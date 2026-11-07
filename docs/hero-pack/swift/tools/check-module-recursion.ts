// Finds static-initialisation recursion in the generated scene files.
//
// ts2swift bundles a module's top-level values into one `private static let _moduleN = { ... }()`
// tuple, with `static var X { _moduleN.X }` accessors. If anything that runs while that tuple is
// being built (i.e. outside the deferred scene draw closures) calls a static func that reads one of
// those accessors, Swift re-enters the lazy initialiser and traps (dispatch_once recursion).
//
// Usage: bun docs/hero-pack/swift/tools/check-module-recursion.ts <file.swift> ...
import * as fs from 'node:fs';

let problems = 0;
for (const file of process.argv.slice(2)) {
  const src = fs.readFileSync(file, 'utf8');
  const lines = src.split('\n');
  const startIdx = lines.findIndex((l) => /private static let _module\d+:/.test(l));
  if (startIdx < 0) continue;
  // end of closure: line matching /^\s*\}\(\)$/ after start
  let endIdx = startIdx + 1;
  while (endIdx < lines.length && !/^\s*\}\(\)\s*$/.test(lines[endIdx])) endIdx++;
  const accessors = new Set<string>();
  for (const l of lines) {
    const m = l.match(/static var (\w+): .*\{ _module\d+\.\w+ \}/);
    if (m) accessors.add(m[1]);
  }
  // static funcs: name -> body
  const funcs = new Map<string, string>();
  for (let i = 0; i < lines.length; i++) {
    if (i >= startIdx && i <= endIdx) continue;
    const m = lines[i].match(/^\s*static func (\w+)\(/);
    if (!m) continue;
    let depth = 0, body = '', j = i, started = false;
    for (; j < lines.length; j++) {
      for (const ch of lines[j]) {
        if (ch === '{') { depth++; started = true; }
        else if (ch === '}') depth--;
      }
      body += lines[j] + '\n';
      if (started && depth <= 0) break;
    }
    funcs.set(m[1], (funcs.get(m[1]) ?? '') + body);
  }
  const words = (s: string) => new Set(s.match(/\b[A-Za-z_]\w*\b/g) ?? []);
  // funcs that (transitively) read an accessor
  const tainted = new Set<string>();
  let changed = true;
  while (changed) {
    changed = false;
    for (const [name, body] of funcs) {
      if (tainted.has(name)) continue;
      const w = words(body);
      if ([...accessors].some((a) => w.has(a)) || [...tainted].some((t) => w.has(t) && body.includes(t + '('))) {
        tainted.add(name);
        changed = true;
      }
    }
  }
  // eager code in the module closure: strip scene draw closures (`) { (g: inout MatrixBoard` ... matching brace)
  const body = lines.slice(startIdx + 1, endIdx).join('\n');
  let eager = '';
  let i = 0;
  while (i < body.length) {
    const k = body.indexOf('{ (g: inout MatrixBoard', i);
    if (k < 0) { eager += body.slice(i); break; }
    eager += body.slice(i, k);
    let depth = 0, j = k;
    for (; j < body.length; j++) {
      if (body[j] === '{') depth++;
      else if (body[j] === '}') { depth--; if (depth === 0) break; }
    }
    i = j + 1;
  }
  for (const t of tainted) {
    const re = new RegExp(`\\b${t}\\(`, 'g');
    const hits = eager.match(re);
    if (hits) {
      problems++;
      console.log(`${file}: eager call to ${t}() inside the module initialiser reads module values`);
    }
  }
  for (const a of accessors) {
    // direct reads are fine (local lets shadow them) unless used before local declaration; skip
  }
}
console.log(problems ? `${problems} problem(s)` : 'clean');
process.exit(problems ? 1 : 0);
