"use server";
import { aircraftLayoutServices } from "@/composition/services";
import { aircraftC4Services, aircraftD2Services, aircraftD3Services, aircraftD4Services } from "@/composition/services";
import { carrierDrawingOrigin } from "@/domain/carrier-drawing-origin";
import { buildHoldLayout, holdLayoutUnavailable } from "@/domain/hold-layout";

export async function loadHoldLayout(iata: string, typeCode: string, subtype: string) {
  try {
    // These services authenticate the user and authorise carrier access on each
    // request. Read both snapshots afresh whenever either page opens the diagram.
    const [calibration, d2, d3, d4, c4] = await Promise.all([
      aircraftLayoutServices().then(s=>s.load(iata,typeCode,subtype)),
      aircraftD2Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftD3Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftD4Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftC4Services().then(service => service.get(iata, typeCode, subtype)),
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
    const reason = holdLayoutUnavailable(d2,effectiveCalibration,d3);
    if (reason) return { ok: false as const, error: reason };
    try { return { ok: true as const, layout: buildHoldLayout(d2, d4, d3, effectiveCalibration) }; }
    catch (error) { return { ok: false as const, error: error instanceof Error ? error.message : "Unable to draw this hold layout." }; }
  } catch {
    return { ok: false as const, error: "Unable to load the saved hold layout. Check your access and try again." };
  }
}
