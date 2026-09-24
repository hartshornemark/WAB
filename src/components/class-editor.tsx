"use client";
import { useState, useTransition } from "react";
import { saveClassCodes } from "@/app/class-actions";
import { validateClasses, ClassInvalid, type ClassSnapshot } from "@/domain/class-codes";
import {ConfigurationStatusBadge} from "@/components/configuration-status-badge";
import {b1ClassStatus} from "@/domain/b1-status";
import {useRouter} from "next/navigation";
export function ClassEditor({ iata, initial, passengerOperations }: { iata: string; initial: ClassSnapshot; passengerOperations:boolean }) {
  const router=useRouter();
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState(initial.rows);
  const [editing, setEditing] = useState(false);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  if (!saved.canView) return <p>Class codes are not available for your account.</p>;
  if (!passengerOperations) return <section className="commodity-section" aria-labelledby="class-title"><div className="details-heading"><h3 id="class-title">CARRIER CLASS CODES</h3><ConfigurationStatusBadge status="not_required"/></div><p>This carrier currently operates only Freighter aircraft. Passenger class codes are not required; any existing data is retained.</p></section>;
  const suggested = saved.rows.length === 0;
  const displayed = suggested ? saved.defaults : saved.rows;
  return <section className="commodity-section" aria-labelledby="class-title">
    <div className="details-heading"><h3 id="class-title">CARRIER CLASS CODES</h3><div className="c5-heading-actions"><ConfigurationStatusBadge status={b1ClassStatus(saved)}/>{!editing && saved.canEdit && <button className="secondary" onClick={() => { setDraft(displayed.map(row => ({ ...row }))); setError(""); setMessage(""); setEditing(true); }}>EDIT</button>}</div></div>
    <p>Keep One to Four classes. You may change each Class Code, Priority and Name/Description. You may remove Classes you do not use.</p>
    {suggested && <p className="muted">No carrier-specific classes have been saved. The master list is a starting point; review it and save to create this carrier’s classes.</p>}
    {editing ? <form noValidate onSubmit={event => {
      event.preventDefault(); setError("");
      try { validateClasses(draft); } catch (cause) { setError(cause instanceof ClassInvalid ? cause.message : "Check the class details."); return; }
      startTransition(async () => {
        try { const result = await saveClassCodes(iata, saved.revision, draft); if (result.ok) { setSaved(result.snapshot); setEditing(false); setMessage("Carrier class codes saved.");router.refresh(); } else setError(result.error); }
        catch { setError("Unable to save. Your entries are still here; please try again."); }
      });
    }}><fieldset disabled={pending}><legend>Classes</legend>
      {draft.map((row, index) => <div className="class-row" key={index}>
        <div><label htmlFor={`class-code-${index}`}>Class Code</label><input id={`class-code-${index}`} value={row.code} maxLength={1} pattern="[A-Za-z]" required autoCapitalize="characters" onChange={event => { const value = event.target.value; setDraft(current => current.map((item, i) => i === index ? { ...item, code: /^[a-z]$/.test(value) ? value.toUpperCase() : value } : item)); }} /></div>
        <div><label htmlFor={`class-priority-${index}`}>Priority</label><select id={`class-priority-${index}`} value={row.priority} onChange={event => { const priority = Number(event.target.value); setDraft(current => current.map((item, i) => i === index ? { ...item, priority } : item)); }}>{[1,2,3,4].map(priority => <option key={priority} value={priority}>{priority}</option>)}</select></div>
        <div><label htmlFor={`class-description-${index}`}>Name / Description</label><input id={`class-description-${index}`} value={row.description} maxLength={64} required onChange={event => { const description = event.target.value; setDraft(current => current.map((item, i) => i === index ? { ...item, description } : item)); }} /></div>
        <button className="secondary" type="button" aria-label={`Remove class ${row.code || index + 1}`} onClick={() => setDraft(current => current.filter((_, i) => i !== index))}>Remove</button>
      </div>)}
      <button className="secondary" type="button" disabled={draft.length >= 4} onClick={() => setDraft(current => [...current, { code: "", priority: [1,2,3,4].find(priority => !current.some(row => row.priority === priority)) ?? 1, description: "" }])}>Add Class</button>
      <p className="muted">Codes must be a single letter A–Z. Each code and priority must be unique. Names may contain up to 64 characters. Removing a class does not renumber the others; changes take effect when you save.</p>
      {error && <p className="field-error" role="alert">{error}</p>}
      <div className="logo-actions"><button type="submit">{pending ? "Saving…" : "Save Class Codes"}</button><button className="secondary" type="button" onClick={() => { setEditing(false); setError(""); }}>Cancel</button></div>
    </fieldset></form> : <><div className="commodity-table"><table><thead><tr><th scope="col">Class Code</th><th scope="col">Priority</th><th scope="col">Name / Description</th></tr></thead><tbody>{displayed.map(row => <tr key={row.code}><td>{row.code}</td><td>{row.priority}</td><td>{row.description}</td></tr>)}</tbody></table></div>{!saved.canEdit && <p className="muted">These classes are read-only for your account.</p>}</>}
    <p role="status" aria-live="polite">{message}</p>
  </section>;
}
