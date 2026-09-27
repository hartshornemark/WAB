import assert from "node:assert/strict";
import test from "node:test";
import {dashboardSummaryStatus} from "../src/domain/dashboard-summary";

test("dashboard summary is configured when every assessed page is complete",()=>{
  assert.equal(dashboardSummaryStatus({C1:"configured","C5.2":"auto",G1:"not_required"}),"configured");
});

test("dashboard summary is partial when some assessed pages are complete",()=>{
  assert.equal(dashboardSummaryStatus({C1:"configured",C2:"incomplete"}),"partial");
  assert.equal(dashboardSummaryStatus({C1:"partial",C2:"incomplete"}),"partial");
});

test("dashboard summary is incomplete when no assessed page is complete",()=>{
  assert.equal(dashboardSummaryStatus({C1:"incomplete",G1:"not_required"}),"incomplete");
});
