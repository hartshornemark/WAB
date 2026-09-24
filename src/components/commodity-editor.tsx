"use client";
import { useState, useTransition } from "react";
import { saveCommodityCodes } from "@/app/commodity-actions";
import type { CommoditySnapshot } from "@/domain/commodity-codes";
import {ConfigurationStatusBadge} from "@/components/configuration-status-badge";
import {b1CommodityStatus} from "@/domain/b1-status";
import {useRouter} from "next/navigation";
export function CommodityEditor({ iata, initial }: { iata: string; initial: CommoditySnapshot }) {
  const router=useRouter();
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState(initial.rows);
  const [editing, setEditing] = useState(false);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  if (!saved.canView) return <p>Commodity codes are not available for your account.</p>;
  const suggested = saved.rows.length === 0;
  const displayed = suggested ? saved.defaults : saved.rows;
  return <section className="commodity-section" aria-labelledby="commodity-title">
    <div className="details-heading"><h3 id="commodity-title">CARRIER LOAD COMMODITY CODES</h3><div className="c5-heading-actions"><ConfigurationStatusBadge status={b1CommodityStatus(saved)}/>{!editing && saved.canEdit && <button className="secondary" onClick={() => { setDraft(displayed.map(row => ({ ...row }))); setError(""); setMessage(""); setEditing(true); }}>EDIT</button>}</div></div>
    <p>This table maintains the complete set of Codes and Descriptions for your carrier. You may Change and/or Remove any/each Commodity Code as it may or may not apply to your Operations.</p>
    {suggested && <p className="muted">No carrier-specific set has been saved. {saved.defaults.length ? "The master list below is a starting point; review it and save to create this carrier’s set." : "An authorised administrator can add the carrier’s codes."}</p>}
    {editing ? <form onSubmit={event => { event.preventDefault(); setError(""); startTransition(async () => {
      try { const result = await saveCommodityCodes(iata, saved.revision, draft); if (result.ok) { setSaved(result.snapshot); setEditing(false); setMessage("Carrier commodity codes saved.");router.refresh(); } else setError(result.error); }
      catch { setError("Unable to save. Your entries are still here; please try again."); }
    }); }}><fieldset disabled={pending}><legend>Codes and descriptions</legend>
      {draft.map((row, index) => <div className="commodity-row" key={index}><div><label htmlFor={`commodity-code-${index}`}>Load Code</label><input id={`commodity-code-${index}`} value={row.code} maxLength={2} required onChange={event => setDraft(current => current.map((item, i) => i === index ? { ...item, code: event.target.value.toUpperCase() } : item))} /></div><div><label htmlFor={`commodity-description-${index}`}>Description</label><input id={`commodity-description-${index}`} value={row.description} maxLength={64} required onChange={event => setDraft(current => current.map((item, i) => i === index ? { ...item, description: event.target.value } : item))} /></div><button className="secondary" type="button" aria-label={`Remove code ${row.code || index + 1}`} onClick={() => setDraft(current => current.filter((_, i) => i !== index))}>Remove</button></div>)}
      <button className="secondary" type="button" disabled={draft.length >= 200} onClick={() => setDraft(current => [...current, { code: "", description: "" }])}>Add code</button>
      <p className="muted">Codes: 1–2 letters or numbers. Descriptions: up to 64 characters. Saving replaces the carrier’s complete set.</p>
      {error && <p className="field-error" role="alert">{error}</p>}<div className="logo-actions"><button type="submit">{pending ? "Saving…" : "Save commodity codes"}</button><button className="secondary" type="button" onClick={() => { setEditing(false); setError(""); }}>Cancel</button></div>
    </fieldset></form> : <><div className="commodity-table"><table><thead><tr><th scope="col">Load Code</th><th scope="col">Description</th></tr></thead><tbody>{displayed.map(row => <tr key={row.code}><td>{row.code}</td><td>{row.description}</td></tr>)}</tbody></table></div>{!saved.canEdit && <p className="muted">These codes are read-only for your account.</p>}</>}
    <p role="status" aria-live="polite">{message}</p>
  </section>;
}
