import{configurationStatusLabels,type DisplayConfigurationStatus}from"@/domain/configuration-status";

export function ConfigurationStatusBadge({status,variant="compact"}:{status:DisplayConfigurationStatus;variant?:"compact"|"large"}){
  const label=configurationStatusLabels[status];
  return <span className={`configuration-status-badge status-${status} variant-${variant}`} aria-label={`Configuration status: ${label}`}>
    <span className="configuration-status-icon" aria-hidden="true"><svg viewBox="0 0 24 24" focusable="false"><path d="M12 1.8c.9 0 1.6.7 1.6 1.6v5.7l6.3 4.1v2.2l-6.3-2v4.7l2.1 1.5v1.6L12 20l-3.7 1.2v-1.6l2.1-1.5v-4.7l-6.3 2v-2.2l6.3-4.1V3.4c0-.9.7-1.6 1.6-1.6Z"/></svg></span>
    <span>{label}</span>
  </span>;
}
