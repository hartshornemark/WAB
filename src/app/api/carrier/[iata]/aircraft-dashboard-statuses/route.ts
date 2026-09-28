import {NextResponse} from "next/server";
import {carrierHomeServices,dashboardStatusServices} from "@/composition/services";
import {AuthenticationRequired,CarrierUnavailable} from "@/domain/models";
import {dashboardAttentionPages,dashboardSummaryStatus} from "@/domain/dashboard-summary";
import {aircraftDashboardStatuses,type AircraftDashboardRead} from "@/app/api/carrier/aircraft-dashboard-status";

export async function GET(_request:Request,{params}:{params:Promise<{iata:string}>}){
  try{
    const{iata}=await params;
    const home=await(await carrierHomeServices()).get(iata);
    const service=await dashboardStatusServices();
    const reads=await service.getMany(iata,home.aircraft.rows);
    const statuses=Object.fromEntries(home.aircraft.rows.map((aircraft,index)=>{
      const key=`${aircraft.typeCode.trim().toUpperCase()}:${aircraft.subtype.trim().toUpperCase()}`;
      if(reads[index]===null)return[key,{status:"unavailable",attention:[]}];
      const pages=aircraftDashboardStatuses(reads[index] as AircraftDashboardRead);
      return[key,{status:dashboardSummaryStatus(pages),attention:dashboardAttentionPages(pages)}];
    }));
    return NextResponse.json({carrier:iata.toUpperCase(),statuses},{headers:{"Cache-Control":"no-store"}});
  }catch(error){
    if(error instanceof AuthenticationRequired)return NextResponse.json({error:"Authentication required."},{status:401});
    if(error instanceof CarrierUnavailable)return NextResponse.json({error:"Carrier unavailable."},{status:404});
    console.error("Aircraft dashboard statuses failed",error);
    return NextResponse.json({error:"Unable to read aircraft dashboard statuses."},{status:503});
  }
}
