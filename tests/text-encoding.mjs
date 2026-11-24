#!/usr/bin/env node
// Guard every text file against accidental Latin-1 / Windows-1252 double-encoding (mojibake)
// or stray Unicode replacement characters.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const TEXT = new Set(['.md', '.json', '.js', '.mjs', '.yml', '.yaml', '.txt', '.sh', '.svg']);
const SKIP = new Set(['.git', 'node_modules']);
const MOJIBAKE = /\u00C3[\u0080-\u00BF]|\u00C2[\u0080-\u00BF]|\u00E2\u20AC|\uFFFD/;
const bad = [];

function walk(dir) {
  for (const name of readdirSync(dir)) {
    if (SKIP.has(name)) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) { walk(p); continue; }
    if (!TEXT.has(extname(name).toLowerCase()) || st.size > 4e6) continue;
    const lines = readFileSync(p, 'utf8').split('\n');
    lines.forEach((line, idx) => {
      const m = line.match(MOJIBAKE);
      if (m) {
        const snippet = line.slice(Math.max(0, m.index - 20), m.index + 20).trim();
        bad.push(`${relative(ROOT, p).replaceAll('\\', '/')}:${idx + 1}: "${snippet}"`);
      }
    });
  }
}

walk(ROOT);

if (bad.length) {
  console.error(`not ok - ${bad.length} line(s) look corrupted or double-encoded:`);
  for (const b of bad.slice(0, 20)) console.error('  ' + b);
  process.exit(1);
}

console.log('ok - every text file is clean UTF-8');
