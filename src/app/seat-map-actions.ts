"use server";
import { aircraftLayoutServices,aircraftOverlayCalibrationServices } from "@/composition/services";
import { aircraftC4Services, aircraftD5Services, aircraftD8Services, aircraftD9Services } from "@/composition/services";
import { carrierDrawingOrigin } from "@/domain/carrier-drawing-origin";
import { provisionalAircraftLayout } from "@/domain/provisional-aircraft-layout";
import { buildSeatMap,seatMapLongitudinalShift } from "@/domain/seat-map";

export async function loadSeatMap(iata:string,typeCode:string,subtype:string) {
  try {
    // Each service authenticates and checks carrier access. Reload saved data on open.
    const [calibration,d8,c4,d5,d9,savedCalibration]=await Promise.all([
      aircraftLayoutServices().then(s=>s.load(iata,typeCode,subtype)).catch(error=>{
        const provisional=provisionalAircraftLayout(typeCode,subtype,process.env.ENABLE_PROVISIONAL_A310_LAYOUT==="true");
        if(provisional)return provisional;
        throw error;
      }),
      aircraftD8Services().then(s=>s.get(iata,typeCode,subtype)),
      aircraftC4Services().then(s=>s.get(iata,typeCode,subtype)),
      aircraftD5Services().then(s=>s.get(iata,typeCode,subtype)),
      aircraftD9Services().then(s=>s.get(iata,typeCode,subtype)),
      aircraftOverlayCalibrationServices().then(service=>service.get(iata,typeCode,subtype,"SEAT")),
    ]);
    const alignedCalibration = carrierDrawingOrigin(iata, calibration);
    const offsetX=savedCalibration.offsetX??seatMapLongitudinalShift(alignedCalibration);
    try{return {ok:true as const,calibration:{...savedCalibration,offsetX},layouts:d9.configurations.length?d9.configurations.map(configuration=>{try{return {code:configuration.code,description:configuration.description,layout:buildSeatMap(d8,c4,d5,configuration,alignedCalibration,offsetX),error:null};}catch(error){return {code:configuration.code,description:configuration.description,layout:null,error:error instanceof Error?error.message:"Check this configuration."};}}):[{code:"",description:"Physical layout (D8)",layout:buildSeatMap(d8,c4,d5,undefined,alignedCalibration,offsetX),error:null}]};}
    catch(error){return {ok:false as const,error:error instanceof Error?error.message:"Unable to draw the seat map."};}
  }catch(error){
    console.error("loadSeatMap failed",{iata,typeCode,subtype,error});
    return {ok:false as const,error:"Unable to load the saved seat map. Check your access and try again."};
  }
}

export async function lockSeatMapCalibration(iata:string,typeCode:string,subtype:string,offsetX:number) {
  try {
    return{ok:true as const,calibration:await aircraftOverlayCalibrationServices().then(service=>service.save(iata,typeCode,subtype,"SEAT",offsetX))};
  } catch(error) {
    console.error("save_aircraft_overlay_calibration failed",{iata,typeCode,subtype,error});
    return{ok:false as const,error:"Unable to lock the seat-map position."};
  }
}
