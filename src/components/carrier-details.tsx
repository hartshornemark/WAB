"use client";
import {useSaveFeedback,SaveScope,SaveButton,SaveInput,SaveSelect,SaveSubmit,SaveCancel} from "@/components/save-feedback";
import { SectionHeader } from "@/components/section-header";
import Link from "next/link";
import {useRouter} from "next/navigation";
import { useState, type ReactNode } from "react";
import { saveDetails } from "@/app/details-actions";
import { a2CarrierContactsStatus, contactFields, type DetailValues, type DetailsSnapshot } from "@/domain/carrier-details";
import {ConfigurationStatusBadge} from "@/components/configuration-status-badge";
import {b1UnitsStatus} from "@/domain/b1-status";
import type {ConfigurationStatus} from "@/domain/configuration-status";
import {INDEX_DISPLAY_PREFERENCE_EVENT} from "@/components/index-display-preference";
const choices = [
  { key: "weightUnit", label: "Weight unit", options: [["KG", "Kilograms (KG)"], ["LB", "Pounds (LB)"]] },
  { key: "volumeUnit", label: "Volume unit", options: [["m3", "Cubic metres (m³)"], ["ft3", "Cubic feet (ft³)"]] },
  { key: "weightMethod", label: "Starting Weight Principle", options: [["BASIC", "Basic Weight"], ["DRY_OPERATING", "Dry Operating Weight"]] },
] as const;
export function CarrierDetails({ iata, initial, children, commodityEditor, initialStep = "contact",pageStatus="incomplete" }: { iata: string; initial: DetailsSnapshot; children?: ReactNode; commodityEditor?: ReactNode; initialStep?: "contact" | "general";pageStatus?:ConfigurationStatus }) {
  const router=useRouter();
  const [step, setStep] = useState<"contact" | "general">(initialStep);
  const title = step === "contact" ? "A2. CARRIERS’ CONTACTS" : "B1. UNITS & CODES";
  const reference = step === "contact" ? "(AHM565 Sheet A2)" : "(AHM565 Sheet B1)";
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState(initial.values);
  const [editing, setEditing] = useState(false);
  const [pending, startTransition,saveFeedback] = useSaveFeedback();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [fields, setFields] = useState<Partial<Record<keyof DetailValues, string>>>({});
  function edit() { setDraft({ ...saved.values }); setFields({}); setError(""); setMessage(""); setEditing(true); }
  if (!saved.canView) return <SaveScope feedback={saveFeedback}>{<><section className="overview"><h2>A2. CARRIERS’ CONTACTS</h2><p>You do not have access to this carrier’s contact details or carrier standard units and codes.</p></section>{children}</>}</SaveScope>;
  return <SaveScope feedback={saveFeedback}>{<><section className="overview carrier-details" aria-labelledby="details-title">
    <SectionHeader id="details-title" title={title} reference={reference}>{step==="general"?<ConfigurationStatusBadge status={pageStatus} variant="large"/>:<div className="c5-heading-actions">{!editing&&saved.canEdit&&<SaveButton className="secondary" onClick={edit}>EDIT</SaveButton>}<ConfigurationStatusBadge status={a2CarrierContactsStatus(saved)} variant="large"/></div>}</SectionHeader>
    {!saved.exists && <p>Contact details and carrier standard units and codes still need to be completed by an authorised administrator.</p>}
    {step==="general"&&<div className="details-heading"><h3>STANDARD UNITS AND STARTING WEIGHT PRINCIPLE</h3><div className="c5-heading-actions"><ConfigurationStatusBadge status={b1UnitsStatus(saved)}/>{!editing&&saved.canEdit&&<SaveButton className="secondary" onClick={edit}>EDIT</SaveButton>}</div></div>}
    {editing ? <form noValidate onSubmit={event => {
      event.preventDefault(); setError(""); setFields({});
      startTransition(async () => {
        try {
          const result = await saveDetails(iata, saved.revision, draft);
          if (result.ok) {setError("");setSaved(result.snapshot);saveFeedback.complete(()=>{  setEditing(false); window.dispatchEvent(new CustomEvent(INDEX_DISPLAY_PREFERENCE_EVENT,{detail:{iata,indexDecimalPlaces:result.snapshot.values.indexDecimalPlaces==="2"?2:1}})); router.refresh(); setMessage("Carrier details and carrier standard units and codes saved."); });}
          else { setError(result.error); setFields(result.fields ?? {}); if (result.fields) setStep(contactFields.some(field => result.fields?.[field.key]) ? "contact" : "general"); }
        } catch { setError("Unable to save. Your entries are still here; please try again."); }
      });
    }}>
      {step === "contact" && <fieldset disabled={pending}><legend>Contact details</legend><p className="muted">Fields marked * are required.</p><div className="details-grid">
      {contactFields.map(field => <div className="details-field" key={field.key}><label htmlFor={`detail-${field.key}`}>{field.label}{"required" in field ? " *" : ""}</label><SaveInput id={`detail-${field.key}`} name={field.key} type={field.key === "email" ? "email" : field.key === "telephone" ? "tel" : "text"} value={draft[field.key]} maxLength={field.max} required={"required" in field} aria-invalid={!!fields[field.key]} aria-describedby={fields[field.key] ? `error-${field.key}` : undefined} onChange={event => { const value = event.target.value; setDraft(current => ({ ...current, [field.key]: value })); }} />{fields[field.key] && <span className="field-error" id={`error-${field.key}`}>{fields[field.key]}</span>}</div>)}
      </div></fieldset>}
      {step === "general" && <fieldset disabled={pending}><legend>1. STANDARD UNITS AND CODES</legend><div className="details-grid">{choices.map(field => <div className="details-field" key={field.key}><label htmlFor={`detail-${field.key}`}>{field.label} *</label><SaveSelect id={`detail-${field.key}`} value={draft[field.key]} required aria-invalid={!!fields[field.key]} aria-describedby={fields[field.key] ? `error-${field.key}` : undefined} onChange={event => { const value = event.target.value; setDraft(current => ({ ...current, [field.key]: value })); }}><option value="">Choose…</option>{field.options.map(([value,label]) => <option key={value} value={value}>{label}</option>)}</SaveSelect>{fields[field.key] && <span className="field-error" id={`error-${field.key}`}>{fields[field.key]}</span>}</div>)}</div><fieldset className="index-display-preference" aria-describedby={fields.indexDecimalPlaces?"error-indexDecimalPlaces":undefined}><legend>Display (and Print) INDEX values to</legend><label><SaveInput type="radio" name="index-decimal-places" checked={draft.indexDecimalPlaces==="1"} onChange={()=>setDraft(current=>({...current,indexDecimalPlaces:"1"}))}/> ONE Decimal Place</label><label><SaveInput type="radio" name="index-decimal-places" checked={draft.indexDecimalPlaces==="2"} onChange={()=>setDraft(current=>({...current,indexDecimalPlaces:"2"}))}/> TWO Decimal Places</label>{fields.indexDecimalPlaces&&<span className="field-error" id="error-indexDecimalPlaces">{fields.indexDecimalPlaces}</span>}</fieldset></fieldset>}
      {error && <p role="alert" className="field-error">{error}</p>}
      <div className="logo-actions"><SaveSubmit disabled={pending} type="submit">{pending ? "Saving…" : "Save changes"}</SaveSubmit><SaveCancel disabled={pending} type="button" className="secondary" onClick={() => { setEditing(false); setError(""); setFields({}); }}>Cancel</SaveCancel></div>
    </form> : <>{step === "contact" ? <><h3>Contact details</h3><dl className="details-grid">{contactFields.map(field => <div key={field.key}><dt>{field.label}</dt><dd>{saved.values[field.key] || "Not provided"}</dd></div>)}</dl></> : <><dl className="details-grid">{choices.map(field => <div key={field.key}><dt>{field.label}</dt><dd>{field.options.find(([value]) => value === saved.values[field.key])?.[1] ?? "Not provided"}</dd></div>)}</dl><dl className="index-display-preference saved"><div><dt>Display (and Print) INDEX values to</dt><dd>{saved.values.indexDecimalPlaces==="2"?"TWO Decimal Places":"ONE Decimal Place"}</dd></div></dl></>}</>}
    {!editing && !saved.canEdit && <p className="muted">These details are read-only for your account.</p>}
    <p role="status" aria-live="polite">{message}</p>
    {step === "general" && commodityEditor}
  </section>{children}<nav className="section-navigation" aria-label="Carrier setup sections">{step === "contact" ? <Link className="section-link" href={`/carrier/${encodeURIComponent(iata)}/a5`}>NEXT: A5. AUTOMATIC DOCUMENTS →</Link> : <Link className="section-link secondary" href={`/carrier/${encodeURIComponent(iata)}/a5`}>← A5. AUTOMATIC DOCUMENTS</Link>}{step === "general" && !editing && <Link className="section-link" href={`/carrier/${encodeURIComponent(iata)}/crew-weights`}>NEXT: B2. CREW →</Link>}</nav></>}</SaveScope>;
}
