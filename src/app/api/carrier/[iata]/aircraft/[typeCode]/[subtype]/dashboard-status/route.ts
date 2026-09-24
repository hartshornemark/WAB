import { NextResponse } from "next/server";
import { dashboardStatusServices } from "@/composition/services";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { a2CarrierContactsStatus } from "@/domain/carrier-details";
import { a5AutomaticDocumentsStatus } from "@/domain/a5-status";
import { b1Statuses } from "@/domain/b1-status";
import { b2Statuses } from "@/domain/b2-status";
import { b3Statuses } from "@/domain/b3-status";
import { b4Statuses } from "@/domain/b4-status";
import { b5Completion } from "@/domain/b5-status";
import { aircraftC1Statuses } from "@/domain/aircraft-c1-status";
import { aircraftC2Statuses, aircraftC5ApplicabilityFromC2 } from "@/domain/aircraft-c2-status";
import { aircraftC4Status } from "@/domain/aircraft-c4-status";
import { aircraftC5Statuses } from "@/domain/aircraft-c5-status";
import { aircraftC7Statuses } from "@/domain/aircraft-c7-status";
import { aircraftC8Statuses } from "@/domain/aircraft-c8-status";
import { aircraftC11Status } from "@/domain/aircraft-c11-status";
import { aircraftD2Status } from "@/domain/aircraft-d2-status";
import { aircraftD3Status } from "@/domain/aircraft-d3-status";
import { aircraftD4Status } from "@/domain/aircraft-d4-status";
import { aircraftD5Status } from "@/domain/aircraft-d5-status";
import { aircraftD6Status } from "@/domain/aircraft-d6-status";
import { aircraftD8Status } from "@/domain/aircraft-d8-status";
import { aircraftD9Status } from "@/domain/aircraft-d9-status";
import { aircraftD11Status } from "@/domain/aircraft-d11-status";
import { aircraftE11Status } from "@/domain/aircraft-e11-status";
import { aircraftE12Status } from "@/domain/aircraft-e12-status";
import { aircraftE2Status } from "@/domain/aircraft-e2-status";
import { aircraftE3Status } from "@/domain/aircraft-e3-status";
import { aircraftE4Status } from "@/domain/aircraft-e4-status";
import { aircraftE5Status } from "@/domain/aircraft-e5-status";
import { aircraftF1Status } from "@/domain/aircraft-f1-status";
import { aircraftG1DashboardStatus } from "@/domain/aircraft-g1-status";
import { aircraftH1Status } from "@/domain/aircraft-h1-status";

export async function GET(_request:Request,{params}:{params:Promise<{iata:string;typeCode:string;subtype:string}>}) {
  try {
    const {iata,typeCode,subtype}=await params;
    const [details,density,classes,commodities,crew,passengers,baggage,uld,c1,c2,c4,c5,c7,c8,c11,d2,d3,d4,d5,d6,d8,d9,d11,e11,e12,e2,e3,e4,e5,f1,g1,h1]=await (await dashboardStatusServices()).get(iata,typeCode,subtype);
    const incomplete="incomplete" as const;
    const operatingRole=c1?.operatingRole??"PASSENGER";
    const passengerOperations=operatingRole!=="FREIGHTER";
    const c4Page=c4?aircraftC4Status(c4):incomplete;
    const c5Page=c5&&c2?aircraftC5Statuses(c5.values,aircraftC5ApplicabilityFromC2(c2)).page:incomplete;
    const c11Page=c11?aircraftC11Status(c11):incomplete;
    const d9Formula=c4&&c4Page==="configured"?{referenceArm:c4.values.referenceArm,constantC:c4.values.constantC}:undefined;
    const statuses={
      A2:details?a2CarrierContactsStatus(details):incomplete,A5:c2?a5AutomaticDocumentsStatus(c2):incomplete,
      B1:details&&density&&classes&&commodities?b1Statuses(details,density,classes,commodities,passengerOperations).page:incomplete,B2:crew?b2Statuses(crew).page:incomplete,B3:passengerOperations?(passengers?b3Statuses(passengers).page:incomplete):"not_required",B4:passengerOperations?(baggage?b4Statuses(baggage).page:incomplete):"not_required",B5:uld?b5Completion(uld).page:incomplete,
      C1:c1?aircraftC1Statuses(c1).page:incomplete,C2:c2?aircraftC2Statuses(c2,operatingRole).page:incomplete,C3:c2?aircraftC2Statuses(c2,operatingRole).page:incomplete,C4:c4Page,"C5.1":c5Page,"C5.2":c5Page==="configured"?"auto":incomplete,C7:c7?aircraftC7Statuses(c7.values,c5?.values.maximumWeights.mrw||null).page:incomplete,C8:c8?aircraftC8Statuses(c8.values).page:incomplete,"C11.1":c11Page,"C11.2":c11Page==="configured"?"auto":incomplete,
      D2:d2?aircraftD2Status(d2):incomplete,D3:d3?aircraftD3Status(d3):incomplete,D4:d4?aircraftD4Status(d4):incomplete,D5:d5?aircraftD5Status(d5,operatingRole):incomplete,D6:d6?aircraftD6Status(d6):incomplete,D8:d8?aircraftD8Status(d8,operatingRole):incomplete,D9:d9?aircraftD9Status(d9,d9Formula,operatingRole):incomplete,D11:d11?aircraftD11Status(d11):incomplete,
      "E1.1":e11?aircraftE11Status(e11):incomplete,"E1.2":e12?aircraftE12Status(e12):incomplete,E2:e2?aircraftE2Status(e2):incomplete,E3:e3?aircraftE3Status(e3):incomplete,E4:e4?aircraftE4Status(e4):incomplete,E5:e5?aircraftE5Status(e5):incomplete,
      F1:f1?aircraftF1Status(f1):incomplete,G1:aircraftG1DashboardStatus(g1,d2?.uldApplicable),H1:h1?aircraftH1Status(h1):incomplete,
    } as const;
    return NextResponse.json({carrier:iata.toUpperCase(),aircraft:`${typeCode.toUpperCase()}-${subtype.toUpperCase()}`,statuses},{headers:{"Cache-Control":"no-store"}});
  } catch(error) {
    if(error instanceof AuthenticationRequired)return NextResponse.json({error:"Authentication required."},{status:401});
    if(error instanceof CarrierUnavailable)return NextResponse.json({error:"Aircraft unavailable."},{status:404});
    console.error("Dashboard status failed",error);
    return NextResponse.json({error:"Unable to read dashboard status."},{status:503});
  }
}
