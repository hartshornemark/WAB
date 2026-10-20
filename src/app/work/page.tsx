import Image from "next/image";
import Link from "next/link";
import {redirect} from "next/navigation";
import {services} from "@/composition/services";
import {WorkspaceShell} from "@/components/workspace-shell";
import {ContactUsLink} from "@/components/contact-us-link";

const options=[
  {title:"Airport Configuration",description:"Review and maintain the airport reference data used throughout the solution.",icon:"/work-options/airports.png",href:"/admin/airports",direct:true},
  {title:"Schedule Creation / Amendment",description:"Create, import, review and amend a carrier's published flight schedules.",icon:"/work-options/schedules.png",href:"/carriers?work=schedules",direct:false},
  {title:"Load Control",description:"Open your combined operational workload across authorised carriers and locations.",icon:"/work-options/load-control.png",href:"/load-control",direct:true},
  {title:"AHM560 / 565 Database",description:"Configure carrier standards, aircraft data and weight-and-balance requirements.",icon:"/work-options/ahm.png",href:"/carriers?work=ahm",direct:false},
  {title:"User Administration",description:"Create users and manage their carrier, location and permission assignments.",icon:"/work-options/users.svg",href:"/admin/users",direct:true},
] as const;

export default async function WorkPage(){
  const user=await(await services()).currentUser();
  if(!user)redirect("/login");
  return <WorkspaceShell user={user}>
    <section className="work-option-introduction"><div className="work-option-heading"><p className="eyebrow">YOUR WORKSPACE</p><h1>What would you like to work on?</h1><p>Select an operational area to continue.</p></div><ContactUsLink /></section>
    <div className="work-option-grid">{options.map(option=><Link className="work-option-card" href={option.href} key={option.title}>
      <span className="work-option-icon"><Image src={option.icon} alt="" width={128} height={128} unoptimized/></span>
      <span className="work-option-copy"><span className="work-option-access">{option.direct?"OPEN WORKSPACE":"SELECT CARRIER"}</span><strong>{option.title}</strong><span>{option.description}</span></span>
      <span className="work-option-arrow" aria-hidden="true">→</span>
    </Link>)}</div>
  </WorkspaceShell>;
}
