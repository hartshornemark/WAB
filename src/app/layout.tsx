import type { Metadata } from "next";
import { NumericInputGuard } from "@/components/numeric-input-guard";
import "./globals.css";
export const metadata: Metadata = { title: "W/B Operations Workspace", description: "Your airline operations workspace", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><NumericInputGuard />{children}</body></html>;
}
