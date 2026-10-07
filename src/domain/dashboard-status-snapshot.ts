import type {DashboardSummaryStatus} from "@/domain/dashboard-summary";
import type {DashboardWork} from "@/domain/dashboard-progress";

export const dashboardStatusCalculationVersion=1;

export type DashboardStatusSnapshot={
  carrierIata:string;
  typeCode:string;
  subtype:string;
  overallStatus:DashboardSummaryStatus;
  attention:string[];
  statuses:Record<string,string>;
  progress:Record<string,DashboardWork>;
  calculationVersion:number;
  updatedAt:string;
};

export const dashboardStatusSnapshotKey=(typeCode:string,subtype:string)=>
  `${typeCode.trim().toUpperCase()}:${subtype.trim().toUpperCase()}`;

export const currentDashboardStatusSnapshot=(snapshot:DashboardStatusSnapshot|undefined):snapshot is DashboardStatusSnapshot=>
  snapshot?.calculationVersion===dashboardStatusCalculationVersion;

export function resolveDashboardStatusSnapshots(
  aircraft:{typeCode:string;subtype:string}[],
  snapshots:DashboardStatusSnapshot[],
){
  const byAircraft=new Map(snapshots.map(snapshot=>[dashboardStatusSnapshotKey(snapshot.typeCode,snapshot.subtype),snapshot]));
  const refreshing:string[]=[];
  const statuses=Object.fromEntries(aircraft.map(row=>{
    const key=dashboardStatusSnapshotKey(row.typeCode,row.subtype);
    const saved=byAircraft.get(key);
    if(!currentDashboardStatusSnapshot(saved)){
      refreshing.push(key);
      return[key,{status:"unavailable" as const,attention:[]}];
    }
    return[key,{status:saved.overallStatus,attention:saved.attention}];
  }));
  return{statuses,refreshing};
}
