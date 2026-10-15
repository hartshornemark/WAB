export type LoadControlWorkloadFlight = {
  carrierIata: string;
  carrierName: string;
  serviceDate: string;
  departureLocal: string;
  airlineDesignator: string;
  flightNumber: string;
  operationalSuffix: string;
};

export function sortLoadControlWorkload<T extends LoadControlWorkloadFlight>(flights: T[]) {
  return [...flights].sort((left, right) =>
    left.departureLocal.localeCompare(right.departureLocal) ||
    left.airlineDesignator.localeCompare(right.airlineDesignator) ||
    left.flightNumber.localeCompare(right.flightNumber) ||
    left.operationalSuffix.localeCompare(right.operationalSuffix),
  );
}
