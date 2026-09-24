"use server";
import { revalidatePath } from "next/cache";
import { logoServices } from "@/composition/services";
import { LogoInputError, LogoAccessDenied, AuthenticationRequired } from "@/domain/models";
import { MAX_LOGO_BYTES } from "@/application/carrier-logos";
export type LogoFormState = { error: string; message: string };
export async function changeLogo(iata: string, _state: LogoFormState, form: FormData): Promise<LogoFormState> {
  try {
    const service = await logoServices();
    let result;
    if (form.get("operation") === "remove") {
      result = await service.remove(iata);
    } else {
      const file = form.get("logo");
      if (!(file instanceof File) || !file.size || file.size > MAX_LOGO_BYTES) throw new LogoInputError("Choose an image up to 2 MB.");
      result = await service.upload(iata, new Uint8Array(await file.arrayBuffer()), file.type);
    }
    revalidatePath("/carriers");
    revalidatePath(`/carrier/${encodeURIComponent(iata)}`);
    return { error: "", message: result.cleanupPending ? "Logo updated. The previous file could not be deleted; administrator cleanup is needed." : form.get("operation") === "remove" ? "Logo removed." : "Logo saved." };
  } catch (error) {
    return { error: error instanceof LogoInputError ? error.message : error instanceof AuthenticationRequired ? "Your session has ended. Please sign in again." : error instanceof LogoAccessDenied ? "You do not have permission to change this carrier’s logo." : "Unable to update the logo. Refresh the page and try again.", message: "" };
  }
}
