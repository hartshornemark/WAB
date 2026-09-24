import {NextResponse} from "next/server";
import {dashboardStatusServices} from "@/composition/services";
import {AuthenticationRequired,CarrierUnavailable} from "@/domain/models";
import {a2CarrierContactsStatus} from "@/domain/carrier-details";
import {b1Statuses} from "@/domain/b1-status";
import {b2Statuses} from "@/domain/b2-status";
import {b3Statuses} from "@/domain/b3-status";
import {b4Statuses} from "@/domain/b4-status";

const aircraftPages=["A5","B5","C1","C2","C3","C4","C5.1","C5.2","C7","C8","C11.1","C11.2","D2","D3","D4","D5","D6","D8","D9","D11","E1.1","E1.2","E2","E3","E4","E5","F1","G1","H1"] as const;

export async function GET(_request:Request,{params}:{params:Promise<{iata:string}>}){
 try{
  const{iata}=await params;
  const[details,density,classes,commodities,crew,passengers,baggage,aircraft]=await(await dashboardStatusServices()).getCarrier(iata);
  const incomplete="incomplete" as const;
  const statuses=Object.fromEntries(aircraftPages.map(code=>[code,incomplete])) as Record<string,"incomplete"|"configured"|"partial"|"skipped"|"not_required"|"auto">;
  statuses.A2=details?a2CarrierContactsStatus(details):incomplete;
  statuses.B1=details&&density&&classes&&commodities?b1Statuses(details,density,classes,commodities).page:incomplete;
  statuses.B2=crew?b2Statuses(crew).page:incomplete;
  statuses.B3=passengers?b3Statuses(passengers).page:incomplete;
  statuses.B4=baggage?b4Statuses(baggage).page:incomplete;
  statuses.C1=aircraft?.rows.length?"configured":incomplete;
  return NextResponse.json({carrier:iata.toUpperCase(),aircraft:null,statuses},{headers:{"Cache-Control":"no-store"}});
 }catch(error){
  if(error instanceof AuthenticationRequired)return NextResponse.json({error:"Authentication required."},{status:401});
  if(error instanceof CarrierUnavailable)return NextResponse.json({error:"Carrier unavailable."},{status:404});
  console.error("Carrier dashboard status failed",error);
  return NextResponse.json({error:"Unable to read dashboard status."},{status:503});
 }
}
