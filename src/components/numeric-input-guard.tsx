"use client";

import { useEffect } from "react";

function isNumericInput(target: EventTarget | null): target is HTMLInputElement {
  return target instanceof HTMLInputElement && target.type === "number";
}

export function NumericInputGuard() {
  useEffect(() => {
    function preventArrowAdjustment(event: KeyboardEvent) {
      if (
        isNumericInput(event.target) &&
        (event.key === "ArrowUp" || event.key === "ArrowDown")
      ) {
        event.preventDefault();
      }
    }

    function preventWheelAdjustment(event: WheelEvent) {
      if (isNumericInput(event.target) && document.activeElement === event.target) {
        event.target.blur();
      }
    }

    document.addEventListener("keydown", preventArrowAdjustment);
    document.addEventListener("wheel", preventWheelAdjustment, { passive: true });

    return () => {
      document.removeEventListener("keydown", preventArrowAdjustment);
      document.removeEventListener("wheel", preventWheelAdjustment);
    };
  }, []);

  return null;
}
