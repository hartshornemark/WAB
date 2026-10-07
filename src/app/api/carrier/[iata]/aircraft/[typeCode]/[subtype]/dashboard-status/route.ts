import { NextResponse } from "next/server";
import { dashboardStatusServices } from "@/composition/services";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { aircraftDashboardReport } from "@/composition/aircraft-dashboard-status";

export async function GET(_request:Request,{params}:{params:Promise<{iata:string;typeCode:string;subtype:string}>}) {
  try {
    const {iata,typeCode,subtype}=await params;
    const report=aircraftDashboardReport(await (await dashboardStatusServices()).get(iata,typeCode,subtype));
    return NextResponse.json({carrier:iata.toUpperCase(),aircraft:`${typeCode.toUpperCase()}-${subtype.toUpperCase()}`,...report},{headers:{"Cache-Control":"no-store"}});
  } catch(error) {
    if(error instanceof AuthenticationRequired)return NextResponse.json({error:"Authentication required."},{status:401});
    if(error instanceof CarrierUnavailable)return NextResponse.json({error:"Aircraft unavailable."},{status:404});
    console.error("Dashboard status failed",error);
    return NextResponse.json({error:"Unable to read dashboard status."},{status:503});
  }
}
