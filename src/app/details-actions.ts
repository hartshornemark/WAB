"use server";
import { revalidatePath } from "next/cache";
import { detailsServices } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { DetailsConflict, DetailsDenied, DetailsInvalid, type DetailsSaveSection, type DetailValues, type DetailsSnapshot } from "@/domain/carrier-details";
export type SaveDetailsResult = { ok: true; snapshot: DetailsSnapshot } | { ok: false; error: string; fields?: Partial<Record<keyof DetailValues, string>> };
export async function saveDetails(iata: string, revision: string, values: DetailValues, section: DetailsSaveSection = "all"): Promise<SaveDetailsResult> {
  try {
    const snapshot = await (await detailsServices()).save(iata, revision, values, section);
    revalidatePath(`/carrier/${encodeURIComponent(iata)}`);
    return { ok: true, snapshot };
  } catch (error) {
    if (error instanceof DetailsInvalid) return { ok: false, error: error.message, fields: error.fields };
    return { ok: false, error: error instanceof AuthenticationRequired ? "Your session has ended. Please sign in again." : error instanceof DetailsDenied ? "You no longer have permission to edit these details." : error instanceof DetailsConflict ? "Someone changed these details while you were editing. Copy any changes you wish to keep, then reload the page." : "Unable to save the details. Your entries are still here; please try again." };
  }
}
