import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

test("the configuration dashboard uses the shared W/B logo asset",()=>{
  const dashboard=readFileSync("public/mockups/configuration-dashboard.html","utf8");
  assert.match(dashboard,/<img class="wb-logo" src="\/brand\/wb-logo\.png" alt="W\/B">/);
  assert.doesNotMatch(dashboard,/<span class="wb">W\/B<\/span>/);
});
