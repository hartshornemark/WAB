import {NextResponse} from "next/server";
import {AuthenticationRequired} from "@/domain/models";
import {resolveDashboardStatusSnapshots} from "@/domain/dashboard-status-snapshot";
import {readDashboardStatusSnapshots} from "@/composition/dashboard-status-refresh";
import {scheduleCarrierDashboardStatusRefresh} from "@/composition/dashboard-status-refresh-schedule";

const requestedAircraft=(request:Request)=>new URL(request.url).searchParams.getAll("aircraft").flatMap(value=>{
  const separator=value.indexOf(":");
  if(separator<1)return[];
  const typeCode=value.slice(0,separator).trim().toUpperCase();
  const subtype=value.slice(separator+1).trim().toUpperCase();
  return/^[A-Z0-9]{3}$/.test(typeCode)&&/^[A-Z0-9-]{1,20}$/.test(subtype)?[{typeCode,subtype}]:[];
}).slice(0,100);

export async function GET(request:Request,{params}:{params:Promise<{iata:string}>}){
  try{
    const{iata}=await params;
    const saved=await readDashboardStatusSnapshots(iata);
    const aircraft=requestedAircraft(request);
    const{statuses,refreshing}=resolveDashboardStatusSnapshots(aircraft.length?aircraft:saved,saved);
    if(refreshing.length)scheduleCarrierDashboardStatusRefresh(iata);
    return NextResponse.json({carrier:iata.toUpperCase(),statuses,refreshing},{headers:{"Cache-Control":"no-store"}});
  }catch(error){
    if(error instanceof AuthenticationRequired)return NextResponse.json({error:"Authentication required."},{status:401});
    console.error("Aircraft dashboard statuses failed",error);
    return NextResponse.json({error:"Unable to read aircraft dashboard statuses."},{status:503});
  }
}
