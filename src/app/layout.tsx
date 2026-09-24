import type { Metadata } from "next";
import { NumericInputGuard } from "@/components/numeric-input-guard";
import "./globals.css";
export const metadata: Metadata = { title: "Carrier Configuration", description: "Your airline configuration workspace", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><NumericInputGuard />{children}</body></html>;
}
