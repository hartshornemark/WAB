import type { PassengerSnapshot, PassengerSection, PassengerValues, PassengerRow, FlightVariation } from "@/domain/passenger-weights";
export interface PassengerRepository {
  get(iata: string): Promise<PassengerSnapshot>;
  save(iata: string, revision: string, section: PassengerSection, values: PassengerValues | PassengerRow[] | FlightVariation[]): Promise<PassengerSnapshot>;
}
