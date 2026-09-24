"use server";
import { revalidatePath } from "next/cache";
import { crewServices } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { CrewConflict, CrewDenied, CrewInvalid, type CrewSnapshot } from "@/domain/crew-weights";
export async function saveCrewWeights(iata: string, revision: string, values: unknown): Promise<{ ok: true; snapshot: CrewSnapshot } | { ok: false; error: string }> {
  try {
    const snapshot = await (await crewServices()).save(iata, revision, values);
    revalidatePath(`/carrier/${encodeURIComponent(iata)}/crew-weights`);
    return { ok: true, snapshot };
  } catch (error) {
    return { ok: false, error: error instanceof CrewInvalid ? error.message : error instanceof CrewDenied ? "You no longer have permission to edit these weights." : error instanceof CrewConflict ? "The weights or carrier weight unit changed while you were editing. Copy your changes, then reload the page." : error instanceof AuthenticationRequired ? "Your session has ended. Please sign in again." : "Unable to save crew weights. Your entries are still here; please try again." };
  }
}
