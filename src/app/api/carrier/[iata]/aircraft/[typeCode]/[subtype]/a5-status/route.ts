import{NextResponse}from"next/server";
import{aircraftC2Services}from"@/composition/services";
import{a5AutomaticDocumentsStatus}from"@/domain/a5-status";
import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";

export async function GET(_request:Request,{params}:{params:Promise<{iata:string;typeCode:string;subtype:string}>}){
  try{
    const{iata,typeCode,subtype}=await params;
    const snapshot=await(await aircraftC2Services()).get(iata,typeCode,subtype);
    return NextResponse.json({status:a5AutomaticDocumentsStatus(snapshot)},{headers:{"Cache-Control":"no-store"}});
  }catch(error){
    if(error instanceof AuthenticationRequired)return NextResponse.json({error:"Authentication required."},{status:401});
    if(error instanceof CarrierUnavailable)return NextResponse.json({error:"Aircraft unavailable."},{status:404});
    return NextResponse.json({error:"Unable to read A5 status."},{status:503});
  }
}
