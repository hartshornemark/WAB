import type { AircraftLayoutCalibration } from "./hold-layout";

export type LayoutVersion = {
  id:string; aircraft_type:string; aircraft_subtype:string; version:number;
  asset_aircraft_type?:string; asset_aircraft_subtype?:string;
  geometry_family_code?:string; geometry_profile_code?:string;
  bucket:string; object_path:string; sha256:string; byte_size:number; nose_arm_m:number;
  datum_description:string; datum_source:string; source_drawing:string;
  calibration:Omit<AircraftLayoutCalibration,"asset">; active?:boolean;
};
const record=(v:unknown):v is Record<string,unknown>=>!!v&&typeof v==="object"&&!Array.isArray(v);
const finite=(v:unknown):v is number=>typeof v==="number"&&Number.isFinite(v);
const nonEmptyStrings=(value:unknown):value is string[]=>Array.isArray(value)&&value.length>0&&value.every(item=>typeof item==="string"&&item.trim()!=="");
const validArrangementOption=(value:unknown)=>record(value)&&typeof value.id==="string"&&value.id.trim()!==""
  &&typeof value.label==="string"&&value.label.trim()!==""&&nonEmptyStrings(value.includedPositionIds)
  &&(value.uldCode===undefined||typeof value.uldCode==="string"&&value.uldCode.trim()!=="")
  &&(value.referencePositionId===undefined||typeof value.referencePositionId==="string"&&value.referencePositionId.trim()!=="")
  &&(value.referenceUldCode===undefined||typeof value.referenceUldCode==="string"&&value.referenceUldCode.trim()!=="")
  &&(value.excludedPositionIds===undefined||Array.isArray(value.excludedPositionIds)&&value.excludedPositionIds.every(id=>typeof id==="string"&&id.trim()!==""));
const validArrangementSelector=(value:unknown)=>record(value)&&typeof value.holdId==="string"&&value.holdId.trim()!==""
  &&typeof value.uldType==="string"&&value.uldType.trim()!==""&&typeof value.label==="string"&&value.label.trim()!==""
  &&Array.isArray(value.options)&&value.options.length>0&&value.options.every(validArrangementOption);
/** Fail closed rather than plotting a mismatched image and calibration. */
export function parseLayoutVersion(value:unknown):LayoutVersion {
  if(!record(value))throw new Error("No published aircraft outline is available.");
  const c=value.calibration;
  const assetType=value.asset_aircraft_type??value.aircraft_type;
  const assetSubtype=value.asset_aircraft_subtype??value.aircraft_subtype;
  if(!record(c)||typeof value.id!=="string"||typeof value.aircraft_type!=="string"||typeof value.aircraft_subtype!=="string"||typeof assetType!=="string"||typeof assetSubtype!=="string"||!Number.isInteger(value.version)||Number(value.version)<1||value.bucket!=="aircraft-layouts"||typeof value.sha256!=="string"||!/^[a-f0-9]{64}$/.test(value.sha256)||value.object_path!==`${assetType}/${assetSubtype}/${value.sha256}.svg`||!Number.isInteger(value.byte_size)||Number(value.byte_size)<=0||Number(value.byte_size)>2000000||!finite(value.nose_arm_m))throw new Error("Aircraft outline metadata is invalid.");
  if(c.typeCode!==value.aircraft_type||c.subtype!==value.aircraft_subtype||"asset" in c)throw new Error("Aircraft outline calibration does not match its version.");
  for(const key of ["length","noseArm","tailX","span","centreY","cropLeft","cropRight","holdY","holdHeight","leftDoorY","rightDoorY","labelCharWidth"])if(!finite(c[key]))throw new Error(`Aircraft outline calibration is missing ${key}.`);
  if(c.stationOriginX!==undefined&&!finite(c.stationOriginX))throw new Error("Invalid station origin.");
  if(c.armUnit!==undefined&&c.armUnit!=="IN"&&c.armUnit!=="M")throw new Error("Invalid drawing arm units.");
  if(c.combinedHoldProfile!==undefined){const p=c.combinedHoldProfile;if(!record(p)||!finite(p.joinArm)||!Array.isArray(p.points)||p.points.length<2||!p.points.every((v,i,a)=>record(v)&&finite(v.arm)&&finite(v.halfWidth)&&v.halfWidth>0&&(i===0||v.arm>a[i-1].arm)))throw new Error("Invalid hold profile.");}
  if(c.holdProfiles!==undefined&&(!record(c.holdProfiles)||!Object.values(c.holdProfiles).every(p=>record(p)&&Array.isArray(p.points)&&p.points.length>=2&&p.points.every((v,i,a)=>record(v)&&finite(v.arm)&&finite(v.halfWidth)&&v.halfWidth>0&&(i===0||v.arm>a[i-1].arm)))))throw new Error("Invalid individual hold profile.");
  const frame=c.imageFrame;
  if(!record(frame)||!["x","y","width","height"].every(key=>finite(frame[key]))||Number(frame.width)<=0||Number(frame.height)<=0||Number(c.length)<=0||Number(c.span)<=0||Number(c.holdHeight)<=0||Number(c.cropLeft)>=Number(c.cropRight))throw new Error("Aircraft outline dimensions are invalid.");
  if(c.holdArmOffsets!==undefined&&(!record(c.holdArmOffsets)||!Object.values(c.holdArmOffsets).every(finite)))throw new Error("Aircraft hold offsets are invalid.");
  if(c.holdArmDefaults!==undefined&&(!record(c.holdArmDefaults)||!Object.values(c.holdArmDefaults).every(v=>record(v)&&finite(v.from)&&finite(v.to)&&v.from<v.to)))throw new Error("Aircraft hold boundaries are invalid.");
  if(c.holdSubdivisionBreaks!==undefined&&(!record(c.holdSubdivisionBreaks)||!Object.values(c.holdSubdivisionBreaks).every(v=>Array.isArray(v)&&v.every(finite)&&v.every((n,i,a)=>i===0||n>a[i-1]))))throw new Error("Aircraft compartment boundaries are invalid.");
  if(c.holdSubdivisionDoorStarts!==undefined&&(!record(c.holdSubdivisionDoorStarts)||!Object.values(c.holdSubdivisionDoorStarts).every(v=>Array.isArray(v)&&v.every(id=>typeof id==="string"&&id.trim()!==""))))throw new Error("Aircraft compartment door anchors are invalid.");
  if(c.uldArrangementSelectors!==undefined&&(!Array.isArray(c.uldArrangementSelectors)||!c.uldArrangementSelectors.every(validArrangementSelector)))throw new Error("Aircraft ULD arrangement selectors are invalid.");
  for(const key of ["datum_description","datum_source","source_drawing"])if(typeof value[key]!=="string"||!value[key])throw new Error("Aircraft outline source information is missing.");
  return value as LayoutVersion;
}
