"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { saveOperationalFuelPlan, type AutoloadFuelCurve } from "@/app/load-control-actions";
import type { AircraftC4Values } from "@/domain/aircraft-c4";
import type { AircraftC5Values } from "@/domain/aircraft-c5";
import type { AircraftC5Applicability } from "@/domain/aircraft-c2-status";
import {
  balancePointWithinEnvelope,
  calculateFinalPayloadCapability,
  calculateOperationalFuelEffect,
  operationalEnvelopeConfigured,
  operationalEnvelopeSelectionForFuel,
  type FuelledBalancePoint,
  type OperationalFuelEffect,
  type OperationalFuelPlan,
} from "@/domain/operational-fuel";

const numberOrBlank = (value: number | null) => value === null ? "" : String(value);
const kilograms = (value: number) => `${Math.round(value).toLocaleString()} KG`;

export function OperationalFuelPlanning({ iata, flightId, loadPlanEdition, initial, zfw, acceptedCargoWeight, nonCargoTrafficWeight, curves, defaultTaxiFuel, maximumWeights, envelopeValues, aircraftFuelConfigurationCode, balanceApplicability, formula, onEffectChange, onEnvelopeSelectionChange, onStatusChange }: {
  iata: string;
  flightId: string;
  loadPlanEdition: number;
  initial: OperationalFuelPlan;
  zfw: FuelledBalancePoint;
  acceptedCargoWeight: number;
  nonCargoTrafficWeight: number;
  curves: AutoloadFuelCurve[];
  defaultTaxiFuel: number | null;
  maximumWeights: AircraftC5Values["maximumWeights"];
  envelopeValues: AircraftC5Values;
  aircraftFuelConfigurationCode: string | null;
  balanceApplicability: AircraftC5Applicability;
  formula: AircraftC4Values;
  onEffectChange?: (effect: OperationalFuelEffect | null) => void;
  onEnvelopeSelectionChange?: (codes: Partial<Record<"zfw"|"tow"|"law",string>>) => void;
  onStatusChange?: (status: OperationalFuelPlan["status"]) => void;
}) {
  const initialCurve = curves.find((curve) => curve.configurationCode === initial.configurationCode && curve.specificGravity === initial.specificGravity) ?? curves[0] ?? null;
  const initialSignature = [initialCurve?.id ?? "", numberOrBlank(initial.blockFuel), numberOrBlank(initial.taxiFuel ?? defaultTaxiFuel), numberOrBlank(initial.tripFuel)].join("|");
  const [version, setVersion] = useState(initial.version), [savedStatus,setSavedStatus]=useState(initial.status), [editingFinal,setEditingFinal]=useState(false), [curveId, setCurveId] = useState(initialCurve?.id ?? ""), [blockFuel, setBlockFuel] = useState(numberOrBlank(initial.blockFuel)), [taxiFuel, setTaxiFuel] = useState(numberOrBlank(initial.taxiFuel ?? defaultTaxiFuel)), [tripFuel, setTripFuel] = useState(numberOrBlank(initial.tripFuel)), [savedSignature,setSavedSignature]=useState(initialSignature), [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null),[pendingOperation,setPendingOperation]=useState<"PRELIMINARY"|"FINAL"|null>(null), [pending, start] = useTransition();
  const curve = curves.find((item) => item.id === curveId) ?? null;
  const currentSignature = [curveId, blockFuel, taxiFuel, tripFuel].join("|");
  const dirty = currentSignature !== savedSignature;
  const calculation = useMemo(() => {
    if (!curve || blockFuel === "" || taxiFuel === "" || tripFuel === "") return { effect: null, error: null };
    try { return { effect: calculateOperationalFuelEffect({ zfw, blockFuel: Number(blockFuel), taxiFuel: Number(taxiFuel), tripFuel: Number(tripFuel), curve: curve.points, formula }), error: null }; }
    catch (error) { return { effect: null, error: error instanceof Error ? error.message : "Check the fuel quantities." }; }
  }, [blockFuel, curve, formula, taxiFuel, tripFuel, zfw]);
  const effect = calculation.effect;
  useEffect(() => { onEffectChange?.(effect); }, [effect, onEffectChange]);
  const envelopeSelections=useMemo(()=>effect?{
    zfw:operationalEnvelopeSelectionForFuel(envelopeValues,"zfw",effect,aircraftFuelConfigurationCode),
    tow:operationalEnvelopeSelectionForFuel(envelopeValues,"tow",effect,aircraftFuelConfigurationCode),
    law:operationalEnvelopeConfigured(envelopeValues,"law")?operationalEnvelopeSelectionForFuel(envelopeValues,"law",effect,aircraftFuelConfigurationCode):null,
  }:null,[aircraftFuelConfigurationCode,effect,envelopeValues]);
  const checks = useMemo(() => {
    if (!effect || !curve || !envelopeSelections) return [];
    const towSelection = envelopeSelections.tow;
    const towBoundary = towSelection?.boundary ?? null;
    const hasLawEnvelope = operationalEnvelopeConfigured(envelopeValues, "law");
    const lawSelection = hasLawEnvelope ? envelopeSelections.law : towSelection;
    const lawBoundary = lawSelection?.boundary ?? null;
    return [
      { label: "RAMP", point: effect.ramp, maximum: maximumWeights.mrw, envelope: true, envelopeBasis: null, envelopeCode: null, balanceRequired: false },
      { label: "TOW", point: effect.takeOff, maximum: maximumWeights.tow, envelope: balanceApplicability.tow ? balancePointWithinEnvelope(effect.takeOff, towBoundary) : true, envelopeBasis: balanceApplicability.tow ? "TOW" : null, envelopeCode: towSelection?.code??null, balanceRequired: balanceApplicability.tow },
      { label: "LAW", point: effect.landing, maximum: maximumWeights.law, envelope: balanceApplicability.law ? balancePointWithinEnvelope(effect.landing, lawBoundary) : true, envelopeBasis: balanceApplicability.law ? (hasLawEnvelope ? "LAW" : "TOW") : null, envelopeCode: lawSelection?.code??null, balanceRequired: balanceApplicability.law },
    ];
  }, [balanceApplicability, curve, effect, envelopeSelections, envelopeValues, maximumWeights]);
  useEffect(()=>{onEnvelopeSelectionChange?.(Object.fromEntries(Object.entries(envelopeSelections??{}).filter(([,selection])=>selection?.code).map(([phase,selection])=>[phase,selection!.code!])) as Partial<Record<"zfw"|"tow"|"law",string>>)},[envelopeSelections,onEnvelopeSelectionChange]);
  const invalidChecks = checks.filter((check) => check.point.weight > check.maximum || (check.balanceRequired && check.envelope === false)), incompleteEnvelope = checks.some((check) => check.balanceRequired && check.envelope === null);
  const payload = useMemo(() => effect ? calculateFinalPayloadCapability({ dryOperatingWeight: zfw.weight - acceptedCargoWeight - nonCargoTrafficWeight, acceptedCargoWeight, nonCargoTrafficWeight, takeOffFuel: effect.takeOffFuel, landingFuel: effect.landingFuel, maximumWeights }) : null, [acceptedCargoWeight, effect, maximumWeights, nonCargoTrafficWeight, zfw.weight]);
  const save = (finalise:boolean) => {
    if (!curve || !effect) return;
    setNotice(null);
    setPendingOperation(finalise?"FINAL":"PRELIMINARY");
    start(async () => {
      try{
        const result = await saveOperationalFuelPlan(iata, flightId, version, { configurationCode: curve.configurationCode, specificGravity: curve.specificGravity, blockFuel: Number(blockFuel), taxiFuel: Number(taxiFuel), tripFuel: Number(tripFuel), finalise });
        if (!result.ok || !result.fuelPlan) { setNotice({ ok: false, text: result.message }); return; }
        setVersion(result.fuelPlan.version);setSavedStatus(result.fuelPlan.status);onStatusChange?.(result.fuelPlan.status);setEditingFinal(false);setSavedSignature(currentSignature);setNotice({ ok: true, text: result.message });
      }finally{setPendingOperation(null)}
    });
  };
  const fuelLocked=savedStatus==="FINAL"&&!editingFinal;
  const summaryStatus = dirty ? "UNSAVED CHANGES" : savedStatus === "FINAL" ? "FINAL" : savedStatus === "PRELIMINARY" || version > 0 ? "PRELIMINARY" : "AWAITING FUEL";
  return <details className="operational-fuel-planning operational-collapsible" open>
    <summary className="operational-collapsible-summary"><div><p className="eyebrow">FUEL AND BALANCE</p><h2>Flight Plan</h2><p>Calculate ramp, take-off and landing balance from the current load plan.</p></div><div className="operational-summary-facts"><span><small>LOAD PLAN</small><strong>EDITION {loadPlanEdition}</strong></span><span><small>TAKE-OFF FUEL</small><strong>{effect ? kilograms(effect.takeOffFuel) : "—"}</strong></span><span><small>LANDING FUEL</small><strong>{effect ? kilograms(effect.landingFuel) : "—"}</strong></span><span className={`summary-emphasis ${savedStatus==="FINAL"&&!dirty ? "ready" : "incomplete"}`}><small>FUEL STATUS</small><strong>{summaryStatus}</strong></span></div></summary>
    <div className="operational-collapsible-body">
      {!curves.length && <p className="load-control-notice error">No applicable C8 Standard Fuel curve is configured for this aircraft.</p>}
      <div className="operational-fuel-inputs"><label><span>Fuel distribution</span><select value={curveId} onChange={(event) => setCurveId(event.target.value)} disabled={!curves.length||fuelLocked}>{curves.map((item) => <option value={item.id} key={item.id}>{item.label}</option>)}</select></label><label><span>Block fuel (KG)</span><input type="number" min="0" step="1" value={blockFuel} disabled={fuelLocked} onChange={(event) => setBlockFuel(event.target.value)} /></label><label><span>Taxi fuel (KG)</span><input type="number" min="0" step="1" value={taxiFuel} disabled={fuelLocked} onChange={(event) => setTaxiFuel(event.target.value)} /></label><label><span>Trip fuel (KG)</span><input type="number" min="0" step="1" value={tripFuel} disabled={fuelLocked} onChange={(event) => setTripFuel(event.target.value)} /></label></div>
      {effect && <div className="operational-fuel-derived"><span><span className="operational-weight-heading"><small>ZFW</small><b>ESTIMATED</b></span><strong>{kilograms(zfw.weight)}</strong><em>LIZFW {zfw.indexValue.toFixed(2)} · MACZFW {zfw.macValue.toFixed(1)}%{envelopeSelections?.zfw?.code?` · ENVELOPE ${envelopeSelections.zfw.code}`:""}</em></span>{checks.map((check) => { const valid = check.point.weight <= check.maximum && (!check.balanceRequired || check.envelope !== false),indexCode=check.label==="TOW"?"LITOW":check.label==="LAW"?"LILAW":null,macCode=check.label==="TOW"?"MACTOW":check.label==="LAW"?"MACLAW":null,envelopeLabel=check.envelopeCode?` · ENVELOPE ${check.envelopeCode}`:check.label==="LAW"&&check.envelopeBasis==="TOW"?" · TOW ENVELOPE":""; return <span className={valid ? "valid" : "invalid"} key={check.label}><span className="operational-weight-heading"><small>{check.label}</small><b>ESTIMATED</b></span><strong>{kilograms(check.point.weight)}</strong><em>{check.balanceRequired&&indexCode&&macCode?`${indexCode} ${check.point.indexValue.toFixed(2)} · ${macCode} ${check.point.macValue.toFixed(1)}%${envelopeLabel}`:"WEIGHT CHECK ONLY"}</em></span>; })}</div>}
      {payload&&<div className="operational-payload-comparison"><span><small>MAX ALLOWABLE TRAFFIC LOAD</small><strong>{kilograms(payload.maximumAllowableTrafficLoad)}</strong><em>MATL · {payload.limitingFactor} LIMITING</em></span><span><small>ALLOWED TRAFFIC LOAD</small><strong>{kilograms(payload.allowedTrafficLoad)}</strong><em>ATL for this flight</em></span><span><small>TOTAL TRAFFIC LOAD</small><strong>{kilograms(payload.actualTrafficLoad)}</strong></span><span className={payload.operationalUnderload<=0?"invalid":payload.operationalUnderload<=payload.allowedTrafficLoad*.05?"warning":"valid"}><span className="operational-weight-heading"><small>UNDERLOAD</small><b>PREDICTED</b></span><strong>{kilograms(payload.operationalUnderload)}</strong><em>{payload.operationalUnderload<=0?"ACTUAL LOAD AT OR ABOVE ATL":"ATL − ACTUAL TRAFFIC LOAD"}</em></span></div>}
      {payload&&<p className="operational-matl-basis">MATL is the lowest of: MTOW − Operating Weight; MLAW + Trip Fuel − Operating Weight; or MZFW + Take-off Fuel − Operating Weight. Operating Weight = DOW + Take-off Fuel.</p>}
      {calculation.error && <p className="load-control-notice error">{calculation.error}</p>}
      {invalidChecks.map((check) => <p className="load-control-notice error" key={`${check.label}-error`}>{check.label} is outside its configured {check.point.weight > check.maximum ? "maximum structural weight" : `${check.envelopeBasis} balance envelope`}. The fuel plan may be retained for correction, but loadsheet release must be blocked.</p>)}
      {incompleteEnvelope && <p className="load-control-notice warning">A matching conditional balance envelope could not be identified. Review the configured fuel condition before loadsheet release.</p>}
      {payload&&payload.operationalUnderload<0&&<p className="load-control-notice error">The Actual Traffic Load exceeds this flight’s Allowed Traffic Load by {kilograms(Math.abs(payload.operationalUnderload))}. Fuel may be finalised, but loadsheet production must remain blocked until the load or fuel condition is resolved.</p>}
      {notice && <p className={`load-control-notice ${notice.ok ? "success" : "error"}`} role="status">{notice.text}</p>}
      <div className="operational-fuel-actions">{fuelLocked?<button type="button" className="secondary" disabled={pending} onClick={()=>{setEditingFinal(true);setNotice(null)}}>EDIT FUEL DATA</button>:<><button type="button" className="secondary" disabled={pending || !effect || !curve} onClick={()=>save(false)}>{pending&&pendingOperation==="PRELIMINARY"?"SAVING PRELIMINARY…":"SAVE PRELIMINARY"}</button><button type="button" disabled={pending || !effect || !curve} onClick={()=>save(true)}>{pending&&pendingOperation==="FINAL"?"FINALISING FUEL DATA…":"FINALISE FUEL DATA"}</button></>}<span>{fuelLocked?"Final fuel data is locked. Select Edit Fuel Data to reopen these controls.":"Taxi fuel defaults from C8 for the departure station and remains editable for this flight. A revised load plan automatically recalculates the balance effects without changing fuel status. Any structural or envelope exception will block loadsheet production, not fuel finalisation."}</span></div>
    </div>
  </details>;
}
