"use server";
import { aircraftD2Services, aircraftD3Services, aircraftD4Services } from "@/composition/services";
import { buildHoldLayout, holdLayoutUnavailable } from "@/domain/hold-layout";

export async function loadHoldLayout(iata: string, typeCode: string, subtype: string) {
  try {
    // These services authenticate the user and authorise carrier access on each
    // request. Read both snapshots afresh whenever either page opens the diagram.
    const [d2, d3, d4] = await Promise.all([
      aircraftD2Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftD3Services().then(service => service.get(iata, typeCode, subtype)),
      aircraftD4Services().then(service => service.get(iata, typeCode, subtype)),
    ]);
    const reason = holdLayoutUnavailable(d2);
    if (reason) return { ok: false as const, error: reason };
    try { return { ok: true as const, layout: buildHoldLayout(d2, d4, d3) }; }
    catch (error) { return { ok: false as const, error: error instanceof Error ? error.message : "Unable to draw this hold layout." }; }
  } catch {
    return { ok: false as const, error: "Unable to load the saved hold layout. Check your access and try again." };
  }
}
