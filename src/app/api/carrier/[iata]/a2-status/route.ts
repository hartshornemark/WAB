import{NextResponse}from"next/server";
import{detailsServices}from"@/composition/services";
import{a2CarrierContactsStatus}from"@/domain/carrier-details";
import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";

export async function GET(_request:Request,{params}:{params:Promise<{iata:string}>}){
  try{
    const{iata}=await params;
    const snapshot=await(await detailsServices()).get(iata);
    return NextResponse.json({status:a2CarrierContactsStatus(snapshot)},{headers:{"Cache-Control":"no-store"}});
  }catch(error){
    if(error instanceof AuthenticationRequired)return NextResponse.json({error:"Authentication required."},{status:401});
    if(error instanceof CarrierUnavailable)return NextResponse.json({error:"Carrier unavailable."},{status:404});
    return NextResponse.json({error:"Unable to read A2 status."},{status:503});
  }
}
