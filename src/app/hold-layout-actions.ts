"use server";
import { aircraftLayoutServices,aircraftOverlayCalibrationServices } from "@/composition/services";
import { aircraftC4Services, aircraftD2Services, aircraftD3Services, aircraftD4Services } from "@/composition/services";
import { carrierDrawingOrigin } from "@/domain/carrier-drawing-origin";
import { buildHoldLayout, holdLayoutUnavailable } from "@/domain/hold-layout";
import { effectiveAircraftD2Snapshot } from "@/domain/aircraft-d2";
import { effectiveAircraftD3Snapshot } from "@/domain/aircraft-d3";
import { provisionalAircraftLayout } from "@/domain/provisional-aircraft-layout";

export async function loadHoldLayout(iata: string, typeCode: string, subtype: string, fuelConfigurationCode?: string | null) {
  try {
    // These services authenticate the user and authorise carrier access on each
    // request. Read both snapshots afresh whenever either page opens the diagram.
    const [calibration, d2, d3, d4, c4, savedCalibration] = await Promise.all([
      aircraftLayoutServices().then(s=>s.load(iata,typeCode,subtype)).catch(error=>{
        const provisional=provisionalAircraftLayout(typeCode,subtype,process.env.ENABLE_PROVISIONAL_A310_LAYOUT==="true");
        if(provisional)return provisional;
        throw error;
      }),
      aircraftD2Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftD3Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftD4Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftC4Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftOverlayCalibrationServices().then(service=>service.get(iata,typeCode,subtype,"HOLD")),
    ]);
    if(calibration.armUnit && calibration.armUnit!==c4.lengthUnit)return {ok:false as const,error:"Aircraft drawing and C4 length units do not match."};
    // MAX 9 trial calibration follows the carrier's nose arm, as the seat map does.
    // Older templates retain their independently calibrated cargo origins.
    let effectiveCalibration = typeCode === "7M9" && subtype === "900"
      ? {...calibration,noseArm:c4.values.datum,diagramCaption:`Provisional MAX 9 calibration: nose at balance arm ${c4.values.datum} inches. Boeing airport-planning outline.`}
      : calibration;
    if (typeCode === "321" && subtype === "P2F") effectiveCalibration = {
      ...calibration, noseArm: c4.values.datum,
      diagramCaption: `Airbus A321 general outline, shared by both decks. Nose at the saved C4 Balance Arm ${c4.values.datum} m. Hold widths are schematic; conversion-specific cargo doors are not defined by this source.`,
    };
    effectiveCalibration = carrierDrawingOrigin(iata, effectiveCalibration);
    const selectedConfiguration=fuelConfigurationCode?.trim().toUpperCase()||null;
    if(selectedConfiguration&&!d2.fuelConfigurations?.some(item=>item.code===selectedConfiguration))return {ok:false as const,error:"Select a valid fitted fuel configuration."};
    const effectiveD2=effectiveAircraftD2Snapshot(d2,selectedConfiguration);
    const effectiveD3=effectiveAircraftD3Snapshot(d3,selectedConfiguration);
    const reason = holdLayoutUnavailable(effectiveD2,effectiveCalibration,effectiveD3);
    if (reason) return { ok: false as const, error: reason };
    try { return { ok: true as const, calibration:{...savedCalibration,offsetX:savedCalibration.offsetX??0}, layout: buildHoldLayout(effectiveD2, d4, effectiveD3, effectiveCalibration, d2) }; }
    catch (error) { return { ok: false as const, error: error instanceof Error ? error.message : "Unable to draw this hold layout." }; }
  } catch (error) {
    console.error("loadHoldLayout failed", { iata, typeCode, subtype, fuelConfigurationCode, error });
    return { ok: false as const, error: "Unable to load the saved hold layout. Check your access and try again." };
  }
}

export async function lockHoldLayoutCalibration(iata:string,typeCode:string,subtype:string,offsetX:number) {
  try {
    return{ok:true as const,calibration:await aircraftOverlayCalibrationServices().then(service=>service.save(iata,typeCode,subtype,"HOLD",offsetX))};
  }catch(error){
    console.error("save_aircraft_overlay_calibration failed",{iata,typeCode,subtype,error});
    return{ok:false as const,error:"Unable to lock the hold-layout position."};
  }
}
