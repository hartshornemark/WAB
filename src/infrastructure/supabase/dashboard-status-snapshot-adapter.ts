import "server-only";
import {DataUnavailable} from "@/domain/models";
import type {DashboardStatusSnapshot} from "@/domain/dashboard-status-snapshot";
import type {Json} from "@/infrastructure/supabase/database.types";
import type {RequestClient} from "@/infrastructure/supabase/server";

type SnapshotRow={
  Carrier_IATA:string;
  Aircraft_Type_IATA:string;
  Aircraft_Series_Subtype:string;
  Overall_Status:string;
  Attention_Pages:Json;
  Page_Statuses:Json;
  Page_Progress:Json;
  Calculation_Version:number;
  Updated_At:string;
};

function snapshot(row:SnapshotRow):DashboardStatusSnapshot{
  if(!["configured","partial","incomplete"].includes(row.Overall_Status)
    ||!Array.isArray(row.Attention_Pages)
    ||!row.Page_Statuses||Array.isArray(row.Page_Statuses)||typeof row.Page_Statuses!=="object"
    ||!row.Page_Progress||Array.isArray(row.Page_Progress)||typeof row.Page_Progress!=="object")throw new DataUnavailable();
  return{
    carrierIata:row.Carrier_IATA,
    typeCode:row.Aircraft_Type_IATA,
    subtype:row.Aircraft_Series_Subtype,
    overallStatus:row.Overall_Status as DashboardStatusSnapshot["overallStatus"],
    attention:row.Attention_Pages.filter((value):value is string=>typeof value==="string"),
    statuses:row.Page_Statuses as Record<string,string>,
    progress:row.Page_Progress as unknown as DashboardStatusSnapshot["progress"],
    calculationVersion:row.Calculation_Version,
    updatedAt:row.Updated_At,
  };
}

export function createDashboardStatusSnapshotAdapter(client:RequestClient){
  const table=()=>client.schema("Basic_Carrier_Record").from("Aircraft_Dashboard_Status_Snapshots");
  return{
    async getMany(iata:string):Promise<DashboardStatusSnapshot[]>{
      const{data,error}=await table().select("Carrier_IATA,Aircraft_Type_IATA,Aircraft_Series_Subtype,Overall_Status,Attention_Pages,Page_Statuses,Page_Progress,Calculation_Version,Updated_At").eq("Carrier_IATA",iata.toUpperCase());
      if(error)throw new DataUnavailable("Unable to load dashboard status snapshots.");
      return(data as unknown as SnapshotRow[]).map(snapshot);
    },
    async upsertMany(rows:DashboardStatusSnapshot[]):Promise<void>{
      if(rows.length===0)return;
      const values=rows.map(row=>({
        Carrier_IATA:row.carrierIata.toUpperCase(),
        Aircraft_Type_IATA:row.typeCode.toUpperCase(),
        Aircraft_Series_Subtype:row.subtype.toUpperCase(),
        Overall_Status:row.overallStatus,
        Attention_Pages:row.attention as Json,
        Page_Statuses:row.statuses as Json,
        Page_Progress:row.progress as unknown as Json,
        Calculation_Version:row.calculationVersion,
        Updated_At:row.updatedAt,
      }));
      const{error}=await table().upsert(values,{onConflict:"Carrier_IATA,Aircraft_Type_IATA,Aircraft_Series_Subtype"});
      if(error)throw new DataUnavailable("Unable to save dashboard status snapshots.");
    },
  };
}
