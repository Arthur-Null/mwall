import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [root, packageRoot] = process.argv.slice(2);
assert(root && packageRoot, "Expected fixture root and installed pi package directory");
process.env.PI_CODING_AGENT_DIR = path.join(root, "first/pi");
const themePath = path.join(packageRoot, "dist/modes/interactive/theme");
const schema = JSON.parse(fs.readFileSync(path.join(themePath, "theme-schema.json"), "utf8"));
const mod = await import(pathToFileURL(path.join(themePath, "theme.js")).href);
const names = ["mwall", "mwall-dark", "mwall-light"];
const originals = new Map();
for (const version of ["first", "second"]) {
  for (const name of names) {
    const file = path.join(root, version, "pi/themes", name + ".json");
    const raw = fs.readFileSync(file, "utf8");
    const doc = JSON.parse(raw);
    assert.equal(doc.name, name);
    for (const token of schema.properties.colors.required) {
      assert.match(doc.colors[token], /^#[0-9A-F]{6}$/, "Missing or invalid pi color: " + token);
    }
    mod.loadThemeFromPath(file); // Parse using the installed consumer, not only JSON.parse.
    if (version === "first") originals.set(name, raw);
  }
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function replace(file, data) {
  fs.writeFileSync(file + ".new", data);
  fs.renameSync(file + ".new", file);
}
async function waitFor(predicate) {
  const start = Date.now();
  while (!predicate() && Date.now() - start < 4000) await delay(20);
  assert(predicate(), "pi did not reload an atomically replaced generated theme");
}
let changes = 0;
mod.onThemeChange(() => changes++);
try {
  for (const name of names) {
    assert(mod.setTheme(name, true).success);
    await delay(150);
    const file = path.join(root, "first/pi/themes", name + ".json");
    const before = mod.theme.fg("accent", "sample");
    replace(file, fs.readFileSync(path.join(root, "second/pi/themes", name + ".json")));
    await waitFor(() => mod.theme.fg("accent", "sample") !== before);
    const after = mod.theme.fg("accent", "sample");
    const count = changes;
    replace(file, "{invalid");
    await delay(250);
    assert.equal(mod.theme.fg("accent", "sample"), after, "invalid data replaced the valid theme");
    assert.equal(changes, count, "invalid data triggered a UI change");
    replace(file, originals.get(name));
    await waitFor(() => mod.theme.fg("accent", "sample") === before);
  }
  assert.equal(mod.resolveThemeSetting("mwall-light/mwall-dark", "light"), "mwall-light");
  assert.equal(mod.resolveThemeSetting("mwall-light/mwall-dark", "dark"), "mwall-dark");
  console.log("Pi generated theme reload PASS: schema, three variants, atomic replacements, recovery, light/dark pair");
} finally {
  mod.stopThemeWatcher();
}
