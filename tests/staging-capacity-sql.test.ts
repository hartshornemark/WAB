import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
const sql = (file: string) => readFileSync(file, "utf8");
const files = ["solver/staging/preflight.sql", "solver/reference/max_net_cargo_v2.sql", "solver/reference/frontier_net_cargo_v2.sql", "solver/staging/timed_offer.sql", "solver/staging/runtime_grants.sql"];

test("private reference installs transactionally, denies API roles, and calculates under the restricted role", async () => {
  const db = new PGlite();
  try {
    await db.exec("create role anon; create role authenticated; create role service_role; create table public.operational_sentinel(id int); insert into public.operational_sentinel values(1);");
    await db.exec("begin;" + files.map(sql).join("\n") + "commit;");
    const pinned = await db.query<{ pinned: boolean }>("select bool_and(proconfig @> array['search_path=pg_catalog']) pinned from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='capacity_reference'");
    assert.equal(pinned.rows[0].pinned, true);
    const roles = await db.query<{ name: string; usage: boolean; execute: boolean }>(`select name,has_schema_privilege(name,'capacity_reference','USAGE') usage, has_function_privilege(name,'capacity_reference.timed_offer(jsonb)','EXECUTE') execute from (values ('anon'),('authenticated'),('service_role'),('capacity_benchmark')) r(name)`);
    for (const role of roles.rows) { assert.equal(role.usage, role.name === "capacity_benchmark"); assert.equal(role.execute, role.name === "capacity_benchmark"); }
    await db.exec("set role capacity_benchmark; set default_transaction_read_only=on;");
    const problem = sql("solver/verification/a350-v2-seven-scenarios-2026-10-23/final/inputs/case-07-infeasible.json");
    const result = await db.query<{ measured: { result: { status: string }; calculationMilliseconds: number } }>("select capacity_reference.timed_offer($1::jsonb) measured", [problem]);
    assert.equal(result.rows[0].measured.result.status, "INFEASIBLE"); assert(result.rows[0].measured.calculationMilliseconds >= 0);
    await assert.rejects(db.query("select * from public.operational_sentinel"), /permission denied/);
    await db.exec("set default_transaction_read_only=off; reset role;");
    assert.equal((await db.query("select * from public.operational_sentinel")).rows.length, 1);
    await assert.rejects(db.exec(sql(files[0])), /already exists/);
  } finally { await db.close(); }
});

test("installation failure rolls back schema and role without changing operational objects", async () => {
  const db = new PGlite();
  try {
    await db.exec("create role anon; create role authenticated; create role service_role;");
    await assert.rejects(db.exec("begin;" + files.slice(0, 2).map(sql).join("\n") + ";select nonexistent_installation_check();commit;"));
    await db.exec("rollback;");
    const state = (await db.query<{ schema: boolean; role: boolean }>("select exists(select 1 from pg_namespace where nspname='capacity_reference') schema,exists(select 1 from pg_roles where rolname='capacity_benchmark') role")).rows[0];
    assert.equal(state.schema, false); assert.equal(state.role, false);
  } finally { await db.close(); }
});
