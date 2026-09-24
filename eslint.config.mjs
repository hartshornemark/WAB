import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";
import architecture from "./scripts/architecture-rule.mjs";
export default defineConfig([
  ...nextVitals, ...nextTs,
  { files: ["src/**/*.{ts,tsx}"], plugins: { architecture }, rules: { "architecture/boundaries": "error" } },
  globalIgnores([".next/**", "next-env.d.ts", "playwright-report/**", "test-results/**"]),
]);
