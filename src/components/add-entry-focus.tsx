"use client";

import { useEffect } from "react";

const entrySelector = [
  "input:not([type='hidden']):not([type='checkbox']):not([type='radio']):not([disabled]):not([readonly])",
  "select:not([disabled])",
  "textarea:not([disabled]):not([readonly])",
  "[contenteditable='true']",
].join(",");

function empty(control: HTMLElement) {
  if (control instanceof HTMLInputElement || control instanceof HTMLTextAreaElement || control instanceof HTMLSelectElement) {
    return control.value.trim() === "";
  }
  return (control.textContent ?? "").trim() === "";
}

function visible(control: HTMLElement) {
  return control.getClientRects().length > 0 && control.getAttribute("aria-hidden") !== "true";
}

/** Move directly from ADD actions, or single-field EDIT actions, to the new entry field. */
export function AddEntryFocus() {
  useEffect(() => {
    function prepareFocus(event: MouseEvent) {
      const target = event.target;
      if (!(target instanceof Element)) return;
      const button = target.closest("button");
      const label = (button?.textContent ?? "").trim();
      const isAdd = /^ADD\b/i.test(label);
      const isEdit = /^EDIT\b/i.test(label);
      if (!button || button.disabled || (!isAdd && !isEdit)) return;

      const existing = new Set(document.querySelectorAll(entrySelector));
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const added = Array.from(document.querySelectorAll<HTMLElement>(entrySelector))
          .filter(control => !existing.has(control) && visible(control));
        if (isEdit && added.length !== 1) return;
        const control = added.find(candidate => candidate.matches("[required]") && empty(candidate))
          ?? added.find(empty)
          ?? added.find(candidate => candidate.matches("[required]"))
          ?? added[0];
        if (!control) return;
        control.focus({ preventScroll: true });
        control.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" });
      }));
    }

    document.addEventListener("click", prepareFocus, true);
    return () => document.removeEventListener("click", prepareFocus, true);
  }, []);

  return null;
}
