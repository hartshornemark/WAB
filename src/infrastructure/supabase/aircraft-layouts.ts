import "server-only";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { join } from "node:path";
import type { AircraftLayoutRepository } from "@/ports/aircraft-layout-repository";
import type { RequestClient } from "./server";
import { parseLayoutVersion } from "@/domain/aircraft-layout-template";

async function loadAircraftLayout(client:RequestClient,iata:string,typeCode:string,subtype:string) {
  const {data,error}=await client.schema("Basic_Carrier_Record").rpc("get_aircraft_layout",{p_iata:iata,p_type:typeCode,p_subtype:subtype});
  if(error){console.error("get_aircraft_layout failed",{iata,typeCode,subtype,error});throw new Error("Unable to load the aircraft outline library.");}
  const version=parseLayoutVersion(data);
  if(version.aircraft_type!==typeCode||version.aircraft_subtype!==subtype)throw new Error("Aircraft outline does not match this aircraft.");
  // Private, immutable object. Its URL and calibration always come from one version.
  const signed=await client.storage.from(version.bucket).createSignedUrl(version.object_path,3600);
  if(signed.error||!signed.data)throw new Error("The aircraft outline file is unavailable.");
  const calibration = version.aircraft_type === "359" && version.aircraft_subtype === "900" && version.version < 8
    ? {...version.calibration,holdArmOffsets:{...version.calibration.holdArmOffsets,FWD:3.4,AFT:-3.4,ALB:-3.4}}
    : version.calibration;
  return {...calibration,asset:signed.data.signedUrl};
}

