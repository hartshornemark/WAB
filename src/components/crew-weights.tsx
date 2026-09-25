"use client";
import {useSaveFeedback,SaveScope,SaveInput,SaveButton,SaveSubmit,SaveCancel} from "@/components/save-feedback";
import { SectionHeader } from "@/components/section-header";
import { useState } from "react";
import { saveCrewWeights } from "@/app/crew-actions";
import { crewDraft, holdCategories, selectHoldCategory, validateCrewWeights, CrewInvalid, type CrewSnapshot, type CrewWeightKey } from "@/domain/crew-weights";
import {ConfigurationStatusBadge} from "@/components/configuration-status-badge";
import {b2Statuses} from "@/domain/b2-status";
import {displayUnit} from "@/domain/display-standards";
export function CrewWeights({ iata, initial }: { iata: string; initial: CrewSnapshot }) {
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState(() => crewDraft(initial.values));
  const [editing, setEditing] = useState(false);
  const [pending, startTransition,saveFeedback] = useSaveFeedback();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [defaultHold,setDefaultHold]=useState(()=>({flightDeck:String(initial.values.flightDeckOther??0),cabin:String(initial.values.cabinOther??0)}));
  const included = editing ? draft.includesHandBaggage : saved.values.includesHandBaggage;
  const selection = editing ? draft : saved.values;
  const completion=b2Statuses(saved);
  const hasSavedHold=saved.values.allFlights||saved.values.longhaul||saved.values.shorthaul;
  const showDefaultHold=!editing&&saved.exists&&!hasSavedHold;
  const canSaveDefault=saved.canEdit&&!!saved.unit&&completion.crewWeights==="configured"&&completion.handBaggage==="configured";
  function beginEdit(){
    const next=crewDraft(saved.values);
    if(!hasSavedHold){next.allFlights=true;next.flightDeckOther=defaultHold.flightDeck||"0";next.cabinOther=defaultHold.cabin||"0";}
    setDraft(next);setError("");setMessage("");setEditing(true);
  }
  function saveDefaultHold(){
    setError("");setMessage("");
    let values;
    try{values=validateCrewWeights({...saved.values,allFlights:true,longhaul:false,shorthaul:false,flightDeckOther:defaultHold.flightDeck,cabinOther:defaultHold.cabin});}
    catch(cause){setError(cause instanceof CrewInvalid?cause.message:"Check the Crew Hold Baggage weights.");return;}
    startTransition(async()=>{try{const result=await saveCrewWeights(iata,saved.revision,values);if(result.ok){setError("");saveFeedback.complete(()=>{setSaved(result.snapshot);setDraft(crewDraft(result.snapshot.values));setDefaultHold({flightDeck:String(result.snapshot.values.flightDeckOther??0),cabin:String(result.snapshot.values.cabinOther??0)});setMessage("Default All Flights Crew Hold Baggage saved.");});}else setError(result.error);}catch{setError("Unable to save. Your entries are still here; please try again.");}});
  }
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
      try { validateCrewWeights(draft); } catch (cause) { setError(cause instanceof CrewInvalid ? cause.message : "Check the weights."); return; }
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
      <section className="commodity-section" aria-labelledby="crew-baggage-title"><div className="details-heading"><h3 id="crew-baggage-title">CREW HOLD BAGGAGE</h3><ConfigurationStatusBadge status={completion.holdBaggage}/></div><p className="muted hold-category-note">Select All Flights for one set of weights, or select Longhaul and/or Shorthaul. All Flights cannot be combined with the other selections.</p>{showDefaultHold&&<p className="muted hold-category-note">All Flights with zero weights is the default suggestion. Review the values and save this row before it counts as configured.</p>}
        <div className="commodity-table"><table><thead><tr><th scope="col">Description</th><th scope="col">Flight Deck Crew Baggage</th><th scope="col">Cabin Crew Baggage</th>{showDefaultHold&&<th scope="col">Action</th>}</tr></thead><tbody>
          {holdCategories.map(category=>{
            if(showDefaultHold&&category.key==="allFlights")return <tr className="crew-default-row" key={category.key}><th scope="row"><span className="hold-category"><SaveInput type="checkbox" checked disabled readOnly/>All Flights <span className="crew-default-tag">DEFAULT</span></span></th><td><SaveInput aria-label={`Flight Deck Crew Baggage — All Flights (${displayUnit(saved.unit)||"unit not set"})`} type="number" inputMode="numeric" min="0" max="2147483647" value={defaultHold.flightDeck} disabled={!saved.canEdit||pending} onChange={event=>{setError("");setDefaultHold(current=>({...current,flightDeck:event.target.value}));}}/></td><td><SaveInput aria-label={`Cabin Crew Baggage — All Flights (${displayUnit(saved.unit)||"unit not set"})`} type="number" inputMode="numeric" min="0" max="2147483647" value={defaultHold.cabin} disabled={!saved.canEdit||pending} onChange={event=>{setError("");setDefaultHold(current=>({...current,cabin:event.target.value}));}}/></td><td>{saved.canEdit&&<SaveSubmit type="button" disabled={!canSaveDefault||pending} onClick={saveDefaultHold}>{pending?"Saving…":"SAVE"}</SaveSubmit>}</td></tr>;
            return <tr key={category.key}><th scope="row"><label className="hold-category"><SaveInput type="checkbox" checked={selection[category.key]} disabled={!editing||(category.key!=="allFlights"&&selection.allFlights)} onChange={event=>{const checked=event.target.checked;setError("");setDraft(current=>selectHoldCategory(current,category.key,checked));}}/>{category.label}</label></th><td>{field(category.flightDeck,`Flight Deck Crew Baggage — ${category.label}`,selection[category.key],!selection[category.key],"Not selected")}</td><td>{field(category.cabin,`Cabin Crew Baggage — ${category.label}`,selection[category.key],!selection[category.key],"Not selected")}</td>{showDefaultHold&&<td/>}</tr>;
          })}
        </tbody></table></div>
        {editing && <p className="muted">Enter both weights for each selected flight category, using whole numbers. Enter 0 only when the weight is zero. Deselected weights are retained but inactive.</p>}
      </section>
      {error && <p role="alert" className="field-error">{error}</p>}
      {editing && <div className="logo-actions"><SaveSubmit type="submit">{pending ? "Saving…" : "Save Crew Weights"}</SaveSubmit><SaveCancel className="secondary" type="button" onClick={() => { setEditing(false); setError(""); }}>Cancel</SaveCancel></div>}
    </fieldset></form>
    {!saved.canEdit && <p className="muted">These weights are read-only for your account.</p>}
    <p role="status" aria-live="polite">{message}</p>
  </section>}</SaveScope>;
}
