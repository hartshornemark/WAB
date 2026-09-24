import { notFound, redirect } from "next/navigation";
import { aircraftC1Services, services } from "@/composition/services";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";

export default async function AircraftDashboardPage({params}:{params:Promise<{iata:string;typeCode:string;subtype:string}>}) {
  const {iata,typeCode,subtype}=await params;
  const result=await (await services()).selectCarrier(iata).catch(error=>{
    if(error instanceof AuthenticationRequired) redirect("/login");
    if(error instanceof CarrierUnavailable) notFound();
    throw error;
  });
  const aircraft=await (await aircraftC1Services()).get(iata,typeCode,subtype);
  if(!aircraft.typeCode) notFound();
  const query=new URLSearchParams({
    iata:result.carrier.iata,
    carrier:result.carrier.name,
    type:aircraft.typeCode,
    subtype:aircraft.subtype,
    aircraft:aircraft.identityName||aircraft.aircraftName,
    ...(result.carrier.logoUrl?{logo:result.carrier.logoUrl}:{}),
  });
  redirect(`/mockups/configuration-dashboard.html?${query.toString()}`);
}
