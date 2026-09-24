export type ConfigurationStatus="incomplete"|"partial"|"configured";
export type NeutralConfigurationStatus="unsupported"|"out_of_scope"|"skipped"|"not_active"|"not_required"|"optional";
export type DisplayConfigurationStatus=ConfigurationStatus|NeutralConfigurationStatus;

export const configurationStatusLabels:Record<DisplayConfigurationStatus,string>={
  incomplete:"INCOMPLETE",
  partial:"PARTIALLY CONFIGURED",
  configured:"CONFIGURED",
  unsupported:"UNSUPPORTED",
  out_of_scope:"OUT OF SCOPE",
  skipped:"SKIPPED",
  not_active:"NOT ACTIVE",
  not_required:"NOT REQUIRED",
  optional:"OPTIONAL"
};

export function aggregateConfigurationStatuses(statuses:ConfigurationStatus[]):ConfigurationStatus{
  if(statuses.length>0&&statuses.every(status=>status==="configured"))return"configured";
  if(statuses.length===0||statuses.every(status=>status==="incomplete"))return"incomplete";
  return"partial";
}
