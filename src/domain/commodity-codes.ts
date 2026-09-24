export type CommodityCode = { code: string; description: string };
export type CommoditySnapshot = { canView: boolean; canEdit: boolean; revision: string; rows: CommodityCode[]; defaults: CommodityCode[] };
export class CommodityInvalid extends Error {}
export class CommodityDenied extends Error {}
export class CommodityConflict extends Error {}
export function validateCommodities(input: unknown): CommodityCode[] {
  if (!Array.isArray(input) || !input.length || input.length > 200) throw new CommodityInvalid("Provide between 1 and 200 commodity codes.");
  const seen = new Set<string>();
  return input.map((row, index) => {
    if (!row || typeof row.code !== "string" || typeof row.description !== "string") throw new CommodityInvalid(`Check row ${index + 1}.`);
    const code = row.code.trim().toUpperCase(), description = row.description.trim();
    if (!/^[A-Z0-9]{1,2}$/.test(code)) throw new CommodityInvalid(`Row ${index + 1}: use one or two letters or numbers for the code.`);
    if (!description || [...description].length > 64 || /[\u0000-\u001f\u007f]/.test(description)) throw new CommodityInvalid(`Row ${index + 1}: provide a description of up to 64 characters without line breaks.`);
    if (seen.has(code)) throw new CommodityInvalid(`Code ${code} is duplicated. Each code must be unique.`);
    seen.add(code); return { code, description };
  });
}
