import type { AircraftLayoutCalibration } from "./hold-layout";

export type LayoutVersion = {
  id:string; aircraft_type:string; aircraft_subtype:string; version:number;
  bucket:string; object_path:string; sha256:string; byte_size:number; nose_arm_m:number;
  datum_description:string; datum_source:string; source_drawing:string;
  calibration:Omit<AircraftLayoutCalibration,"asset">; active?:boolean;
};
const record=(v:unknown):v is Record<string,unknown>=>!!v&&typeof v==="object"&&!Array.isArray(v);
const finite=(v:unknown):v is number=>typeof v==="number"&&Number.isFinite(v);
/** Fail closed rather than plotting a mismatched image and calibration. */
export function parseLayoutVersion(value:unknown):LayoutVersion {
  if(!record(value))throw new Error("No published aircraft outline is available.");
  const c=value.calibration;
  if(!record(c)||typeof value.id!=="string"||typeof value.aircraft_type!=="string"||typeof value.aircraft_subtype!=="string"||!Number.isInteger(value.version)||Number(value.version)<1||value.bucket!=="aircraft-layouts"||typeof value.sha256!=="string"||!/^[a-f0-9]{64}$/.test(value.sha256)||value.object_path!==`${value.aircraft_type}/${value.aircraft_subtype}/${value.sha256}.svg`||!Number.isInteger(value.byte_size)||Number(value.byte_size)<=0||Number(value.byte_size)>2000000||!finite(value.nose_arm_m))throw new Error("Aircraft outline metadata is invalid.");
  if(c.typeCode!==value.aircraft_type||c.subtype!==value.aircraft_subtype||"asset" in c)throw new Error("Aircraft outline calibration does not match its version.");
  for(const key of ["length","noseArm","tailX","span","centreY","cropLeft","cropRight","holdY","holdHeight","leftDoorY","rightDoorY","labelCharWidth"])if(!finite(c[key]))throw new Error(`Aircraft outline calibration is missing ${key}.`);
  if(c.stationOriginX!==undefined&&!finite(c.stationOriginX))throw new Error("Invalid station origin.");
  if(c.armUnit!==undefined&&c.armUnit!=="IN"&&c.armUnit!=="M")throw new Error("Invalid drawing arm units.");
  if(c.combinedHoldProfile!==undefined){const p=c.combinedHoldProfile;if(!record(p)||!finite(p.joinArm)||!Array.isArray(p.points)||p.points.length<2||!p.points.every((v,i,a)=>record(v)&&finite(v.arm)&&finite(v.halfWidth)&&v.halfWidth>0&&(i===0||v.arm>a[i-1].arm)))throw new Error("Invalid hold profile.");}
  const frame=c.imageFrame;
  if(!record(frame)||!["x","y","width","height"].every(key=>finite(frame[key]))||Number(frame.width)<=0||Number(frame.height)<=0||Number(c.length)<=0||Number(c.span)<=0||Number(c.holdHeight)<=0||Number(c.cropLeft)>=Number(c.cropRight))throw new Error("Aircraft outline dimensions are invalid.");
  if(c.holdArmOffsets!==undefined&&(!record(c.holdArmOffsets)||!Object.values(c.holdArmOffsets).every(finite)))throw new Error("Aircraft hold offsets are invalid.");
  if(c.holdArmDefaults!==undefined&&(!record(c.holdArmDefaults)||!Object.values(c.holdArmDefaults).every(v=>record(v)&&finite(v.from)&&finite(v.to)&&v.from<v.to)))throw new Error("Aircraft hold boundaries are invalid.");
  for(const key of ["datum_description","datum_source","source_drawing"])if(typeof value[key]!=="string"||!value[key])throw new Error("Aircraft outline source information is missing.");
  return value as LayoutVersion;
}
