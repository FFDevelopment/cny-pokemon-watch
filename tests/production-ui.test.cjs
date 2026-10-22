const assert = require("node:assert/strict");
const fs = require("node:fs");
const html = fs.readFileSync("production/index.html", "utf8");
const js = fs.readFileSync("production/app.js", "utf8");
const config = fs.readFileSync("production/config.js", "utf8");
const ids = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(x=>x[1]));
const selectors = [...js.matchAll(/\$\("([^"]+)"\)/g)].map(x=>x[1]);
for (const id of selectors) assert.ok(ids.has(id), "Missing HTML element #"+id);
for (const id of ["authPanel","adminTab","memberResults","storeResults","watchResults","alertResults","resendEmail","resetEmail","passwordRecoveryPanel","passwordRecoveryForm"]) {
  assert.ok(ids.has(id), "Required production control missing: #"+id);
}
assert.match(js, /onConflict:"product_slug,store_id,product_url"/, "Offer updates must use conflict-aware upserts");
assert.match(js, /previously reported in stock/, "Stale stock warning missing");
assert.match(config, /SUPABASE_PUBLISHABLE_KEY/, "Missing public Supabase config key");
assert.doesNotMatch(config, /(sb_secret_|service_role)/i, "Secret configuration must not be committed");
console.log("Production HTML element contract: "+selectors.length+" selectors valid");
console.log("Production UI static assertions passed.");
