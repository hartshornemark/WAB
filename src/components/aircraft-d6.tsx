"use client";
import {useSaveFeedback,SaveScope,SaveInput,SaveButton,SaveCancel,SaveSubmit} from "@/components/save-feedback";

import { useState } from "react";
import { saveAircraftD6, setAircraftD6Applicability } from "@/app/aircraft-d6-actions";
import { ConfigurationStatusBadge } from "@/components/configuration-status-badge";
import { SectionHeader } from "@/components/section-header";
import { aircraftD6Status, aircraftD6Statuses } from "@/domain/aircraft-d6-status";
import type {
  AircraftD6Snapshot,
  D6Section,
  GalleyLocation,
  WaterLocation,
} from "@/domain/aircraft-d6";
import {
  balanceArmFromIndexPerWeightUnit,
  validIndexPerWeightUnitFormula,
} from "@/domain/index-per-weight-unit";

const shown = (value: number | null, decimals = 3) =>
  value === null ? "—" : value.toFixed(decimals);
const numeric = (value: string) => value.trim() === "" ? null : Number(value);
const blankWater = (): WaterLocation => ({
  id: "", name: "", maxWeight: null, centroid: null, index: null,
});
const blankGalley = (): GalleyLocation => ({
  id: "", description: "", maxWeight: null, centroid: null, index: null,
});
type D6Row = WaterLocation | GalleyLocation;

export function AircraftD6({ iata, initial }: { iata: string; initial: AircraftD6Snapshot }) {
  const [saved, setSaved] = useState(initial);
  const statuses = aircraftD6Statuses(saved);
  return <section className="aircraft-d6">
    <SectionHeader id="aircraft-d6-heading" title="D6. WATER, GALLEY & OTHER LOCATIONS" reference="(AHM565 Sheet D6)">
      <ConfigurationStatusBadge status={aircraftD6Status(saved)} variant="large" />
    </SectionHeader>
    <p className="c5-intro">Select the sections used by this aircraft, then configure at least one complete row in every active section. Lateral balance fields are provisioned and disabled.</p>
    <D6Editor iata={iata} snapshot={saved} setSnapshot={setSaved} section="waterLocations" title="POTABLE WATER LOCATIONS" status={statuses.waterLocations} />
    <D6Editor iata={iata} snapshot={saved} setSnapshot={setSaved} section="galleyLocations" title="GALLEYS AND OTHER LOCATIONS" status={statuses.galleyLocations} />
  </section>;
}

function D6Editor({ iata, snapshot, setSnapshot, section, title, status }: {
  iata: string;
  snapshot: AircraftD6Snapshot;
  setSnapshot: (value: AircraftD6Snapshot) => void;
  section: D6Section;
  title: string;
  status: ReturnType<typeof aircraftD6Statuses>[D6Section];
}) {
  const source = snapshot[section] as D6Row[];
  const savedApplicable = section === "waterLocations"
    ? snapshot.waterApplicable
    : snapshot.galleyApplicable;
  const [draft, setDraft] = useState<D6Row[]>(source);
  const [editing, setEditing] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [pending, start,saveFeedback] = useSaveFeedback();

  const begin = () => {
    setDraft(source.map((row) => ({ ...row })));
    setError("");
    setMessage("");
    setEditing(true);
  };
  const change = (index: number, key: string, value: unknown) => setDraft((rows) =>
    rows.map((row, rowIndex) => {
      if (rowIndex !== index) return row;
      const next = { ...row, [key]: value };
      if (key === "index" && validIndexPerWeightUnitFormula(snapshot.balanceFormula)) {
        if (value === "") return { ...next, centroid: null };
        const indexValue = typeof value === "number" ? value : Number(value);
        return {
          ...next,
          centroid: Number.isFinite(indexValue)
            ? balanceArmFromIndexPerWeightUnit(indexValue, snapshot.balanceFormula)
            : null,
        };
      }
      return next;
    })
  );
  const add = () => setDraft((rows) => [
    ...rows,
    section === "waterLocations" ? blankWater() : blankGalley(),
  ]);
  const save = () => start(async () => {
    const result = await saveAircraftD6(
      iata,
      snapshot.typeCode,
      snapshot.subtype,
      snapshot.revision,
      section,
      true,
      draft,
    );
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setError("");setSnapshot(result.snapshot);saveFeedback.complete(()=>{
    setEditing(false);
    setError("");
    setMessage("SAVED");});
  });
  const toggleApplicable = (applicable: boolean) => start(async () => {
    setError("");
    setMessage("");
    const result = await setAircraftD6Applicability(
      iata,
      snapshot.typeCode,
      snapshot.subtype,
      snapshot.revision,
      section,
      applicable,
    );
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setSnapshot(result.snapshot);
  });
  const visible = savedApplicable === true;
  const description = visible
    ? "Enter Index Per Weight Unit. Balance Arm Centroid is calculated from C4."
    : "Check this section to activate and configure it.";

  return <SaveScope feedback={saveFeedback}>{<section className={`d6-card ${visible ? "" : "d6-inactive"}`}>
    <div className="d4-heading">
      <label className="d6-applicability">
        <SaveInput
          type="checkbox"
          checked={savedApplicable === true}
          disabled={!snapshot.canEdit || pending || editing}
          onChange={(event) => toggleApplicable(event.target.checked)}
        />
        <span><h3>{title}</h3><p>{description}</p></span>
      </label>
      <div className="c5-heading-actions">
        {message && <span className="form-success c5-inline-success">{message}</span>}
        {snapshot.canEdit && savedApplicable === true && !editing && <SaveButton className="secondary" onClick={begin}>EDIT</SaveButton>}
        <ConfigurationStatusBadge status={status} />
      </div>
    </div>
    {visible && <D6Rows
      rows={editing ? draft : source}
      section={section}
      editing={editing}
      change={change}
      remove={(index) => setDraft((rows) => rows.filter((_, rowIndex) => rowIndex !== index))}
    />}
    {visible && !source.length && !editing && <p className="d2-empty">No rows have been configured.</p>}
    {error && <p className="field-error" role="alert">{error}</p>}
    {editing && <div className="d5-edit-footer">
      <span><SaveButton className="secondary" onClick={add}>ADD ROW</SaveButton></span>
      <div className="c7-actions">
        <SaveCancel className="secondary" disabled={pending} onClick={() => { setEditing(false); setError(""); }}>CANCEL</SaveCancel>
        <SaveSubmit disabled={pending} onClick={save}>{pending ? "Saving…" : "SAVE"}</SaveSubmit>
      </div>
    </div>}
  </section>}</SaveScope>;
}

