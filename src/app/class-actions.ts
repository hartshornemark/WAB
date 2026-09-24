"use server";
import { revalidatePath } from "next/cache";
import { classServices } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { ClassConflict, ClassDenied, ClassInvalid, type ClassSnapshot } from "@/domain/class-codes";
export async function saveClassCodes(iata: string, revision: string, rows: unknown): Promise<{ ok: true; snapshot: ClassSnapshot } | { ok: false; error: string }> {
  try {
    const snapshot = await (await classServices()).save(iata, revision, rows);
    revalidatePath(`/carrier/${encodeURIComponent(iata)}`);
    return { ok: true, snapshot };
  } catch (error) {
    return { ok: false, error: error instanceof ClassInvalid ? error.message : error instanceof ClassDenied ? "You no longer have permission to change class codes." : error instanceof ClassConflict ? "The saved codes have changed. Copy your changes and reload before editing again." : error instanceof AuthenticationRequired ? "Your session has ended. Please sign in again." : "Unable to save class codes. Your entries are still here; please try again." };
  }
}
