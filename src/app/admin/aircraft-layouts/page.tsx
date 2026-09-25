import Link from "next/link";
import {aircraftLayoutServices} from "@/composition/services";
import { PublishButton } from "./publish-button";
export default async function AircraftLayouts(){
 const versions=await(await aircraftLayoutServices()).list().catch(()=>null);
 if(!versions)return <main className="workspace"><h1>Aircraft layout library</h1><p>Solution administrator access is required.</p><Link href="/carriers">Return to workspace</Link></main>;
 return <main style={{maxWidth:1000,margin:"3rem auto",padding:"2rem"}}><h1>Aircraft layout library</h1><p>Global aircraft outlines and their matching calibration. Published versions serve every authorised carrier using that aircraft type.</p>{versions.map(v=><section key={v.id} style={{background:"white",padding:"1.5rem",margin:"1rem 0",border:"1px solid #d7e1f4",borderRadius:12}}><h2>{v.aircraft_type}-{v.aircraft_subtype}</h2><p>Version {v.version} · {v.active?"PUBLISHED":"AWAITING PUBLICATION"}</p><p>Nose arm: {v.nose_arm_m.toFixed(3)} m. {v.datum_description}</p><p>{v.datum_source}</p></section>)}<PublishButton/><p><Link href="/carriers">Return to workspace</Link></p></main>;
}
