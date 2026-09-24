"use client";
import Link from"next/link";
import{useActionState}from"react";
import{createCarrierAction,type NewCarrierFormState}from"@/app/carriers/new/actions";
const initialState:NewCarrierFormState={error:"",fields:{iata:"",name:"",icao:""},fieldErrors:{}};
export function NewCarrierForm(){const[state,action,pending]=useActionState(createCarrierAction,initialState);return <form className="new-carrier-form" action={action}>
  <div className="new-carrier-identity-grid">
    <div className="details-field"><label htmlFor="new-carrier-iata">Carrier IATA Code</label><input id="new-carrier-iata" name="iata" defaultValue={state.fields.iata} maxLength={2} autoCapitalize="characters" required aria-invalid={!!state.fieldErrors.iata}/>{state.fieldErrors.iata&&<p className="field-error">{state.fieldErrors.iata}</p>}<small>Two letters or numbers</small></div>
    <div className="details-field carrier-name-field"><label htmlFor="new-carrier-name">Carrier Name</label><input id="new-carrier-name" name="name" defaultValue={state.fields.name} maxLength={64} required aria-invalid={!!state.fieldErrors.name}/>{state.fieldErrors.name&&<p className="field-error">{state.fieldErrors.name}</p>}</div>
    <div className="details-field"><label htmlFor="new-carrier-icao">Carrier ICAO Code</label><input id="new-carrier-icao" name="icao" defaultValue={state.fields.icao} maxLength={3} autoCapitalize="characters" required aria-invalid={!!state.fieldErrors.icao}/>{state.fieldErrors.icao&&<p className="field-error">{state.fieldErrors.icao}</p>}<small>Three letters</small></div>
  </div>
  <div className="new-carrier-logo"><label htmlFor="new-carrier-logo">Carrier Logo <span>Optional</span></label><p id="new-carrier-logo-help" className="muted">PNG, JPEG or WebP · up to 2 MB. A transparent background works best.</p><input id="new-carrier-logo" name="logo" type="file" accept="image/png,image/jpeg,image/webp" aria-describedby="new-carrier-logo-help"/></div>
  <div aria-live="polite">{state.error&&<p className="field-error">{state.error}</p>}</div>
  <div className="new-carrier-actions"><Link className="secondary button-link" href="/carriers">CANCEL</Link><button disabled={pending}>{pending?"CREATING…":"CREATE CARRIER"}</button></div>
</form>}
