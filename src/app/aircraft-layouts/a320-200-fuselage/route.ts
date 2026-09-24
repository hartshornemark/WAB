import { readFile } from "node:fs/promises";
import { join } from "node:path";

export async function GET() {
  const svg = await readFile(
    join(process.cwd(), "src", "assets", "aircraft-layouts", "a320-200-fuselage.svg"),
  );

  return new Response(svg, {
    headers: {
      "Cache-Control": "public, max-age=86400, immutable",
      "Content-Type": "image/svg+xml; charset=utf-8",
    },
  });
}
