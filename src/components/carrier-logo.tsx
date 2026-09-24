"use client";

import Image from "next/image";
import { useState } from "react";

const logos: Record<string, string> = { ZZ: "/carriers/zz.png" };

export function CarrierLogo({ iata, logoUrl }: { iata: string; logoUrl?: string | null }) {
  const [failedSource, setFailedSource] = useState<string | null>(null);
  const source = logoUrl === undefined ? logos[iata] : logoUrl;
  if (!source || failedSource === source) {
    return <span className="carrier-code" aria-hidden="true">{iata}</span>;
  }
  return (
    <span className="carrier-logo">
      <Image
        src={source}
        alt=""
        width={100}
        height={72}
        unoptimized
        onError={() => setFailedSource(source)}
      />
    </span>
  );
}
