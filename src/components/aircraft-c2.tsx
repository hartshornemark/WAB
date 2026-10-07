"use client";
import {useSaveFeedback,SaveScope,SaveSubmit,SaveCancel,SaveButton,SaveInput,SaveSelect,SaveTextarea} from "@/components/save-feedback";

import { useState } from "react";
import { saveAircraftC2 } from "@/app/aircraft-c2-actions";
import { SectionHeader } from "@/components/section-header";
import { aircraftC2Statuses } from "@/domain/aircraft-c2-status";
import { ConfigurationStatusBadge } from "@/components/configuration-status-badge";
import type { AircraftOperatingRole } from "@/domain/aircraft-c1";
import type {
  AircraftC2Snapshot,
  AircraftC2Values,
  C2Output,
  C2OutputRemark,
  C2TrimOption,
} from "@/domain/aircraft-c2";

type EditingSection = "documents" | "balance" | "trim" | "lower" | null;

const valueFrom = (snapshot: AircraftC2Snapshot): AircraftC2Values => ({
  outputs: snapshot.outputs,
  documents: snapshot.documents,
  trimOptions: snapshot.trimOptions,
  outputRemarks: snapshot.outputRemarks,
  passengerTrimRemarks: snapshot.passengerTrimRemarks,
  captainsInformation: snapshot.captainsInformation,
  preLmcLoadMessage: snapshot.preLmcLoadMessage,
});

const outputFields: {
  selected: keyof C2Output;
  valid: keyof C2Output;
  documentCode: string;
}[] = [
  { selected: "selectedEdpPrelim", valid: "validEdpPrelim", documentCode: "LS EDP PRELIM" },
  { selected: "selectedAcarsPrelim", valid: "validAcarsPrelim", documentCode: "LS ACARS PRELIM" },
  { selected: "selectedEdpFinal", valid: "validEdpFinal", documentCode: "LS EDP FINAL" },
  { selected: "selectedAcarsFinal", valid: "validAcarsFinal", documentCode: "LS ACARS FINAL" },
];

const macCodes = new Set(["MACDLW", "MACZFW", "MACTOW", "MACLAW"]);

