"use client";
import {useSaveFeedback,SaveScope,SaveInput,SaveButton,SaveSubmit,SaveCancel} from "@/components/save-feedback";
import { SectionHeader } from "@/components/section-header";
import { useState } from "react";
import { saveCrewWeights } from "@/app/crew-actions";
import { crewDraft, crewBodyValues, CrewInvalid, type CrewSnapshot, type CrewWeightKey } from "@/domain/crew-weights";
import {ConfigurationStatusBadge} from "@/components/configuration-status-badge";
import {b2Statuses} from "@/domain/b2-status";
import {CrewHoldBaggage} from "./crew-hold-baggage";
import {displayUnit} from "@/domain/display-standards";
export function CrewWeights({ iata, initial }: { iata: string; initial: CrewSnapshot }) {
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState(() => crewDraft(initial.values));
  const [editing, setEditing] = useState(false);
  const [pending, startTransition,saveFeedback] = useSaveFeedback();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const included = editing ? draft.includesHandBaggage : saved.values.includesHandBaggage;
  const completion=b2Statuses(saved);
  function beginEdit(){setDraft(crewDraft(saved.values));setError("");setMessage("");setEditing(true);}
  function field(key: CrewWeightKey, label: string, required = false, inactive = false, inactiveText = "Included in Crew Weight") {
    if (!editing) return <span>{inactive ? inactiveText : saved.values[key] === null ? "Not specified" : saved.values[key]}</span>;
    return <SaveInput aria-label={`${label} (${displayUnit(saved.unit)||"unit not set"})`} type="number" inputMode="numeric" step="1" min={key.endsWith("Male") || key.endsWith("Female") ? 1 : 0} max="2147483647" required={required} disabled={inactive} value={draft[key]} onChange={event => { const value = event.target.value; setError(""); setDraft(current => ({ ...current, [key]: value })); }} />;
  }
  if (!saved.canView) return <SaveScope feedback={saveFeedback}>{<section className="overview"><h2>2. CREW AND CREW BAGGAGE WEIGHTS</h2><p>You do not have access to crew weights for this carrier.</p></section>}</SaveScope>;
  return <SaveScope feedback={saveFeedback}>{<section className="overview carrier-details crew-weights" aria-labelledby="crew-title">
    <SectionHeader id="crew-title" title="2. CREW AND CREW BAGGAGE WEIGHTS" reference="(AHM565 Sheet B2)"><div className="c5-heading-actions"><ConfigurationStatusBadge status={completion.page} variant="large"/>{!editing && saved.canEdit && saved.unit && <SaveButton className="secondary" onClick={beginEdit}>EDIT</SaveButton>}</div></SectionHeader>
    <p className="muted">{saved.unit ? `All weights are in ${displayUnit(saved.unit)}, as selected on Sheet B1.` : "Choose and save a weight unit on Sheet B1 before entering crew weights."}</p>
    {!saved.exists && <p>No crew weights have been saved for this carrier.</p>}
    <form noValidate onSubmit={event => { event.preventDefault(); if (!editing) return; setError("");
      try { crewBodyValues(draft); } catch (cause) { setError(cause instanceof CrewInvalid ? cause.message : "Check the weights."); return; }
      startTransition(async () => { try { const result = await saveCrewWeights(iata, saved.revision, draft); if (result.ok) {setError("");saveFeedback.complete(()=>{ setSaved(result.snapshot); setDraft(crewDraft(result.snapshot.values)); setEditing(false); setMessage("Crew and crew baggage weights saved."); });} else setError(result.error); } catch { setError("Unable to save. Your entries are still here; please try again."); } });
    }}><fieldset disabled={pending}><legend className="sr-only">Crew and crew baggage weights</legend>
      <section className="commodity-section" aria-labelledby="crew-body-title"><div className="details-heading"><h3 id="crew-body-title">CREW WEIGHTS</h3><ConfigurationStatusBadge status={completion.crewWeights}/></div>
        <div className="commodity-table"><table><thead><tr><th scope="col">Gender</th><th scope="col">Flight Deck Crew</th><th scope="col">Cabin Crew</th></tr></thead><tbody>
          <tr><th scope="row">Male</th><td>{field("flightDeckMale","Flight Deck Crew — Male",true)}</td><td>{field("cabinMale","Cabin Crew — Male",true)}</td></tr>
          <tr><th scope="row">Female</th><td>{field("flightDeckFemale","Flight Deck Crew — Female",true)}</td><td>{field("cabinFemale","Cabin Crew — Female",true)}</td></tr>
        </tbody></table></div>
      </section>
      <section className="commodity-section" aria-labelledby="crew-hand-title"><div className="details-heading"><h3 id="crew-hand-title">CREW HAND BAGGAGE</h3><ConfigurationStatusBadge status={completion.handBaggage}/></div>
        <label className="crew-checkbox"><SaveInput type="checkbox" checked={included} disabled={!editing} onChange={event => { const checked = event.target.checked; setError(""); setDraft(current => ({ ...current, includesHandBaggage: checked })); }} />Crew Weights include Hand Baggage</label>
        <p className="muted">{included ? "Hand Baggage is included in Crew Weights. Separate Hand-Baggage values are inactive." : "Enter a separate hand-baggage weight for Flight Deck Crew and Cabin Crew."}</p>
        <div className="commodity-table"><table><thead><tr><th scope="col">Hand Baggage</th><th scope="col">Flight Deck Crew</th><th scope="col">Cabin Crew</th></tr></thead><tbody><tr><th scope="row">Weight{!included ? " *" : ""}</th><td>{field("flightDeckHand","Flight Deck Crew — Hand Baggage",!included,included)}</td><td>{field("cabinHand","Cabin Crew — Hand Baggage",!included,included)}</td></tr></tbody></table></div>
      </section>
      {error && <p role="alert" className="field-error">{error}</p>}
      {editing && <div className="logo-actions"><SaveSubmit type="submit">{pending ? "Saving…" : "Save Crew Weights"}</SaveSubmit><SaveCancel className="secondary" type="button" onClick={() => { setEditing(false); setError(""); }}>Cancel</SaveCancel></div>}
    </fieldset></form>
    <CrewHoldBaggage iata={iata} snapshot={saved} onSaved={setSaved}/>
    {!saved.canEdit && <p className="muted">These weights are read-only for your account.</p>}
    <p role="status" aria-live="polite">{message}</p>
  </section>}</SaveScope>;
}
