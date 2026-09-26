"use server";
import { aircraftLayoutServices } from "@/composition/services";
import { aircraftC4Services, aircraftD5Services, aircraftD8Services, aircraftD9Services } from "@/composition/services";
import { carrierDrawingOrigin } from "@/domain/carrier-drawing-origin";
import { buildSeatMap } from "@/domain/seat-map";

export async function loadSeatMap(iata:string,typeCode:string,subtype:string) {
  try {
    // Each service authenticates and checks carrier access. Reload saved data on open.
    const [calibration,d8,c4,d5,d9]=await Promise.all([
      aircraftLayoutServices().then(s=>s.load(iata,typeCode,subtype)),
      aircraftD8Services().then(s=>s.get(iata,typeCode,subtype)),
      aircraftC4Services().then(s=>s.get(iata,typeCode,subtype)),
      aircraftD5Services().then(s=>s.get(iata,typeCode,subtype)),
      aircraftD9Services().then(s=>s.get(iata,typeCode,subtype)),
    ]);
    const alignedCalibration = carrierDrawingOrigin(iata, calibration);
    try{return {ok:true as const,layouts:d9.configurations.length?d9.configurations.map(configuration=>{try{return {code:configuration.code,description:configuration.description,layout:buildSeatMap(d8,c4,d5,configuration,alignedCalibration),error:null};}catch(error){return {code:configuration.code,description:configuration.description,layout:null,error:error instanceof Error?error.message:"Check this configuration."};}}):[{code:"",description:"Physical layout (D8)",layout:buildSeatMap(d8,c4,d5,undefined,alignedCalibration),error:null}]};}
    catch(error){return {ok:false as const,error:error instanceof Error?error.message:"Unable to draw the seat map."};}
  }catch{return {ok:false as const,error:"Unable to load the saved seat map. Check your access and try again."};}
}
