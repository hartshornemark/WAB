import type { DisplayConfigurationStatus } from "@/domain/configuration-status";

export type DashboardWork = { earned: number; possible: number };

const excluded = new Set<DisplayConfigurationStatus>([
  "unsupported",
  "out_of_scope",
  "skipped",
  "not_active",
  "not_required",
  "optional",
]);

// These are deliberately simple first-pass effort estimates. They describe the
// amount of configuration work, rather than the operational importance of a page.
export const dashboardPageEffort: Record<string, number> = {
  A2: 2, A5: 1,
  B1: 4, B2: 3, B3: 4, B4: 4, B5: 3,
  C1: 2, C2: 3, C3: 0, C4: 2, "C5.1": 13, "C5.2": 0, C7: 3, C8: 15,
  "C11.1": 3, "C11.2": 0,
  D2: 9, D3: 5, D4: 3, D5: 8, D6: 4, D8: 4, D9: 6, D11: 3,
  "E1.1": 0, "E1.2": 5, E2: 6, E3: 5, E4: 7, E5: 5,
  F1: 4, G1: 4, H1: 7,
};

export function dashboardWorkForStatus(status: string, possible: number): DashboardWork {
  if (possible <= 0 || excluded.has(status as DisplayConfigurationStatus) || status === "auto") {
    return { earned: 0, possible: 0 };
  }
  if (status === "configured") return { earned: possible, possible };
  if (status === "partial") return { earned: possible / 2, possible };
  return { earned: 0, possible };
}

export function combineDashboardWork(parts: DashboardWork[]): DashboardWork {
  return parts.reduce(
    (total, part) => ({ earned: total.earned + part.earned, possible: total.possible + part.possible }),
    { earned: 0, possible: 0 },
  );
}

export function weightedDashboardWork(
  parts: Array<{ status: string; weight: number }>,
): DashboardWork {
  return combineDashboardWork(parts.map(({ status, weight }) => dashboardWorkForStatus(status, weight)));
}

export function dashboardProgressFromStatuses(
  statuses: Record<string, string>,
): Record<string, DashboardWork> {
  return Object.fromEntries(Object.entries(statuses).map(([code, status]) => [
    code,
    dashboardWorkForStatus(status, dashboardPageEffort[code] ?? 1),
  ]));
}

export function dashboardWorkPercent(work: DashboardWork): number {
  return work.possible > 0 ? Math.round(work.earned / work.possible * 100) : 0;
}
