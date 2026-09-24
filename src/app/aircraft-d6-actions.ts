"use server";

import { revalidatePath } from "next/cache";
import { aircraftD6Services } from "@/composition/services";
import {
  AircraftD6Conflict,
  AircraftD6Denied,
  AircraftD6Invalid,
  type D6Section,
} from "@/domain/aircraft-d6";

const failure = (error: unknown) => ({
  ok: false as const,
  error: error instanceof AircraftD6Invalid
    ? error.message
    : error instanceof AircraftD6Conflict
      ? "D6 data changed. Reload before saving."
      : error instanceof AircraftD6Denied
        ? "You do not have permission to edit D6."
        : "Unable to save D6.",
});

export async function saveAircraftD6(
  iata: string,
  typeCode: string,
  subtype: string,
  revision: string,
  section: D6Section,
  applicable: boolean,
  values: unknown,
) {
  try {
    const snapshot = await (await aircraftD6Services()).save(
      iata, typeCode, subtype, revision, section, applicable, values,
    );
    revalidatePath(`/carrier/${iata}/aircraft/${typeCode}/${subtype}/d6`);
    return { ok: true as const, snapshot };
  } catch (error) {
    return failure(error);
  }
}

export async function setAircraftD6Applicability(
  iata: string,
  typeCode: string,
  subtype: string,
  revision: string,
  section: D6Section,
  applicable: boolean,
) {
  try {
    const snapshot = await (await aircraftD6Services()).setApplicable(
      iata, typeCode, subtype, revision, section, applicable,
    );
    revalidatePath(`/carrier/${iata}/aircraft/${typeCode}/${subtype}/d6`);
    return { ok: true as const, snapshot };
  } catch (error) {
    return failure(error);
  }
}
