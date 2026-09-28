export type DashboardSummaryStatus="configured"|"partial"|"incomplete";

const excluded=new Set(["unsupported","out_of_scope","not_required","optional","skipped","not_active"]);
const complete=new Set(["configured","auto"]);

export function dashboardSummaryStatus(statuses:Record<string,string>):DashboardSummaryStatus{
  const assessed=Object.values(statuses).filter(status=>!excluded.has(status));
  if(assessed.length>0&&assessed.every(status=>complete.has(status)))return "configured";
  if(assessed.some(status=>complete.has(status)||status==="partial"))return "partial";
  return "incomplete";
}

export function dashboardAttentionPages(statuses:Record<string,string>):string[]{
  return Object.entries(statuses)
    .filter(([,status])=>!excluded.has(status)&&!complete.has(status))
    .map(([code])=>code);
}
