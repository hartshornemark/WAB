"use server";
import { revalidatePath } from "next/cache";
import { passengerServices } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { PassengerInvalid, PassengerDenied, PassengerConflict, type PassengerSection, type PassengerSnapshot } from "@/domain/passenger-weights";
export async function savePassengerWeights(iata: string,revision: string,section: PassengerSection,values: unknown): Promise<{ok:true;snapshot:PassengerSnapshot}|{ok:false;error:string}> {
  try {
    const snapshot = await (await passengerServices()).save(iata,revision,section,values);
    revalidatePath(`/carrier/${encodeURIComponent(iata)}/passenger-weights`);
    return {ok:true,snapshot};
  } catch(error) {
    return {ok:false,error:error instanceof PassengerInvalid ? error.message : error instanceof PassengerDenied ? "You no longer have permission to edit these settings." : error instanceof PassengerConflict ? "The passenger settings, classes or weight unit changed. Copy your entries, then reload before saving." : error instanceof AuthenticationRequired ? "Your session has ended. Please sign in again." : "Unable to save. Your entries are still here; please try again."};
  }
}
