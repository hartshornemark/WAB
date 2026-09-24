import type { ReactNode } from "react";

/** Shared AHM sheet header, based on the Crew Weights design. */
export function SectionHeader({ id, title, reference, children }: {
  id: string; title: string; reference: string; children?: ReactNode;
}) {
  return <div className="details-heading">
    <div><h2 id={id}>{title}</h2><p className="sheet-reference">{reference}</p></div>
    {children}
  </div>;
}
