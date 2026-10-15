import assert from "node:assert/strict";
import test from "node:test";
import { workstreamNavigation } from "../src/domain/workstream-navigation";

test("the work selection page does not link back to itself", () => {
  assert.equal(workstreamNavigation("/work"), null);
});

test("Carrier Home does not link back to itself", () => {
  assert.deepEqual(workstreamNavigation("/carrier/AB/dashboard"), {
    workOptions: "/work",
    carrierHome: null,
    aircraftDashboard: null,
  });
});

test("work-stream pages return to work options without diverting through Carrier Home", () => {
  for (const pathname of [
    "/carrier/AB/flight-schedules",
    "/carrier/AB/load-control",
    "/carrier/AB/load-control/flight-id",
    "/carrier/AB/load-control-timeline",
  ]) {
    assert.deepEqual(workstreamNavigation(pathname), {
      workOptions: "/work",
      carrierHome: null,
      aircraftDashboard: null,
    });
  }
});

test("AHM pages retain contextual dashboards as well as work options", () => {
  const aircraftSelection = workstreamNavigation("/carrier/AB/aircraft");
  const aircraftPage = workstreamNavigation("/carrier/AB/aircraft/738/800/d4");
  assert.ok(aircraftSelection);
  assert.ok(aircraftPage);
  assert.equal(aircraftSelection.carrierHome, "/carrier/AB/dashboard");
  assert.equal(
    aircraftPage.aircraftDashboard,
    "/carrier/AB/aircraft/738/800/dashboard",
  );
});