async function publishVerifiedAircraftLayouts(client:RequestClient) {
  try {
    // This RPC requires global administrator permission before reading local assets.
    const {data,error}=await client.schema("Basic_Carrier_Record").rpc("aircraft_layout_library",{});
    if(error||!Array.isArray(data))throw new Error("Administrator access is required.");
    const versions=data.map(parseLayoutVersion);
    // Read at publication time so a long-running workspace cannot retain an
    // older manifest after a newly verified aircraft template is added.
    const seeds=JSON.parse(await readFile(join(process.cwd(),"src/infrastructure/aircraft-layouts/seed.json"),"utf8")) as Array<{
      typeCode:string;
      subtype:string;
      version:number;
      file:string;
      sha256:string;
      calibration:Record<string,unknown>;
    }>;
    for(const seed of seeds) {
      const version=versions.find(v=>v.aircraft_type===seed.typeCode&&v.aircraft_subtype===seed.subtype&&v.version===seed.version);
      if(!version||version.sha256!==seed.sha256||canonical(version.calibration)!==canonical(seed.calibration))throw new Error(`Template ${seed.typeCode}-${seed.subtype}: ${!version?"version missing":version.sha256!==seed.sha256?"SVG checksum differs":Object.keys(seed.calibration).filter(k=>canonical((version.calibration as unknown as Record<string,unknown>)[k])!==canonical((seed.calibration as unknown as Record<string,unknown>)[k])).join(", ")} calibration mismatch.`);
      const bytes=await readFile(join(process.cwd(),"src/assets/aircraft-layouts",seed.file));
      if(bytes.length!==version.byte_size||createHash("sha256").update(bytes).digest("hex")!==version.sha256)throw new Error("Aircraft SVG verification failed.");
      const bucket=client.storage.from(version.bucket);
      const existing=await bucket.download(version.object_path);
      if(existing.error) {
        const upload=await bucket.upload(version.object_path,bytes,{contentType:"image/svg+xml",cacheControl:"31536000",upsert:false});
        if(upload.error)throw new Error("Unable to upload the aircraft outline.");
      }
      const check=await bucket.download(version.object_path);
      if(check.error||!check.data||createHash("sha256").update(Buffer.from(await check.data.arrayBuffer())).digest("hex")!==version.sha256)throw new Error("The stored SVG did not pass verification.");
      // Do not roll a newer published version back when rerunning the initial import.
      if(!versions.some(v=>v.aircraft_type===seed.typeCode&&v.aircraft_subtype===seed.subtype&&v.active&&v.version>seed.version)) {
        const activated=await client.schema("Basic_Carrier_Record").rpc("activate_aircraft_layout",{p_id:version.id});
        if(activated.error)throw new Error("The SVG was uploaded but could not be published.");
      }
    }
    return {ok:true,message:`${seeds.length} aircraft template versions are verified and published.`};
  }catch(error){return {ok:false,message:error instanceof Error?error.message:"Unable to publish aircraft templates."};}
}
async function publishVerifiedAircraftLayoutVersion(client:RequestClient,typeCode:string,subtype:string,versionNumber:number) {
  try {
    const {data,error}=await client.schema("Basic_Carrier_Record").rpc("aircraft_layout_library",{});
    if(error||!Array.isArray(data))throw new Error("Administrator access is required.");
    const versions=data.map(parseLayoutVersion);
    const seeds=JSON.parse(await readFile(join(process.cwd(),"src/infrastructure/aircraft-layouts/seed.json"),"utf8")) as Array<{
      typeCode:string;subtype:string;version:number;file:string;sha256:string;calibration:Record<string,unknown>;
    }>;
    const seed=seeds.find(item=>item.typeCode===typeCode&&item.subtype===subtype&&item.version===versionNumber);
    const version=versions.find(item=>item.aircraft_type===typeCode&&item.aircraft_subtype===subtype&&item.version===versionNumber);
    if(!seed||!version)throw new Error("The requested aircraft template version is unavailable.");
    if(version.sha256!==seed.sha256||canonical(version.calibration)!==canonical(seed.calibration))throw new Error("The requested aircraft template does not match its verified local calibration.");
    const bytes=await readFile(join(process.cwd(),"src/assets/aircraft-layouts",seed.file));
    if(bytes.length!==version.byte_size||createHash("sha256").update(bytes).digest("hex")!==version.sha256)throw new Error("Aircraft SVG verification failed.");
    const bucket=client.storage.from(version.bucket);
    const existing=await bucket.download(version.object_path);
    if(existing.error){const upload=await bucket.upload(version.object_path,bytes,{contentType:"image/svg+xml",cacheControl:"31536000",upsert:false});if(upload.error)throw new Error("Unable to upload the aircraft outline.");}
    const check=await bucket.download(version.object_path);
    if(check.error||!check.data||createHash("sha256").update(Buffer.from(await check.data.arrayBuffer())).digest("hex")!==version.sha256)throw new Error("The stored SVG did not pass verification.");
    const activated=await client.schema("Basic_Carrier_Record").rpc("activate_aircraft_layout",{p_id:version.id});
    if(activated.error)throw new Error("The SVG was uploaded but could not be published.");
    return {ok:true,message:`${typeCode}-${subtype} version ${versionNumber} is verified and published.`};
  }catch(error){return {ok:false,message:error instanceof Error?error.message:"Unable to publish the aircraft template."};}
}
function canonical(value:unknown):string {
  if(typeof value==="number")return JSON.stringify(Number(value.toPrecision(14)));
  if(Array.isArray(value))return JSON.stringify(value.map(v=>JSON.parse(canonical(v))));
  if(value&&typeof value==="object"&&!Array.isArray(value))return JSON.stringify(Object.fromEntries(Object.entries(value).sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>[k,JSON.parse(canonical(v))])));
  return JSON.stringify(value);
}

export function createAircraftLayoutAdapter(client:RequestClient):AircraftLayoutRepository {
 return {
  load:(iata,typeCode,subtype)=>loadAircraftLayout(client,iata,typeCode,subtype),
  async list(){const {data,error}=await client.schema("Basic_Carrier_Record").rpc("aircraft_layout_library",{});if(error||!Array.isArray(data))throw new Error("Solution administrator access is required.");return data.map(parseLayoutVersion);},
  publishVerified:()=>publishVerifiedAircraftLayouts(client),
  publishVersion:(typeCode,subtype,version)=>publishVerifiedAircraftLayoutVersion(client,typeCode,subtype,version),
 };
}
