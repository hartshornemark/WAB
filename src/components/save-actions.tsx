"use client";

import { useEffect, useRef, type ReactNode } from "react";

export type SaveState = "editing" | "saving" | "saved";

/** The caller may enter `saved` only after its save request succeeds. */
export function SaveActions({state,onCancel,onExit,saveLabel="SAVE",disabled=false,children}:{
  state:SaveState;
  onCancel:()=>void;
  onExit:()=>void;
  saveLabel?:string;
  disabled?:boolean;
  children?:ReactNode;
}){
  const exit=useRef<HTMLButtonElement>(null);
  useEffect(()=>{if(state==="saved")exit.current?.focus();},[state]);
  const busy=state==="saving";
  return <div className="save-actions" aria-busy={busy}>
    <button type={state==="editing"?"submit":"button"} className={`save-action save-action--${state}`} disabled={disabled||state!=="editing"}>
      {busy&&<span className="save-spinner" aria-hidden="true"/>}
      {busy?"SAVING…":state==="saved"?"SAVED":saveLabel}
    </button>
    {state==="saved"?<button ref={exit} type="button" className="secondary save-exit" onClick={onExit}>EXIT</button>:<button type="button" className="secondary save-exit" disabled={disabled||busy} onClick={onCancel}>CANCEL</button>}
    {state==="editing"&&children}
    <span className="sr-only" role="status" aria-live="polite" aria-atomic="true">{busy?"Saving changes.":state==="saved"?"Changes saved successfully.":""}</span>
  </div>;
}