export function AircraftC2({ iata, initial, operatingRole }: { iata: string; initial: AircraftC2Snapshot; operatingRole:AircraftOperatingRole }) {
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState<AircraftC2Values>(valueFrom(initial));
  const [editingSection, setEditingSection] = useState<EditingSection>(null);
  const [expanded, setExpanded] = useState({ balance: true, trim: true });
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [pending, start,saveFeedback] = useSaveFeedback();

  const statuses = aircraftC2Statuses(saved, operatingRole);

  const visibleOutputFields = outputFields.filter((field) =>
    draft.documents.some((document) => document.code === field.documentCode && document.required),
  );
  const remark = (code: string) =>
    draft.outputRemarks.find((entry) => entry.code === code) ?? {
      code,
      remarks: "",
      useReferenceChord: false,
    };

  function beginEditing(section: Exclude<EditingSection, null>) {
    setDraft(valueFrom(saved));
    if (section === "balance" || section === "trim") {
      setExpanded((current) => ({ ...current, [section]: true }));
    }
    setEditingSection(section);
    setError("");
    setMessage("");
  }

  function cancelEditing() {
    setDraft(valueFrom(saved));
    setEditingSection(null);
    setError("");
  }

  function save(sectionName: string) {
    setError("");
    start(async () => {
      const result = await saveAircraftC2(
        iata,
        saved.typeCode,
        saved.subtype,
        saved.revision,
        draft,
      );
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setError("");setSaved(result.snapshot);saveFeedback.complete(()=>{
      setDraft(valueFrom(result.snapshot));
      setEditingSection(null);
      setMessage(`${sectionName} saved.`);});
    });
  }

  function sectionActions(section: Exclude<EditingSection, null>, label: string) {
    if (!saved.canEdit) return null;
    if (editingSection === section) {
      return (
        <div className="c2-section-actions">
          <SaveSubmit disabled={pending} onClick={() => save(label)}>Save</SaveSubmit>
          <SaveCancel className="secondary" disabled={pending} onClick={cancelEditing}>Cancel</SaveCancel>
        </div>
      );
    }
    if (editingSection !== null) return null;
    return <SaveButton className="secondary" onClick={() => beginEditing(section)}>EDIT</SaveButton>;
  }

  function collapseAction(section: "balance" | "trim", label: string) {
    const open = expanded[section];
    return <SaveButton
      type="button"
      className="secondary c2-collapse-toggle"
      aria-expanded={open}
      aria-controls={`c2-${section}-content`}
      aria-label={`${open ? "Collapse" : "Expand"} ${label}`}
      disabled={editingSection === section}
      onClick={() => setExpanded((current) => ({ ...current, [section]: !current[section] }))}
    >{open ? "COLLAPSE" : "EXPAND"}</SaveButton>;
  }

  function setOutput(index: number, key: keyof C2Output, value: boolean) {
    setDraft((current) => ({
      ...current,
      outputs: current.outputs.map((row, rowIndex) =>
        rowIndex === index ? { ...row, [key]: value } : row,
      ),
    }));
  }

  function setDocument(index: number, required: boolean) {
    setDraft((current) => {
      const code = current.documents[index].code;
      const field = outputFields.find((entry) => entry.documentCode === code);
      return {
        ...current,
        documents: current.documents.map((document, documentIndex) =>
          documentIndex === index ? { ...document, required } : document,
        ),
        outputs:
          !required && field
            ? current.outputs.map((row) => ({ ...row, [field.selected]: false }))
            : current.outputs,
      };
    });
  }

  function setTrim(index: number, patch: Partial<C2TrimOption>) {
    setDraft((current) => ({
      ...current,
      trimOptions: current.trimOptions.map((row, rowIndex) =>
        rowIndex === index ? { ...row, ...patch } : row,
      ),
    }));
  }

  function setRemark(code: string, patch: Partial<C2OutputRemark>) {
    setDraft((current) => {
      const exists = current.outputRemarks.some((entry) => entry.code === code);
      return {
        ...current,
        outputRemarks: exists
          ? current.outputRemarks.map((entry) =>
              entry.code === code ? { ...entry, ...patch } : entry,
            )
          : [...current.outputRemarks, { code, remarks: "", useReferenceChord: false, ...patch }],
      };
    });
  }

  return <SaveScope feedback={saveFeedback}>{(
    <section className="aircraft-c2">
      <SectionHeader
        id="aircraft-c2-heading"
        title="2. BALANCE AND SPECIAL INFORMATION – OUTPUT ON LOADSHEET"
        reference="(AHM565 Sheets C2, C3)"
      ><ConfigurationStatusBadge status={statuses.page} variant="large"/></SectionHeader>

      <div className="c2-section" id="automatic-documents">
        <div className="c2-section-heading">
          <h3>Loadsheet Documents</h3>
          <div className="c5-heading-actions">{sectionActions("documents", "Loadsheet Documents")}<ConfigurationStatusBadge status={statuses.documents}/></div>
        </div>
        <p>Master requirements are suggestions. Saved selections apply to the carrier.</p>
        <div className="c2-documents">
          {draft.documents.map((document, index) => (
            <label key={document.code}>
              <SaveInput
                type="checkbox"
                disabled={editingSection !== "documents"}
                checked={document.required}
                onChange={(event) => setDocument(index, event.target.checked)}
              />
              <span>
                <strong>{document.name}</strong>
                <small>{document.ahmReference}{document.suggested ? " · Suggested" : ""}</small>
              </span>
            </label>
          ))}
        </div>
      </div>

      <div className="c2-section">
        <div className="c2-section-heading">
          <h3>Balance Output</h3>
          <div className="c5-heading-actions">{collapseAction("balance", "BALANCE OUTPUT")}{sectionActions("balance", "Balance Output")}<ConfigurationStatusBadge status={statuses.balance}/></div>
        </div>
        {expanded.balance && <div id="c2-balance-content" className="c2-collapsible-content">{visibleOutputFields.length === 0 ? (
          <p className="muted">Select at least one Loadsheet Document to display its Balance Output column.</p>
        ) : (
          <div className="c2-table-wrap">
            <table className="c2-output-table">
              <thead>
                <tr>
                  <th>Item</th>
                  <th>Code</th>
                  {visibleOutputFields.map((field) => {
                    const document = draft.documents.find((entry) => entry.code === field.documentCode);
                    return <th key={String(field.selected)}>{document?.name}<small>{document?.ahmReference}</small></th>;
                  })}
                  <th>Remarks / RC</th>
                </tr>
              </thead>
              <tbody>
                {draft.outputs.map((row, index) => {
                  const note = remark(row.code);
                  return (
                    <tr key={row.code}>
                      <td>{row.name}</td>
                      <td>{row.code}</td>
                      {visibleOutputFields.map((field) => (
                        <td key={String(field.selected)}>
                          <SaveInput
                            type="checkbox"
                            aria-label={`${row.code} ${field.documentCode}`}
                            disabled={editingSection !== "balance" || !row[field.valid]}
                            checked={Boolean(row[field.selected])}
                            onChange={(event) => setOutput(index, field.selected, event.target.checked)}
                          />
                        </td>
                      ))}
                      <td>
                        <SaveInput
                          className="c2-inline-remark"
                          aria-label={`${row.code} Remarks`}
                          disabled={editingSection !== "balance"}
                          value={note.remarks}
                          maxLength={500}
                          onChange={(event) => setRemark(row.code, { remarks: event.target.value })}
                        />
                        {macCodes.has(row.code) && (
                          <label className="c2-rc">
                            <SaveInput
                              type="checkbox"
                              disabled={editingSection !== "balance"}
                              checked={note.useReferenceChord}
                              onChange={(event) => setRemark(row.code, { useReferenceChord: event.target.checked })}
                            />
                            Print RC
                          </label>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}</div>}
      </div>

      <div className="c2-section">
        <div className="c2-section-heading">
          <h3>Passenger Trim Output</h3>
          <div className="c5-heading-actions">{collapseAction("trim", "PASSENGER TRIM OUTPUT")}{operatingRole!=="FREIGHTER"&&sectionActions("trim", "Passenger Trim Output")}<ConfigurationStatusBadge status={statuses.trim}/></div>
        </div>
        {expanded.trim&&<div id="c2-trim-content" className="c2-collapsible-content">{operatingRole==="FREIGHTER"?<p className="muted">Passenger Trim Output is not required for a Freighter aircraft. Any previously saved data is retained.</p>:<><p>Select each Passenger Trim method used by this aircraft and give selected methods a unique priority.</p>
        <div className="c2-trim-grid">
          {draft.trimOptions.map((row, index) => (
            <div className="c2-trim-row" key={row.option}>
              <label>
                <SaveInput
                  type="checkbox"
                  disabled={editingSection !== "trim"}
                  checked={row.selected}
                  onChange={(event) => setTrim(index, {
                    selected: event.target.checked,
                    priority: event.target.checked ? (row.priority ?? 1) : null,
                  })}
                />
                {row.option}
                {row.suggested && <span className="badge">Suggested</span>}
              </label>
              <div className="details-field c2-priority-field">
                <label>Priority</label>
                <SaveSelect
                  className="c2-priority-select"
                  disabled={editingSection !== "trim" || !row.selected}
                  value={row.priority ?? ""}
                  onChange={(event) => setTrim(index, { priority: Number(event.target.value) })}
                >
                  <option value="">Select</option>
                  <option value="1">1</option>
                  <option value="2">2</option>
                  <option value="3">3</option>
                </SaveSelect>
              </div>
            </div>
          ))}
        </div>
        <div className="details-field c2-standalone-remarks">
          <label htmlFor="passenger-trim-remarks">Alternative Loadsheet Terminology or Remarks</label>
          <SaveTextarea
            id="passenger-trim-remarks"
            disabled={editingSection !== "trim"}
            value={draft.passengerTrimRemarks}
            maxLength={1000}
            onChange={(event) => setDraft((current) => ({
              ...current,
              passengerTrimRemarks: event.target.value,
            }))}
          />
          <small>This standalone remark applies to Passenger Trim Output as a whole and is not attached to an individual option.</small>
        </div></>}
        </div>}
      </div>

      <div className="c2-section">
        <h3>Lower Loadsheet Information</h3>
        <div className="details-field">
          <label htmlFor="captains-information">Captain’s Information / Notes</label>
          <SaveTextarea
            id="captains-information"
            disabled={editingSection !== "balance"}
            value={draft.captainsInformation}
            maxLength={2000}
            onChange={(event) => setDraft((current) => ({ ...current, captainsInformation: event.target.value }))}
          />
        </div>
        <div className="details-field">
          <label htmlFor="pre-lmc-message">Load Message Before LMC</label>
          <SaveTextarea
            id="pre-lmc-message"
            disabled={editingSection !== "balance"}
            value={draft.preLmcLoadMessage}
            maxLength={2000}
            onChange={(event) => setDraft((current) => ({ ...current, preLmcLoadMessage: event.target.value }))}
          />
        </div>
      </div>

      {error && <p className="field-error" role="alert">{error}</p>}
      {message && <p className="form-success" role="status">{message}</p>}
    </section>
  )}</SaveScope>;
}
