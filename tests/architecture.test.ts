import test from "node:test";
import assert from "node:assert/strict";
import { ESLint } from "eslint";
const eslint = new ESLint();
for (const [name, code, file] of [
  ["UI SDK import", 'import { createClient } from "@supabase/supabase-js";', "src/app/example.tsx"],
  ["relative adapter import", 'import { createRequestClient } from "../infrastructure/supabase/server";', "src/components/example.tsx"],
  ["domain infrastructure import", 'export * from "@/infrastructure/supabase/server";', "src/domain/example.ts"],
  ["dynamic SDK import", 'const client = import("@supabase/ssr");', "src/app/example.tsx"],
  ["application framework import", 'import { cookies } from "next/headers";', "src/application/example.ts"],
]) test(`architecture rejects ${name}`, async () => {
  const [result] = await eslint.lintText(code, { filePath: file });
  assert.ok(result.messages.some(message => message.ruleId === "architecture/boundaries"));
});
