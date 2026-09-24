import "server-only";
import sharp from "sharp";
import type { LogoImageProcessor } from "@/ports/carrier-logo-repository";
import { LogoInputError } from "@/domain/models";
export const logoImageProcessor: LogoImageProcessor = {
  async normalise(bytes) {
    try {
      const image = sharp(bytes, { limitInputPixels: 16000000, animated: false, failOn: "warning" });
      const metadata = await image.metadata();
      if (!["png", "jpeg", "webp"].includes(metadata.format ?? "") || (metadata.pages ?? 1) > 1) throw new Error("Unsupported image");
      return await image.rotate().resize({ width: 1024, height: 1024, fit: "inside", withoutEnlargement: true }).png().toBuffer();
    } catch { throw new LogoInputError("This image could not be read. Use a still PNG, JPEG or WebP image up to 16 megapixels."); }
  },
};
