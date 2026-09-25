import type { AircraftLayoutCalibration } from "../../src/domain/hold-layout";
// Each outline has its own longitudinal and vertical calibration. Both vectors
// are plan views isolated from their Airbus general-arrangement DWGs; neither
// aircraft is produced by stretching the other outline.
export const A319_LAYOUT = {
  typeCode: "319", subtype: "100", length: 33.84, noseArm: 2.540,
  // The Airbus plan occupies x=137.4..330.3 after the engine-bounded crop.
  tailX: 330.3, span: 192.9, centreY: 363,
  asset: "/aircraft-layouts/a319-100-fuselage?v=1800f1d81420",
  imageFrame: { x: 102, y: 327.25, width: 236, height: 72 },
  cropLeft: 102, cropRight: 338,
  holdY: 352, holdHeight: 22, leftDoorY: 347, rightDoorY: 377,
  labelCharWidth: 0.58,
} satisfies AircraftLayoutCalibration;
export const A320_LAYOUT = {
  typeCode: "320", subtype: "200", length: 37.57, noseArm: 0,
  // The Airbus plan occupies x=123.5..337.8 after the engine-bounded crop.
  tailX: 337.8, span: 214.3, centreY: 359.5,
  asset: "/aircraft-layouts/a320-200-fuselage?v=f5de949b13d9",
  imageFrame: { x: 102, y: 327.25, width: 236, height: 72 },
  cropLeft: 102, cropRight: 338,
  holdY: 348.5, holdHeight: 22, leftDoorY: 344, rightDoorY: 374,
  labelCharWidth: 0.58,
  // Align the complete aft cargo group with the aft cargo-door edge in the
  // isolated Airbus plan. Correct the drawing only; the carrier's saved D2
  // balance-arm values remain authoritative.
  holdArmOffsets: { "3": -2.735, "4": -2.735, "5": -2.735 },
  // Physical hold boundaries established from the Airbus A320-200 general
  // arrangement drawing. They let every carrier use the global aircraft-type
  // layout when optional D2 From/To values have not been supplied.
  holdArmDefaults: {
    "1": { from: 7.255, to: 12.205 },
    "3": { from: 21.412, to: 24.480 },
    "4": { from: 24.480, to: 27.548 },
    "5": { from: 27.548, to: 31.212 },
  },
} satisfies AircraftLayoutCalibration;
export const AIRCRAFT_LAYOUTS = [A319_LAYOUT, A320_LAYOUT] as const;
export function aircraftLayoutFor(typeCode: string, subtype: string): AircraftLayoutCalibration | undefined {
  return AIRCRAFT_LAYOUTS.find(layout => layout.typeCode === typeCode && layout.subtype === subtype);
}
