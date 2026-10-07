import assert from "node:assert/strict";
import test from "node:test";
import {
  dashboardStatusCalculationVersion,
  dashboardStatusSnapshotKey,
  resolveDashboardStatusSnapshots,
  type DashboardStatusSnapshot,
} from "../src/domain/dashboard-status-snapshot";

const saved=(overrides:Partial<DashboardStatusSnapshot>={}):DashboardStatusSnapshot=>({
  carrierIata:"ZZ",
  typeCode:"321",
  subtype:"200",
  overallStatus:"configured",
  attention:[],
  statuses:{C1:"configured"},
  progress:{},
  calculationVersion:dashboardStatusCalculationVersion,
  updatedAt:"2026-10-01T00:00:00.000Z",
  ...overrides,
});

test("snapshot keys are case and whitespace independent",()=>{
  assert.equal(dashboardStatusSnapshotKey(" 321 "," p2f "),"321:P2F");
});

test("current snapshots provide stored dashboard status without recalculation",()=>{
  assert.deepEqual(resolveDashboardStatusSnapshots(
    [{typeCode:"321",subtype:"200"}],
    [saved({attention:["D2"]})],
  ),{
    statuses:{"321:200":{status:"configured",attention:["D2"]}},
    refreshing:[],
  });
});

test("missing and outdated snapshots are marked for background refresh",()=>{
  assert.deepEqual(resolveDashboardStatusSnapshots(
    [{typeCode:"321",subtype:"200"},{typeCode:"359",subtype:"900"}],
    [saved({calculationVersion:dashboardStatusCalculationVersion-1})],
  ),{
    statuses:{
      "321:200":{status:"unavailable",attention:[]},
      "359:900":{status:"unavailable",attention:[]},
    },
    refreshing:["321:200","359:900"],
  });
});
