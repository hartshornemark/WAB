import type { NextRequest } from "next/server";
import { refreshSession } from "@/infrastructure/supabase/proxy";
export async function proxy(request: NextRequest) { return refreshSession(request); }
export const config = { matcher: ["/", "/login", "/carriers/:path*", "/carrier/:path*"] };
