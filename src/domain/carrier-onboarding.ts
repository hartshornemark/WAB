import type { Carrier } from "./models";

export type NewCarrierInput = Pick<Carrier, "iata" | "name" | "icao">;
export type CarrierIdentityField = "iata" | "name" | "icao";

export class CarrierCreationDenied extends Error {}
export class CarrierIdentityInvalid extends Error {
  constructor(public field: CarrierIdentityField, message: string) { super(message); }
}
export class CarrierIdentityExists extends Error {
  constructor(public field: CarrierIdentityField | "duplicate") { super("Carrier identity already exists."); }
}

export function validateNewCarrier(input: NewCarrierInput): NewCarrierInput {
  const iata=input.iata.trim().toUpperCase(),name=input.name.trim(),icao=input.icao.trim().toUpperCase();
  if(!/^[A-Z0-9]{2}$/.test(iata)) throw new CarrierIdentityInvalid("iata","Enter the two-character IATA code.");
  if(!name || name.length>64) throw new CarrierIdentityInvalid("name","Enter a carrier name of up to 64 characters.");
  if(!/^[A-Z]{3}$/.test(icao)) throw new CarrierIdentityInvalid("icao","Enter the three-letter ICAO code.");
  return {iata,name,icao};
}
