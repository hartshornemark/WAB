import type { AircraftLayoutCalibration } from "./hold-layout";

/** KA D4 cargo-door arms match the Boeing drawing doors when adding 130 inches.
 * This provisional drawing origin applies to 737 seats and holds, independently of C4.
 */
export function carrierDrawingOrigin(iata: string, calibration: AircraftLayoutCalibration): AircraftLayoutCalibration {
  const supported737 = (calibration.typeCode === "7M9" && calibration.subtype === "900")
    || (calibration.typeCode === "738" && calibration.subtype === "800");
  if (iata !== "KA" || !supported737) return calibration;
  return {...calibration,
    stationOriginX: calibration.tailX - 130 * calibration.span / calibration.length,
    diagramCaption: "Aligned to KA D4 cargo-door arms: forward 244–292 inches; aft 1009–1057 inches."};
}
