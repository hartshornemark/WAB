from pathlib import Path
p=Path('.')
files={
'src/domain/carrier-details.ts':'''export const contactFields = [
  { key: "address1", label: "Address line 1", required: true, max: 64 },
  { key: "address2", label: "Address line 2", max: 64 },
  { key: "address3", label: "Address line 3", max: 64 },
  { key: "city", label: "City", required: true, max: 64 },
  { key: "state", label: "State or province", max: 64 },
  { key: "country", label: "Country", required: true, max: 64 },
  { key: "telephone", label: "Telephone", max: 64 },
  { key: "email", label: "Email", max: 64 },
  { key: "teletype", label: "Teletype address", max: 7 },
] as const;
export type ContactKey = typeof contactFields[number]["key"];
export type DetailValues = Record<ContactKey | "weightUnit" | "volumeUnit" | "weightMethod", string>;
export const emptyDetails: DetailValues = { address1: "", address2: "", address3: "", city: "", state: "", country: "", telephone: "", email: "", teletype: "", weightUnit: "", volumeUnit: "", weightMethod: "" };
export interface DetailsSnapshot { canView: boolean; canEdit: boolean; exists: boolean; revision: string; values: DetailValues }
export class DetailsDenied extends Error {}
export class DetailsConflict extends Error {}
export class DetailsInvalid extends Error {
  constructor(public fields: Partial<Record<keyof DetailValues, string>>) { super("Please check the highlighted fields."); }
}
export function validateDetails(input: DetailValues): DetailValues {
  const values = { ...emptyDetails };
  const errors: Partial<Record<keyof DetailValues, string>> = {};
  for (const key of Object.keys(values) as (keyof DetailValues)[]) {
    values[key] = typeof input?.[key] === "string" ? input[key].trim() : "";
  }
  for (const field of contactFields) {
    const value = values[field.key];
    if ("required" in field && !value) errors[field.key] = `${field.label} is required.`;
    else if (value.length > field.max) errors[field.key] = `Use no more than ${field.max} characters.`;
    else if (/[\\x00-\\x1f\\x7f]/.test(value)) errors[field.key] = "Enter a single line of text.";
  }
  if (values.email && !/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(values.email)) errors.email = "Enter a valid email address.";
  if (values.teletype && values.teletype.length !== 7) errors.teletype = "Enter exactly 7 characters.";
  if (!["KG", "LB"].includes(values.weightUnit)) errors.weightUnit = "Choose a weight unit.";
  if (!["m3", "ft3"].includes(values.volumeUnit)) errors.volumeUnit = "Choose a volume unit.";
  if (!["BASIC", "DRY_OPERATING"].includes(values.weightMethod)) errors.weightMethod = "Choose a weight method.";
  if (Object.keys(errors).length) throw new DetailsInvalid(errors);
  return values;
}
''',
'src/ports/carrier-details-repository.ts':'''import type { DetailValues, DetailsSnapshot } from "@/domain/carrier-details";
export interface CarrierDetailsRepository {
  get(iata: string): Promise<DetailsSnapshot>;
  save(iata: string, revision: string, values: DetailValues): Promise<DetailsSnapshot>;
}
''',
'src/application/carrier-details.ts':'''import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { DetailsDenied, validateDetails, type DetailValues } from "@/domain/carrier-details";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { CarrierDetailsRepository } from "@/ports/carrier-details-repository";
export function createCarrierDetails(auth: AuthService, carriers: CarrierRepository, details: CarrierDetailsRepository) {
  async function requireCarrier(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!iata || iata.length > 32 || !await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  return {
    async get(iata: string) { await requireCarrier(iata); return details.get(iata); },
    async save(iata: string, revision: string, input: DetailValues) {
      await requireCarrier(iata);
      if (!(await details.get(iata)).canEdit) throw new DetailsDenied();
      return details.save(iata, revision, validateDetails(input));
    },
  };
}
''',
'src/infrastructure/supabase/details-adapter.ts':'''import "server-only";
import { DataUnavailable } from "@/domain/models";
import { DetailsConflict, DetailsDenied, emptyDetails, type DetailsSnapshot } from "@/domain/carrier-details";
import type { CarrierDetailsRepository } from "@/ports/carrier-details-repository";
import type { RequestClient } from "./server";
function snapshot(data: unknown): DetailsSnapshot {
  if (!data || typeof data !== "object") throw new DataUnavailable();
  const row = data as DetailsSnapshot;
  if (typeof row.canView !== "boolean" || typeof row.canEdit !== "boolean" || typeof row.exists !== "boolean" || typeof row.revision !== "string" || !row.values) throw new DataUnavailable();
  const values = { ...emptyDetails };
  for (const key of Object.keys(values) as (keyof typeof values)[]) {
    if (typeof row.values[key] !== "string") throw new DataUnavailable();
    values[key] = row.values[key];
  }
  return { canView: row.canView, canEdit: row.canEdit, exists: row.exists, revision: row.revision, values };
}
export function createDetailsAdapter(client: RequestClient): CarrierDetailsRepository {
  const api = () => client.schema("Basic_Carrier_Record");
  return {
    async get(iata) {
      const { data, error } = await api().rpc("get_carrier_details", { p_iata: iata });
      if (error) throw new DataUnavailable("Unable to load carrier details.");
      return snapshot(data);
    },
    async save(iata, revision, values) {
      const { data, error } = await api().rpc("save_carrier_details", { p_iata: iata, p_revision: revision, p_values: values });
      if (error?.code === "42501") throw new DetailsDenied();
      if (error?.code === "40001") throw new DetailsConflict();
      if (error) throw new DataUnavailable("Unable to save carrier details.");
      return snapshot(data);
    },
  };
}
''',
'src/app/details-actions.ts':'''"use server";
import { revalidatePath } from "next/cache";
import { detailsServices } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { DetailsConflict, DetailsDenied, DetailsInvalid, type DetailValues, type DetailsSnapshot } from "@/domain/carrier-details";
export type SaveDetailsResult = { ok: true; snapshot: DetailsSnapshot } | { ok: false; error: string; fields?: Partial<Record<keyof DetailValues, string>> };
export async function saveDetails(iata: string, revision: string, values: DetailValues): Promise<SaveDetailsResult> {
  try {
    const snapshot = await (await detailsServices()).save(iata, revision, values);
    revalidatePath(`/carrier/${encodeURIComponent(iata)}`);
    return { ok: true, snapshot };
  } catch (error) {
    if (error instanceof DetailsInvalid) return { ok: false, error: error.message, fields: error.fields };
    return { ok: false, error: error instanceof AuthenticationRequired ? "Your session has ended. Please sign in again." : error instanceof DetailsDenied ? "You no longer have permission to edit these details." : error instanceof DetailsConflict ? "Someone changed these details while you were editing. Copy any changes you wish to keep, then reload the page." : "Unable to save the details. Your entries are still here; please try again." };
  }
}
''',
'src/components/carrier-details.tsx':'''"use client";
import { useState, useTransition } from "react";
import { saveDetails } from "@/app/details-actions";
import { contactFields, type DetailValues, type DetailsSnapshot } from "@/domain/carrier-details";
const choices = [
  { key: "weightUnit", label: "Weight unit", options: [["KG", "Kilograms (KG)"], ["LB", "Pounds (LB)"]] },
  { key: "volumeUnit", label: "Volume unit", options: [["m3", "Cubic metres (m³)"], ["ft3", "Cubic feet (ft³)"]] },
  { key: "weightMethod", label: "Weight method", options: [["BASIC", "Basic Weight"], ["DRY_OPERATING", "Dry Operating Weight"]] },
] as const;
export function CarrierDetails({ iata, initial }: { iata: string; initial: DetailsSnapshot }) {
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState(initial.values);
  const [editing, setEditing] = useState(false);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [fields, setFields] = useState<Partial<Record<keyof DetailValues, string>>>({});
  function edit() { setDraft({ ...saved.values }); setFields({}); setError(""); setMessage(""); setEditing(true); }
  if (!saved.canView) return <section className="overview"><h2>Carrier details</h2><p>You do not have access to this carrier’s contact details or operating preferences.</p></section>;
  return <section className="overview carrier-details" aria-labelledby="details-title">
    <div className="details-heading"><h2 id="details-title">Carrier details</h2>{!editing && saved.canEdit && <button className="secondary" onClick={edit}>{saved.exists ? "Edit details" : "Complete carrier details"}</button>}</div>
    {!saved.exists && <p>Contact details and operating preferences still need to be completed by an authorised administrator.</p>}
    {editing ? <form noValidate onSubmit={event => {
      event.preventDefault(); setError(""); setFields({});
      startTransition(async () => {
        try {
          const result = await saveDetails(iata, saved.revision, draft);
          if (result.ok) { setSaved(result.snapshot); setEditing(false); setMessage("Carrier details saved."); }
          else { setError(result.error); setFields(result.fields ?? {}); }
        } catch { setError("Unable to save. Your entries are still here; please try again."); }
      });
    }}>
      <fieldset disabled={pending}><legend>Contact details</legend><p className="muted">Fields marked * are required.</p><div className="details-grid">
      {contactFields.map(field => <div className="details-field" key={field.key}><label htmlFor={`detail-${field.key}`}>{field.label}{"required" in field ? " *" : ""}</label><input id={`detail-${field.key}`} name={field.key} type={field.key === "email" ? "email" : field.key === "telephone" ? "tel" : "text"} value={draft[field.key]} maxLength={field.max} required={"required" in field} aria-invalid={!!fields[field.key]} aria-describedby={fields[field.key] ? `error-${field.key}` : undefined} onChange={event => setDraft({ ...draft, [field.key]: event.target.value })} />{fields[field.key] && <span className="field-error" id={`error-${field.key}`}>{fields[field.key]}</span>}</div>)}
      </div></fieldset>
      <fieldset disabled={pending}><legend>Operating preferences</legend><div className="details-grid">{choices.map(field => <div className="details-field" key={field.key}><label htmlFor={`detail-${field.key}`}>{field.label} *</label><select id={`detail-${field.key}`} value={draft[field.key]} required aria-invalid={!!fields[field.key]} aria-describedby={fields[field.key] ? `error-${field.key}` : undefined} onChange={event => setDraft({ ...draft, [field.key]: event.target.value })}><option value="">Choose…</option>{field.options.map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select>{fields[field.key] && <span className="field-error" id={`error-${field.key}`}>{fields[field.key]}</span>}</div>)}</div></fieldset>
      {error && <p role="alert" className="field-error">{error}</p>}
      <div className="logo-actions"><button disabled={pending} type="submit">{pending ? "Saving…" : "Save changes"}</button><button disabled={pending} type="button" className="secondary" onClick={() => { setEditing(false); setError(""); setFields({}); }}>Cancel</button></div>
    </form> : <><h3>Contact details</h3><dl className="details-grid">{contactFields.map(field => <div key={field.key}><dt>{field.label}</dt><dd>{saved.values[field.key] || "Not provided"}</dd></div>)}</dl><h3>Operating preferences</h3><dl className="details-grid">{choices.map(field => <div key={field.key}><dt>{field.label}</dt><dd>{field.options.find(([value]) => value === saved.values[field.key])?.[1] ?? "Not provided"}</dd></div>)}</dl></>}
    {!editing && !saved.canEdit && <p className="muted">These details are read-only for your account.</p>}
    <p role="status" aria-live="polite">{message}</p>
  </section>;
}
'''
}
for name,s in files.items(): (p/name).write_text(s)
f=p/'src/composition/services.ts';f.write_text(f.read_text()+'''\nimport { createCarrierDetails } from "@/application/carrier-details";
import { createDetailsAdapter } from "@/infrastructure/supabase/details-adapter";
export async function detailsServices() {
  const client = await createRequestClient();
  return createCarrierDetails(createAuthAdapter(client), createCarrierAdapter(client), createDetailsAdapter(client));
}
''')
f=p/'src/infrastructure/supabase/database.types.ts';s=f.read_text();s='export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];\n'+s;s=s.replace('Functions: {','Functions: {\n      get_carrier_details: { Args: { p_iata: string }; Returns: Json };\n      save_carrier_details: { Args: { p_iata: string; p_revision: string; p_values: Json }; Returns: Json };');f.write_text(s)
f=p/'src/app/carrier/[iata]/page.tsx';s=f.read_text().replace('services, logoServices','services, logoServices, detailsServices');s='import { CarrierDetails } from "@/components/carrier-details";\n'+s;s=s.replace('  return <WorkspaceShell','  const details = await (await detailsServices()).get(iata);\n  return <WorkspaceShell');s=s.replace('<LogoManager','<CarrierDetails iata={iata} initial={details} /><LogoManager');f.write_text(s)
f=p/'src/app/globals.css';f.write_text(f.read_text()+'''\n.details-heading { display:flex; gap:20px; align-items:center; justify-content:space-between; margin-bottom:24px; }
.details-heading h2 { margin:0; }
.carrier-details .details-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:20px 32px; margin:18px 0 32px; }
.carrier-details dd { overflow-wrap:anywhere; }
.carrier-details fieldset { border:0; margin:0; padding:0; min-width:0; }
.carrier-details legend { font-size:19px; font-weight:700; margin-bottom:12px; }
.details-field { display:flex; flex-direction:column; gap:6px; }
.details-field label { font-size:13px; font-weight:600; }
.details-field input,.details-field select { font:inherit; color:var(--ink); background:white; border:1px solid #b8c8e2; border-radius:6px; padding:12px; width:100%; }
.details-field :is(input,select):focus-visible { outline:3px solid var(--accent); outline-offset:3px; }
.details-field [aria-invalid=true] { border-color:#a12c2c; }
.field-error { color:#a12c2c; font-size:14px; }
@media(max-width:760px) { .carrier-details .details-grid { grid-template-columns:1fr; } .details-heading { align-items:flex-start; flex-direction:column; } }
''')
