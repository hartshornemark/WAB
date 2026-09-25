"use client";
import { useState } from "react";
import { changeLogo } from "@/app/logo-actions";
import { CarrierLogo } from "./carrier-logo";
import {useSaveFeedback,SaveScope,SaveInput,SaveButton,SaveSubmit} from "./save-feedback";
export function LogoManager({ iata, logoUrl, canManage }: { iata: string; logoUrl?: string | null; canManage: boolean }) {
  const [state,setState]=useState({error:"",message:""});
  const [pending,start,saveFeedback]=useSaveFeedback();
  return <SaveScope feedback={saveFeedback}><div className="logo-settings identity-logo"><h3>Company logo</h3>
    <div className="logo-settings-preview"><CarrierLogo iata={iata} logoUrl={logoUrl} /></div>
    {canManage ? <form onSubmit={event=>{
      event.preventDefault();
      const form=event.currentTarget;
      const data=new FormData(form,(event.nativeEvent as SubmitEvent).submitter);
      setState({error:"",message:""});
      start(async()=>{
        const result=await changeLogo(iata,state,data);
        if(result.error){setState(result);return;}
        saveFeedback.complete(()=>{setState(result);form.reset();});
      });
    }}>
      <label htmlFor="carrier-logo-file">Upload or replace logo</label>
      <p id="logo-help" className="muted">PNG, JPEG or WebP · up to 2 MB. A transparent background works best.</p>
      <SaveInput id="carrier-logo-file" type="file" name="logo" accept="image/png,image/jpeg,image/webp" aria-describedby="logo-help" disabled={pending} />
      <div className="logo-actions"><SaveSubmit name="operation" value="upload" disabled={pending}>SAVE</SaveSubmit><SaveButton className="secondary" name="operation" value="remove" disabled={pending || logoUrl === null}>Remove logo</SaveButton></div>
      <div role="status" aria-live="polite"><p className="form-message">{state.error}</p><p>{state.message}</p></div>
    </form> : <p className="muted">Your Solution Administrator can update this logo.</p>}
  </div></SaveScope>;
}