function D6Rows({ rows, section, editing, change, remove }: {
  rows: D6Row[];
  section: D6Section;
  editing: boolean;
  change: (index: number, key: string, value: unknown) => void;
  remove: (index: number) => void;
}) {
  if (!rows.length) return null;
  const nameLabel = section === "waterLocations" ? "Tank Name" : "Description";
  const weightLabel = "Max Weight (Kg)";
  return <div className="d6-table">
    <div className={`d6-row d6-head ${editing ? "d6-head-editing" : ""}`}>
      <span>Short Code</span><span>{nameLabel}</span><span>{weightLabel}</span>
      <span className="d6-disabled-head">Lateral Centroid</span>
      <span>Balance Arm Centroid (Calculated)</span><span>Index Per Weight Unit</span>
      {editing && <span>Action</span>}
    </div>
    {rows.map((row, index) => <div className="d6-row" key={index}>
      {editing ? <>
        <label><span>Short Code</span><SaveInput aria-label={`Short Code ${index + 1}`} value={row.id} maxLength={3} onChange={(event) => change(index, "id", event.target.value.toUpperCase())} /></label>
        <label><span>{nameLabel}</span><SaveInput aria-label={`${nameLabel} ${index + 1}`} value={section === "waterLocations" ? (row as WaterLocation).name : (row as GalleyLocation).description} maxLength={64} onChange={(event) => change(index, section === "waterLocations" ? "name" : "description", event.target.value)} /></label>
        <label><span>{weightLabel}</span><SaveInput aria-label={`${weightLabel} ${index + 1}`} inputMode="numeric" value={row.maxWeight ?? ""} onChange={(event) => change(index, "maxWeight", numeric(event.target.value))} /></label>
        <label className="d6-disabled-cell"><span>Lateral Centroid</span><SaveInput aria-label={`Lateral Centroid ${index + 1}`} disabled value="" /></label>
        <label className="d6-calculated-cell"><span>Balance Arm Centroid (Calculated)</span><SaveInput aria-label={`Balance Arm Centroid Calculated ${index + 1}`} inputMode="decimal" value={row.centroid ?? ""} disabled /></label>
        <label><span>Index Per Weight Unit</span><SaveInput aria-label={`Index Per Weight Unit ${index + 1}`} inputMode="decimal" value={row.index ?? ""} onChange={(event) => change(index, "index", event.target.value)} /></label>
        <SaveButton className="secondary" onClick={() => remove(index)}>REMOVE</SaveButton>
      </> : <>
        <strong data-label="Short Code">{row.id}</strong>
        <span data-label={nameLabel}>{section === "waterLocations" ? (row as WaterLocation).name : (row as GalleyLocation).description}</span>
        <span data-label={weightLabel}>{row.maxWeight}</span>
        <span data-label="Lateral Centroid" className="d6-disabled-cell">—</span>
        <span data-label="Balance Arm Centroid (Calculated)">{shown(row.centroid)}</span>
        <span data-label="Index Per Weight Unit">{shown(row.index, 5)}</span>
      </>}
    </div>)}
  </div>;
}
