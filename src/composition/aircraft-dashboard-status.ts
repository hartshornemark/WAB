import type { dashboardStatusServices } from "@/composition/services";
import { a2CarrierContactsStatus } from "@/domain/carrier-details";
import { a5AutomaticDocumentsStatus } from "@/domain/a5-status";
import { b1Statuses } from "@/domain/b1-status";
import { b2Statuses } from "@/domain/b2-status";
import { b3Statuses } from "@/domain/b3-status";
import { b4Statuses } from "@/domain/b4-status";
import { b5Completion } from "@/domain/b5-status";
import { aircraftC1Statuses } from "@/domain/aircraft-c1-status";
import { aircraftC2Statuses, aircraftC5ApplicabilityFromC2 } from "@/domain/aircraft-c2-status";
import { aircraftC4Status } from "@/domain/aircraft-c4-status";
import { aircraftC5Statuses } from "@/domain/aircraft-c5-status";
import { aircraftC7Statuses } from "@/domain/aircraft-c7-status";
import { aircraftC8Statuses } from "@/domain/aircraft-c8-status";
import { aircraftC11Status, aircraftC11Required } from "@/domain/aircraft-c11-status";
import { aircraftD2Status } from "@/domain/aircraft-d2-status";
import { aircraftD3Status } from "@/domain/aircraft-d3-status";
import { aircraftD4Status } from "@/domain/aircraft-d4-status";
import { aircraftD5Status } from "@/domain/aircraft-d5-status";
import { aircraftD6Status } from "@/domain/aircraft-d6-status";
import { aircraftD8Status } from "@/domain/aircraft-d8-status";
import { aircraftD9Status } from "@/domain/aircraft-d9-status";
import { aircraftD11Status } from "@/domain/aircraft-d11-status";
import { aircraftE11Status } from "@/domain/aircraft-e11-status";
import { aircraftE12Status } from "@/domain/aircraft-e12-status";
import { aircraftE2Status } from "@/domain/aircraft-e2-status";
import { aircraftE3Status } from "@/domain/aircraft-e3-status";
import { aircraftE4Status } from "@/domain/aircraft-e4-status";
import { aircraftE5Status } from "@/domain/aircraft-e5-status";
import { aircraftF1Status } from "@/domain/aircraft-f1-status";
import { aircraftG1DashboardStatus } from "@/domain/aircraft-g1-status";
import { aircraftH1Status } from "@/domain/aircraft-h1-status";
import { aircraftD2SectionStatus } from "@/domain/aircraft-d2-status";
import { aircraftD5Statuses } from "@/domain/aircraft-d5-status";
import { aircraftD6Statuses } from "@/domain/aircraft-d6-status";
import { d9ConfigurationStatuses } from "@/domain/aircraft-d9-status";
import { e2CrewStatus, e2PantryStatus } from "@/domain/aircraft-e2-status";
import { e3ServiceStatus, e3WaterStatus } from "@/domain/aircraft-e3-status";
import { e4AdditionalStatus, e4MainStatus } from "@/domain/aircraft-e4-status";
import { h1DgrStatus, h1IataStatus, h1SpecialLoadsStatus } from "@/domain/aircraft-h1-status";
import {
  dashboardProgressFromStatuses,
  weightedDashboardWork,
  type DashboardWork,
} from "@/domain/dashboard-progress";

export type AircraftDashboardRead=Awaited<ReturnType<Awaited<ReturnType<typeof dashboardStatusServices>>["get"]>>;

export function aircraftDashboardStatuses(read:AircraftDashboardRead){
  const [details,density,classes,commodities,crew,passengers,baggage,uld,c1,c2,c4,c5,c7,c8,c11,d2,d3,d4,d5,d6,d8,d9,d11,e11,e12,e2,e3,e4,e5,f1,g1,h1]=read;
  const incomplete="incomplete" as const;
  const operatingRole=c1?.operatingRole??"PASSENGER";
  const passengerOperations=operatingRole!=="FREIGHTER";
  const c2Page=c2?aircraftC2Statuses(c2,operatingRole).page:incomplete;
  const c4Page=c4?aircraftC4Status(c4):incomplete;
  const c5Page=c5&&c2&&c2Page==="configured"?aircraftC5Statuses(c5.values,aircraftC5ApplicabilityFromC2(c2)).page:incomplete;
  const c11Page=c2&&!aircraftC11Required(c2)?"not_required":c11?aircraftC11Status(c11):incomplete;
  const d9Formula=c4&&c4Page==="configured"?{referenceArm:c4.values.referenceArm,constantC:c4.values.constantC}:undefined;
  return{
    A2:details?a2CarrierContactsStatus(details):incomplete,A5:c2?a5AutomaticDocumentsStatus(c2):incomplete,
    B1:details&&density&&classes&&commodities?b1Statuses(details,density,classes,commodities,passengerOperations).page:incomplete,B2:crew?b2Statuses(crew).page:incomplete,B3:passengerOperations?(passengers?b3Statuses(passengers).page:incomplete):"not_required",B4:passengerOperations?(baggage?b4Statuses(baggage).page:incomplete):"not_required",B5:uld?b5Completion(uld).page:incomplete,
    C1:c1?aircraftC1Statuses(c1).page:incomplete,C2:c2Page,C3:c2Page,C4:c4Page,"C5.1":c5Page,"C5.2":c5Page==="configured"?"auto":incomplete,C7:c7?aircraftC7Statuses(c7.values,c5?.values.maximumWeights.mrw||null).page:incomplete,C8:c8?aircraftC8Statuses(c8.values).page:incomplete,"C11.1":c11Page,"C11.2":c11Page==="not_required"?"not_required":c11Page==="configured"?"auto":incomplete,
    D2:d2?aircraftD2Status(d2):incomplete,D3:d3?aircraftD3Status(d3):incomplete,D4:d4?aircraftD4Status(d4):incomplete,D5:d5?aircraftD5Status(d5,operatingRole):incomplete,D6:d6?aircraftD6Status(d6):incomplete,D8:d8?aircraftD8Status(d8,operatingRole):incomplete,D9:d9?aircraftD9Status(d9,d9Formula,operatingRole):incomplete,D11:d11?aircraftD11Status(d11):incomplete,
    "E1.1":e11?(aircraftE11Status(e11)==="configured"?"auto":aircraftE11Status(e11)):incomplete,"E1.2":e12?aircraftE12Status(e12):incomplete,E2:e2?aircraftE2Status(e2):incomplete,E3:e3?aircraftE3Status(e3):incomplete,E4:e4?aircraftE4Status(e4):incomplete,E5:e5?aircraftE5Status(e5):incomplete,
    F1:f1?aircraftF1Status(f1):incomplete,G1:aircraftG1DashboardStatus(g1,d2?.uldApplicable),H1:h1?aircraftH1Status(h1):incomplete,
  } as const;
}

