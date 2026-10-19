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

test("AHM sheets return to the dashboard matching their configuration scope", () => {
  const aircraftSelection = workstreamNavigation("/carrier/AB/aircraft");
  const aircraftPage = workstreamNavigation("/carrier/AB/aircraft/738/800/d4");
  assert.ok(aircraftSelection);
  assert.ok(aircraftPage);
  assert.equal(aircraftSelection.carrierHome, "/carrier/AB/dashboard");
  assert.equal(aircraftPage.carrierHome, "/carrier/AB/dashboard");
  assert.equal(aircraftPage.aircraftDashboard, "/carrier/AB/aircraft/738/800/dashboard");
});

test("carrier-level A2 and B1 to B4 sheets return to the carrier dashboard", () => {
  for (const pathname of [
    "/carrier/AB",
    "/carrier/AB/crew-weights",
    "/carrier/AB/passenger-weights",
    "/carrier/AB/baggage-weights",
  ]) {
    const navigation = workstreamNavigation(pathname);
    assert.ok(navigation);
    assert.equal(navigation.carrierHome, "/carrier/AB/dashboard");
    assert.equal(navigation.aircraftDashboard, null);
  }
});
