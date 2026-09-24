import { AuthenticationRequired, CarrierUnavailable, LogoInputError, LogoAccessDenied } from "@/domain/models";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { CarrierLogoRepository, LogoImageProcessor } from "@/ports/carrier-logo-repository";
export const MAX_LOGO_BYTES = 2 * 1024 * 1024;
export function createCarrierLogos(auth: AuthService, carriers: CarrierRepository, logos: CarrierLogoRepository, images: LogoImageProcessor) {
  async function requireCarrier(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!iata || iata.length > 32 || !await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  async function requireEditor(iata: string) {
    await requireCarrier(iata);
    if (!await logos.canManage(iata)) throw new LogoAccessDenied();
  }
  async function replace(iata: string, path: string | null) {
    // An ambiguous failure may have committed: never delete the newly uploaded object.
    const previous = await logos.setReference(iata, path);
    if (previous && previous !== path) {
      try { await logos.deleteFile(previous); } catch { return { cleanupPending: true }; }
    }
    return { cleanupPending: false };
  }
  return {
    async canManage(iata: string) { await requireCarrier(iata); return logos.canManage(iata); },
    async upload(iata: string, bytes: Uint8Array, mime: string) {
      await requireEditor(iata);
      if (!bytes.length || bytes.length > MAX_LOGO_BYTES) throw new LogoInputError("Choose an image up to 2 MB.");
      if (!["image/png", "image/jpeg", "image/webp"].includes(mime)) throw new LogoInputError("Choose a PNG, JPEG or WebP image.");
      const image = await images.normalise(bytes);
      if (image.length > MAX_LOGO_BYTES) throw new LogoInputError("The processed image is too large. Please choose a smaller image.");
      return replace(iata, await logos.upload(iata, image));
    },
    async remove(iata: string) { await requireEditor(iata); return replace(iata, null); },
  };
}
