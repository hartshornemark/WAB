import type { AircraftLayoutCalibration } from "./hold-layout";

const A310_300_PROVISIONAL_LAYOUT = {
  typeCode: "310",
  subtype: "300",
  length: 46.66,
  noseArm: 6.3825,
  armUnit: "M",
  tailX: 244,
  span: 240,
  centreY: 25,
  asset: "/aircraft-layouts/a310-300-provisional.svg?v=e4dfa29d0fd9",
  imageFrame: { x: 0, y: 0, width: 248, height: 50 },
  cropLeft: 0,
  cropRight: 248,
  holdY: 15,
  holdHeight: 20,
  leftDoorY: 14,
  rightDoorY: 36,
  labelCharWidth: 0.58,
  seatMapNoseArm: 6.3825,
  seatMapCaption: "Provisional A310-300 review alignment uses the 6.3825 m candidate nose datum. The saved C4 datum is unchanged.",
  reviewDoorArmOffset: 1.9675,
  diagramCaption: "Provisional A310-300 review calibration from the supplied Airbus plan drawing. This comparison uses the 6.3825 m candidate nose datum; saved D4 door arms are shifted by 1.9675 m for display only and are not changed in the database.",
} satisfies AircraftLayoutCalibration;

/** Local review layouts never replace or publish the shared master library. */
export function provisionalAircraftLayout(typeCode: string, subtype: string, enabled: boolean): AircraftLayoutCalibration | undefined {
  return enabled && typeCode === "310" && subtype === "300" ? A310_300_PROVISIONAL_LAYOUT : undefined;
}
