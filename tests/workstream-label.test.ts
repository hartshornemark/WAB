import assert from "node:assert/strict";
import test from "node:test";
import { workstreamLabel } from "../src/domain/workstream";

test("labels each primary work stream", () => {
  assert.equal(workstreamLabel("/work"), "OPERATIONS WORKSPACE");
  assert.equal(workstreamLabel("/admin/airports"), "AIRPORT CONFIGURATION");
  assert.equal(workstreamLabel("/carrier/AB/flight-schedules"), "SCHEDULE CREATION / AMENDMENT");
  assert.equal(workstreamLabel("/carrier/AB/load-control"), "LOAD CONTROL");
  assert.equal(workstreamLabel("/carrier/AB/load-control-timeline"), "LOAD CONTROL");
  assert.equal(workstreamLabel("/carrier/AB/aircraft"), "AHM560 / 565 DATABASE");
});

test("labels carrier selection from the selected work stream", () => {
  assert.equal(workstreamLabel("/carriers", "schedules"), "SCHEDULE CREATION / AMENDMENT");
  assert.equal(workstreamLabel("/carriers", "load-control"), "LOAD CONTROL");
  assert.equal(workstreamLabel("/carriers", "ahm"), "AHM560 / 565 DATABASE");
});
