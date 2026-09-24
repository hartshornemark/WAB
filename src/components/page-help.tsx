"use client";

import { useRef,type ReactNode } from "react";

export function PageHelp({title,children}:{title:string;children:ReactNode}){
  const dialog=useRef<HTMLDialogElement>(null);
  const close=()=>dialog.current?.close();
  return <>
    <button type="button" className="secondary page-help-button" onClick={()=>dialog.current?.showModal()} aria-haspopup="dialog">HELP</button>
    <dialog ref={dialog} className="page-help-dialog" aria-labelledby="page-help-title" onClick={event=>{if(event.target===event.currentTarget)close();}}>
      <div className="page-help-card">
        <header><div><span>PAGE HELP</span><h2 id="page-help-title">{title}</h2></div><button type="button" className="secondary" onClick={close}>CLOSE</button></header>
        <div className="page-help-content">{children}</div>
      </div>
    </dialog>
  </>;
}
