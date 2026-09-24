export type CarrierClass = { code: string; priority: number; description: string };
export type ClassSnapshot = { canView: boolean; canEdit: boolean; revision: string; rows: CarrierClass[]; defaults: CarrierClass[] };
export class ClassInvalid extends Error {}
export class ClassDenied extends Error {}
export class ClassConflict extends Error {}
export function validateClasses(input: unknown): CarrierClass[] {
  if (!Array.isArray(input) || input.length < 1 || input.length > 4) throw new ClassInvalid("Keep between one and four classes.");
  const codes = new Set<string>(), priorities = new Set<number>();
  return input.map((row, index) => {
    if (!row || typeof row.code !== "string" || typeof row.description !== "string") throw new ClassInvalid(`Check class ${index + 1}.`);
    const rawCode = row.code.trim(), description = row.description.trim();
    if (!/^[A-Za-z]$/.test(rawCode)) throw new ClassInvalid(`Class ${index + 1}: the code must be one letter (A–Z). Numbers and symbols are not allowed.`);
    const code = rawCode.toUpperCase();
    if (!Number.isInteger(row.priority) || row.priority < 1 || row.priority > 4) throw new ClassInvalid(`Class ${index + 1}: choose a priority from 1 to 4.`);
    if (!description || [...description].length > 64 || /[\u0000-\u001f\u007f]/.test(description)) throw new ClassInvalid(`Class ${index + 1}: provide a name or description of up to 64 characters without line breaks.`);
    if (codes.has(code)) throw new ClassInvalid(`Class code ${code} is duplicated. Each code must be unique.`);
    if (priorities.has(row.priority)) throw new ClassInvalid(`Priority ${row.priority} is duplicated. Each class must have a different priority.`);
    codes.add(code); priorities.add(row.priority);
    return { code, priority: row.priority, description };
  }).sort((a, b) => a.priority - b.priority);
}
