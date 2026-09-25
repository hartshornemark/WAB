"use client";
import {useId, useState} from "react";
import {fuelRowGeneration} from "@/domain/fuel-row-generation";

export function FuelRowGenerator({weights, unit, onGenerate}: {weights: number[]; unit: string; onGenerate: (weights: number[]) => void}) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const [range, setRange] = useState({start: "", last: "", increment: "", includeLast: false});
  const [notice, setNotice] = useState("");
  let preview: ReturnType<typeof fuelRowGeneration> | undefined, error = "";
  if (range.start && range.last && range.increment) {
    try { preview = fuelRowGeneration(range, weights); } catch (e) { error = (e as Error).message; }
  }
  return <div className="c8-generator">
    <button type="button" className="secondary" aria-expanded={open} aria-controls={id} onClick={() => {setOpen(!open); setNotice("");}}>GENERATE ROWS</button>
    {notice && <p role="status">{notice}</p>}
    {open && <section id={id} className="c8-generator-panel" aria-label="Generate fuel rows">
      <div className="c8-generator-fields">{([['start', 'Start Weight'], ['last', 'Last Generated Weight'], ['increment', 'Increment']] as const).map(([key, label]) =>
        <label key={key} htmlFor={`${id}-${key}`}>{label} ({unit})<input id={`${id}-${key}`} type="text" inputMode="numeric" value={range[key]} onChange={event => setRange({...range, [key]: event.target.value})}/></label>
      )}</div>
      {preview?.offStep && <label className="c8-generator-include"><input type="checkbox" checked={range.includeLast} onChange={event => setRange({...range, includeLast: event.target.checked})}/>Include Last Generated Weight ({range.last} {unit})</label>}
      <p className="muted">You can add more rows at any weight afterwards. Existing entries will be kept; new Index values will be blank. SAVE automatically adds a hidden zero-weight / zero-Index starting point.</p>
      {error && <p role="alert" className="field-error">{error}</p>}
      {preview && <p role="status">{preview.weights.length} new rows from {preview.first} to {preview.last} {unit}. {preview.skipped > 0 && `${preview.skipped} existing weights will be skipped.`}</p>}
      <div className="c8-generator-actions"><button type="button" className="secondary" onClick={() => setOpen(false)}>CANCEL GENERATION</button><button type="button" disabled={!preview?.weights.length} onClick={() => {if (!preview) return; onGenerate(preview.weights); setNotice(`${preview.weights.length} rows added. Enter their Index values, then SAVE the table.`); setOpen(false);}}>ADD GENERATED ROWS</button></div>
    </section>}
  </div>;
}
