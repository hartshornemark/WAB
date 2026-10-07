"use client";

import { useState } from "react";
import { CsvImportHelp } from "@/components/csv-import-help";
import { SaveButton, SaveInput } from "@/components/save-feedback";
import { aircraftD2CsvTemplate, parseAircraftD2Csv, type AircraftD2CsvIdentity, type AircraftD2CsvResult } from "@/domain/aircraft-d2-csv";
import type { AircraftD2HoldRow, AircraftD2Snapshot } from "@/domain/aircraft-d2";

export function AircraftD2CsvImport({ snapshot, disabled, onApply }: {
  snapshot: AircraftD2Snapshot;
  disabled: boolean;
  onApply: (rows: AircraftD2HoldRow[], source: AircraftD2CsvIdentity) => Promise<{ ok: boolean; error?: string }>;
}) {
  const [name, setName] = useState("");
  const [preview, setPreview] = useState<AircraftD2CsvResult | null>(null);
  const [pending, setPending] = useState(false);
  const [saveError, setSaveError] = useState("");

  async function load(file: File | undefined) {
    if (!file) return;
    setName(file.name);
    setPreview(parseAircraftD2Csv(await file.text(), snapshot.deckTypes, snapshot.fuelConfigurations ?? [], snapshot.balanceFormula, {typeCode:snapshot.typeCode,subtype:snapshot.subtype}));
    setSaveError("");
  }
  function download() {
    const blob = new Blob([aircraftD2CsvTemplate(snapshot.typeCode,snapshot.subtype)], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob), link = document.createElement("a");
    link.href = url;
    link.download = `d2-${snapshot.typeCode}-${snapshot.subtype}-holds-template.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }
  async function apply() {
    if (!preview || preview.errors.length || !preview.rows.length || !preview.source || pending) return;
    setPending(true);
    const result = await onApply(preview.rows, preview.source);
    setPending(false);
    if (result.ok) { setPreview(null); setName(""); setSaveError(""); }
    else setSaveError(result.error ?? "Unable to import D2 Holds.");
  }
  const compartments = preview?.rows.reduce((total, hold) => total + hold.compartments.length, 0) ?? 0;
  const areas = preview?.rows.reduce((total, hold) => total + hold.compartments.reduce((count, compartment) => count + compartment.areas.length, 0), 0) ?? 0;
  const bulkHolds=preview?.rows.filter(hold=>hold.holdType==="BLK").length??0;
  const uldHolds=preview?.rows.filter(hold=>hold.holdType==="ULD").length??0;
  return <section className="d3-sheet-import">
    <div className="d3-sheet-import-heading">
      <div><strong>IMPORT D2 HOLDS</strong><p>Upload one D2 CSV containing Bulk and/or ULD Hold rows.</p></div>
      <div className="d3-csv-actions">
        <CsvImportHelp kind="d2"/>
        <label className={`secondary button-like${disabled ? " disabled" : ""}`}>IMPORT CSV
          <SaveInput type="file" accept=".csv,text/csv" disabled={disabled} onChange={event => void load(event.target.files?.[0])}/>
        </label>
        <SaveButton type="button" className="secondary" onClick={download}>DOWNLOAD D2 TEMPLATE</SaveButton>
      </div>
    </div>
    {disabled && <p className="muted">Finish or cancel the current D2 edit before importing.</p>}
    {preview && <section className="d3-csv-preview">
      <div><strong>D2 HOLD IMPORT PREVIEW</strong><p>{name}</p></div>
      <p className={preview.source&&preview.source.typeCode===snapshot.typeCode&&preview.source.subtype===snapshot.subtype?"form-success":"field-error"}><strong>CSV aircraft:</strong> {preview.source?`${preview.source.typeCode}-${preview.source.subtype}`:"Not identified"} · <strong>Open page:</strong> {snapshot.typeCode}-{snapshot.subtype}</p>
      {preview.errors.length ? <div className="d3-csv-errors" role="alert"><strong>Resolve these CSV issues:</strong><ul>{preview.errors.map((error, index) => <li key={`${error}-${index}`}>{error}</li>)}</ul></div> :
        <div className="d3-hold-import-summary"><div><strong>{preview.rows.length} Holds</strong><span>{bulkHolds} Bulk · {uldHolds} ULD</span><span>{compartments} Compartments</span><span>{areas} Areas</span></div></div>}
      <p className="muted">Selecting IMPORT &amp; SAVE immediately replaces each Hold Type included in the CSV. An absent Hold Type is unchanged; no additional section SAVE is required.</p>
      {saveError && <p className="field-error">{saveError}</p>}
      <div className="d3-csv-preview-actions">
        <SaveButton type="button" className="secondary" disabled={pending} onClick={() => { setPreview(null); setName(""); setSaveError(""); }}>CANCEL</SaveButton>
        <SaveButton type="button" disabled={pending || preview.errors.length > 0 || preview.rows.length === 0} onClick={() => void apply()}>{pending ? "IMPORTING & SAVING" : "IMPORT & SAVE D2 HOLDS"}</SaveButton>
      </div>
    </section>}
  </section>;
}
