import assert from "node:assert/strict";
import test from "node:test";
import {
  combineDashboardWork,
  dashboardProgressFromStatuses,
  dashboardWorkForStatus,
  dashboardWorkPercent,
  weightedDashboardWork,
} from "../src/domain/dashboard-progress";

test("configured, partial and incomplete sections earn weighted progress", () => {
  assert.deepEqual(dashboardWorkForStatus("configured", 4), { earned: 4, possible: 4 });
  assert.deepEqual(dashboardWorkForStatus("partial", 4), { earned: 2, possible: 4 });
  assert.deepEqual(dashboardWorkForStatus("incomplete", 4), { earned: 0, possible: 4 });
});

test("inactive and generated sections do not inflate configuration effort", () => {
  assert.deepEqual(dashboardWorkForStatus("not_required", 5), { earned: 0, possible: 0 });
  assert.deepEqual(dashboardWorkForStatus("auto", 5), { earned: 0, possible: 0 });
});

test("weighted sections combine into a meaningful page percentage", () => {
  const work = weightedDashboardWork([
    { status: "configured", weight: 4 },
    { status: "partial", weight: 5 },
    { status: "skipped", weight: 5 },
    { status: "configured", weight: 1 },
  ]);
  assert.deepEqual(work, { earned: 7.5, possible: 10 });
  assert.equal(dashboardWorkPercent(work), 75);
});

test("page progress uses the first-pass effort catalogue", () => {
  const progress = dashboardProgressFromStatuses({ C4: "configured", C8: "partial", "C5.2": "auto" });
  assert.deepEqual(progress.C4, { earned: 2, possible: 2 });
  assert.deepEqual(progress.C8, { earned: 7.5, possible: 15 });
  assert.deepEqual(progress["C5.2"], { earned: 0, possible: 0 });
  assert.deepEqual(combineDashboardWork(Object.values(progress)), { earned: 9.5, possible: 17 });
});
