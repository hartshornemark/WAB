"use client";

import { useState } from "react";
import { SaveButton, SaveInput } from "@/components/save-feedback";
import { aircraftD3CsvTemplate, parseAircraftD3Csv, type AircraftD3CsvResult } from "@/domain/aircraft-d3-csv";
import type { AircraftD3Configuration, AircraftD3Hold, AircraftD3UldOption } from "@/domain/aircraft-d3";

type HoldPreview = { hold: AircraftD3Hold; result: AircraftD3CsvResult };

export function AircraftD3CsvImport({
  holds,
  uldOptions,
  onApply,
}: {
  holds: AircraftD3Hold[];
  uldOptions: AircraftD3UldOption[];
  onApply: (configurations: AircraftD3Configuration[]) => Promise<boolean>;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [code, setCode] = useState("A");
  const [description, setDescription] = useState("Imported AHM565 positions");
  const [previews, setPreviews] = useState<HoldPreview[]>([]);
  const [pending, setPending] = useState(false);

  async function load(file: File | undefined) {
    if (!file) return;
    const text = await file.text();
    setName(file.name);
    setPreviews(holds.map(hold => ({
      hold,
      result: parseAircraftD3Csv(text, hold.compartments ?? [], uldOptions),
    })));
    setOpen(true);
  }

  async function apply() {
    if (!valid || pending) return;
    const configurations = previews.map(({ hold, result }) => ({
      holdId: hold.id,
      code,
      description: description.trim() || null,
      expectedPositionCount: result.atomicBays.length,
      atomicBays: result.atomicBays,
      rows: result.rows,
    }));
    setPending(true);
    const saved = await onApply(configurations);
    setPending(false);
    if (saved) close();
  }

  function close() {
    setOpen(false);
    setName("");
    setPreviews([]);
  }

  function download() {
    const blob = new Blob([aircraftD3CsvTemplate], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "d3-uld-positions-template.csv";
    link.click();
    URL.revokeObjectURL(url);
  }

  const errors = previews.flatMap(({ hold, result }) => result.errors.map(error => `${hold.id}: ${error}`));
  const validCode = /^[A-Z0-9][A-Z0-9_-]{0,19}$/.test(code);
  const valid = previews.length === holds.length && previews.length > 0 && errors.length === 0 && validCode;

  return <section className="d3-sheet-import">
    <div className="d3-sheet-import-heading">
      <div>
        <strong>IMPORT ALL ULD HOLDS</strong>
        <p>Upload one AHM565 CSV. Positions are assigned to the applicable D2 hold from their compartment numbers.</p>
      </div>
      <div className="d3-csv-actions">
        <label className="secondary button-like">IMPORT CSV
          <SaveInput type="file" accept=".csv,text/csv" onChange={event => void load(event.target.files?.[0])}/>
        </label>
        <SaveButton type="button" className="secondary" onClick={download}>DOWNLOAD AHM565 TEMPLATE</SaveButton>
      </div>
    </div>
    {open && <section className="d3-csv-preview">
      <div>
        <strong>AIRCRAFT IMPORT PREVIEW</strong>
        <p>{name} · {previews.length} ULD holds</p>
      </div>
      <div className="d3-config-fields">
        <label><span>Configuration Code</span><SaveInput value={code} maxLength={20} onChange={event => setCode(event.target.value.toUpperCase().replace(/[^A-Z0-9_-]/g, ""))}/></label>
        <label><span>Description (optional)</span><SaveInput value={description} maxLength={80} onChange={event => setDescription(event.target.value)}/></label>
      </div>
      {!validCode && <p className="field-error">Configuration Code must use 1–20 letters, numbers, hyphens or underscores.</p>}
      {errors.length > 0 ? <div className="d3-csv-errors" role="alert"><strong>Resolve these CSV issues:</strong><ul>{errors.map(error => <li key={error}>{error}</li>)}</ul></div> :
        <div className="d3-hold-import-summary">{previews.map(({ hold, result }) => <div key={hold.id}>
          <strong>{hold.id}</strong>
          <span>{result.atomicBays.length} Atomic Bays</span>
          <span>{result.rows.length} Loading Arrangements</span>
          <small>Compartments {(hold.compartments ?? []).join(", ")}</small>
        </div>)}</div>}
      <p className="muted">Importing replaces configuration {code || "—"} in every listed hold. Other configuration codes remain unchanged.</p>
      <div className="d3-csv-preview-actions">
        <SaveButton type="button" className="secondary" onClick={close} disabled={pending}>CANCEL</SaveButton>
        <SaveButton type="button" disabled={!valid || pending} onClick={() => void apply()}>{pending ? "IMPORTING" : "IMPORT ALL HOLDS"}</SaveButton>
      </div>
    </section>}
  </section>;
}