export function aircraftDashboardReport(read:AircraftDashboardRead) {
  const statuses = aircraftDashboardStatuses(read);
  const progress: Record<string, DashboardWork> = dashboardProgressFromStatuses(statuses);
  const [, , , , , , , , c1, c2, c4, c5, c7, c8, , d2, , , d5, d6, , d9, , , , e2, e3, e4, , , , h1] = read;
  const operatingRole = c1?.operatingRole ?? "PASSENGER";

  if (c5 && c2 && aircraftC2Statuses(c2, operatingRole).page === "configured") {
    const parts = aircraftC5Statuses(c5.values, aircraftC5ApplicabilityFromC2(c2));
    progress["C5.1"] = weightedDashboardWork([
      { status: parts.status, weight: 1 },
      { status: parts.tow, weight: 4 },
      { status: parts.law, weight: 4 },
      { status: parts.zfw, weight: 4 },
    ]);
  }
  if (c7) {
    const parts = aircraftC7Statuses(c7.values, c5?.values.maximumWeights.mrw || null);
    progress.C7 = weightedDashboardWork([
      { status: parts.idealTrim, weight: 2 },
      { status: parts.tippingLimits, weight: 1 },
    ]);
  }
  if (c8) {
    const parts = aircraftC8Statuses(c8.values);
    progress.C8 = weightedDashboardWork([
      { status: parts.standard, weight: 4 },
      { status: parts.byTank, weight: 5 },
      { status: parts.bySchedule, weight: 5 },
      { status: parts.taxiFuel, weight: 1 },
    ]);
  }
  if (d2) {
    progress.D2 = weightedDashboardWork([
      { status: aircraftD2SectionStatus(d2.bulkApplicable, d2.bulkBalanceLimitsRequired, d2.rows.filter(row => row.holdType === "BLK")), weight: 4 },
      { status: aircraftD2SectionStatus(d2.uldApplicable, d2.uldBalanceLimitsRequired, d2.rows.filter(row => row.holdType === "ULD")), weight: 5 },
    ]);
  }
  if (d5) {
    const parts = aircraftD5Statuses(d5, operatingRole);
    progress.D5 = weightedDashboardWork([
      { status: parts.cabinAreas, weight: 4 },
      { status: parts.flightDeckLocations, weight: 2 },
      { status: parts.cabinCrewLocations, weight: 2 },
    ]);
  }
  if (d6) {
    const parts = aircraftD6Statuses(d6);
    progress.D6 = weightedDashboardWork([
      { status: parts.waterLocations, weight: 2 },
      { status: parts.galleyLocations, weight: 2 },
    ]);
  }
  if (d9 && operatingRole !== "FREIGHTER") {
    const formula = c4 && aircraftC4Status(c4) === "configured"
      ? { referenceArm: c4.values.referenceArm, constantC: c4.values.constantC }
      : undefined;
    progress.D9 = weightedDashboardWork(d9.configurations.flatMap(configuration => {
      const parts = d9ConfigurationStatuses(configuration, d9.cabinAreas, d9.classes, formula, d9.excludedRows);
      return [{ status: parts.cabin, weight: 4 }, { status: parts.classInfo, weight: 2 }];
    }));
  }
  if (e2) progress.E2 = weightedDashboardWork([
    { status: e2CrewStatus(e2), weight: 3 },
    { status: e2PantryStatus(e2), weight: 3 },
  ]);
  if (e3) progress.E3 = weightedDashboardWork([
    { status: e3.applicabilityReviewed ? "configured" : "incomplete", weight: 1 },
    { status: e3WaterStatus(e3), weight: 2 },
    { status: e3ServiceStatus(e3), weight: 2 },
  ]);
  if (e4) progress.E4 = weightedDashboardWork([
    { status: e4.applicabilityReviewed ? "configured" : "incomplete", weight: 1 },
    { status: e4MainStatus(e4), weight: 4 },
    { status: e4AdditionalStatus(e4), weight: 2 },
  ]);
  if (h1) progress.H1 = weightedDashboardWork([
    { status: h1.applicabilityReviewed ? "configured" : "incomplete", weight: 1 },
    { status: h1DgrStatus(h1), weight: 2 },
    { status: h1IataStatus(h1), weight: 2 },
    { status: h1SpecialLoadsStatus(h1), weight: 2 },
  ]);

  return { statuses, progress };
}
