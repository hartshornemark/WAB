import type { Carrier } from "@/domain/models";
export interface CarrierRepository {
  listAuthorised(): Promise<Carrier[]>;
  findAuthorised(iata: string): Promise<Carrier | null>;
}
