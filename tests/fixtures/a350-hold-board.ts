import snapshot from "./a350-hold-board.json";
import type { AircraftD2Snapshot } from "../../src/domain/aircraft-d2";
import type { AircraftD3Snapshot } from "../../src/domain/aircraft-d3";
import type { AircraftD4Snapshot } from "../../src/domain/aircraft-d4";
import { buildFreightAutoloadProblem } from "../../src/domain/freight-autoload";

// Read-only A350 configuration captured on 2026-10-22. No operational flight data.
export function a350HoldBoardFixture() {
  const source = structuredClone(snapshot);
  const d2 = source.d2 as unknown as AircraftD2Snapshot;
  const d3 = source.d3 as unknown as AircraftD3Snapshot;
  const d4 = source.d4 as unknown as AircraftD4Snapshot;
  const context = buildFreightAutoloadProblem({ d2, d3, d4,
    flight: { legSequence: 1, itinerary: { legs: [{ legSequence: 1, arrivalAirport: "BBB" }] },
      freightPlanning: { registration: null, planningAircraftWeight: 0 },
      freightAcceptance: { status: "RELEASED", uldLimits: [], items: [{ lineId: "sample", loadType: "ULD", uldId: "AKE0001ZZ", grossWeight: 900, unloadingStation: "BBB", specialHandlingCodes: [], includedLoads: [], dangerousGoods: false }] },
    } as never,
    c7: { values: { idealTrim: { enabled: false, points: [] } } } as never,
    e12: { registrations: [], standardFleetIndex: null } as never,
    e2: { crewRows: [], pantryRows: [] } as never,
    h1: { masterIncompatibilities: [], dgrActive: false, iataActive: false, specialLoadsActive: false, codeClasses: {} } as never,
  });
  return { d2, d3, d4, problem: context.problem };
}
