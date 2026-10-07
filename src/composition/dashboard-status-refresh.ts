import {aircraftDashboardReport} from "@/composition/aircraft-dashboard-status";
import {dashboardStatusServices} from "@/composition/services";
import {dashboardAttentionPages,dashboardSummaryStatus} from "@/domain/dashboard-summary";
import {
  dashboardStatusCalculationVersion,
  type DashboardStatusSnapshot,
} from "@/domain/dashboard-status-snapshot";
import {createDashboardStatusSnapshotAdapter} from "@/infrastructure/supabase/dashboard-status-snapshot-adapter";
import {createRequestClient} from "@/infrastructure/supabase/server";

type AircraftIdentity={typeCode:string;subtype:string};

export async function readDashboardStatusSnapshots(iata:string){
  return createDashboardStatusSnapshotAdapter(await createRequestClient()).getMany(iata);
}

export async function refreshDashboardStatusSnapshots(iata:string,aircraft:AircraftIdentity[]){
  if(aircraft.length===0)return;
  const reads=await(await dashboardStatusServices()).getMany(iata,aircraft);
  const calculatedAt=new Date().toISOString();
  const snapshots=reads.flatMap((read,index):DashboardStatusSnapshot[]=>{
    if(read===null)return[];
    const report=aircraftDashboardReport(read);
    return[{
      carrierIata:iata.toUpperCase(),
      typeCode:aircraft[index].typeCode.toUpperCase(),
      subtype:aircraft[index].subtype.toUpperCase(),
      overallStatus:dashboardSummaryStatus(report.statuses),
      attention:dashboardAttentionPages(report.statuses),
      statuses:report.statuses,
      progress:report.progress,
      calculationVersion:dashboardStatusCalculationVersion,
      updatedAt:calculatedAt,
    }];
  });
  await createDashboardStatusSnapshotAdapter(await createRequestClient()).upsertMany(snapshots);
}
