"use client";
import { useActionState } from "react";
import { changeLogo } from "@/app/logo-actions";
import { CarrierLogo } from "./carrier-logo";
export function LogoManager({ iata, logoUrl, canManage }: { iata: string; logoUrl?: string | null; canManage: boolean }) {
  const [state, action, pending] = useActionState(changeLogo.bind(null, iata), { error: "", message: "" });
  return <div className="logo-settings identity-logo"><h3>Company logo</h3>
    <div className="logo-settings-preview"><CarrierLogo iata={iata} logoUrl={logoUrl} /></div>
    {canManage ? <form action={action}>
      <label htmlFor="carrier-logo-file">Upload or replace logo</label>
      <p id="logo-help" className="muted">PNG, JPEG or WebP · up to 2 MB. A transparent background works best.</p>
      <input id="carrier-logo-file" type="file" name="logo" accept="image/png,image/jpeg,image/webp" aria-describedby="logo-help" disabled={pending} />
      <div className="logo-actions"><button name="operation" value="upload" disabled={pending}>{pending ? "Updating…" : "Save logo"}</button><button className="secondary" name="operation" value="remove" disabled={pending || logoUrl === null}>Remove logo</button></div>
      <div role="status" aria-live="polite"><p className="form-message">{state.error}</p><p>{state.message}</p></div>
    </form> : <p className="muted">Your Solution Administrator can update this logo.</p>}
  </div>;
}
