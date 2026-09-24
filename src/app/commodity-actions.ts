"use server";
import { revalidatePath } from "next/cache";
import { commodityServices } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { CommodityConflict, CommodityDenied, CommodityInvalid, type CommoditySnapshot } from "@/domain/commodity-codes";
export async function saveCommodityCodes(iata: string, revision: string, rows: unknown): Promise<{ ok: true; snapshot: CommoditySnapshot } | { ok: false; error: string }> {
  try {
    const snapshot = await (await commodityServices()).save(iata, revision, rows);
    revalidatePath(`/carrier/${encodeURIComponent(iata)}`);
    return { ok: true, snapshot };
  } catch (error) {
    return { ok: false, error: error instanceof CommodityInvalid ? error.message : error instanceof CommodityDenied ? "You no longer have permission to change commodity codes." : error instanceof CommodityConflict ? "The saved codes have changed. Copy your changes and reload before editing again." : error instanceof AuthenticationRequired ? "Your session has ended. Please sign in again." : "Unable to save commodity codes. Your entries are still here; please try again." };
  }
}
