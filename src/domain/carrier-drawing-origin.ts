import type { AircraftLayoutCalibration } from "./hold-layout";

/** Apply a carrier-specific drawing origin only where the source drawing needs one.
 * 737-800 D2 hold boundaries and D4 doors already use the same Boeing station system.
 */
export function carrierDrawingOrigin(iata: string, calibration: AircraftLayoutCalibration): AircraftLayoutCalibration {
  if (iata !== "KA") return calibration;

  if (calibration.typeCode === "738" && calibration.subtype === "800") {
    return {
      ...calibration,
      stationOriginX: calibration.tailX,
      holdArmOffsets: {...calibration.holdArmOffsets, "1": 68.17},
      diagramCaption: "KA drawing calibration: forward Hold 1 uses a +68.17-inch local alignment to its cargo door; aft Hold 3 uses the saved D2 arms without an additional offset.",
    };
  }

  if (calibration.typeCode !== "7M9" || calibration.subtype !== "900") return calibration;
  return {...calibration,
    stationOriginX: calibration.tailX - 130 * calibration.span / calibration.length,
    diagramCaption: "Aligned to KA D4 cargo-door arms: forward 244–292 inches; aft 1009–1057 inches."};
}
