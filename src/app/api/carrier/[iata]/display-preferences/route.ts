import{NextResponse}from"next/server";
import{detailsServices}from"@/composition/services";
import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";

export async function GET(_request:Request,{params}:{params:Promise<{iata:string}>}){
  try{
    const{iata}=await params;
    const snapshot=await(await detailsServices()).get(iata);
    const places=snapshot.values.indexDecimalPlaces==="2"?2:1;
    return NextResponse.json({indexDecimalPlaces:places},{headers:{"Cache-Control":"no-store"}});
  }catch(error){
    if(error instanceof AuthenticationRequired)return NextResponse.json({error:"Authentication required."},{status:401});
    if(error instanceof CarrierUnavailable)return NextResponse.json({error:"Carrier unavailable."},{status:404});
    return NextResponse.json({error:"Unable to read display preferences."},{status:503});
  }
}
