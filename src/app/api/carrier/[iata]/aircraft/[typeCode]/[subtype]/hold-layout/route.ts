import { NextResponse } from "next/server";
import { loadHoldLayout } from "@/app/hold-layout-actions";

export const dynamic = "force-dynamic";

export async function GET(_request: Request, { params }: { params: Promise<{ iata: string; typeCode: string; subtype: string }> }) {
  const { iata, typeCode, subtype } = await params;
  const result = await loadHoldLayout(iata, typeCode, subtype);
  return NextResponse.json(result, { status: result.ok ? 200 : 400 });
}
