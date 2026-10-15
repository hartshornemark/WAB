import assert from "node:assert/strict";
import test from "node:test";
import { sortLoadControlWorkload } from "../src/domain/load-control-workload";

test("a mixed-carrier workload is ordered by published STD", () => {
  const common = {carrierName:"Carrier",serviceDate:"2026-10-15",operationalSuffix:""};
  const flights = sortLoadControlWorkload([
    {...common,carrierIata:"AB",airlineDesignator:"AB",flightNumber:"200",departureLocal:"2026-10-15T18:00:00"},
    {...common,carrierIata:"KA",airlineDesignator:"KA",flightNumber:"100",departureLocal:"2026-10-15T07:30:00"},
    {...common,carrierIata:"BC",airlineDesignator:"BC",flightNumber:"300",departureLocal:"2026-10-15T12:15:00"},
  ]);
  assert.deepEqual(flights.map(flight=>flight.flightNumber),["100","300","200"]);
});
