#!/usr/bin/env node
// Verify that every local link, image src, and <picture> srcset in Markdown files resolves on disk.
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname, extname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SKIP = new Set(['.git', 'node_modules']);
const mdFiles = [];

function walk(dir) {
  for (const name of readdirSync(dir)) {
    if (SKIP.has(name)) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) { walk(p); continue; }
    if (extname(name).toLowerCase() === '.md') mdFiles.push(p);
  }
}

walk(ROOT);

const broken = [];
const isExternal = (target) =>
  /^(https?:|mailto:|tel:|data:|#)/i.test(target) || target === '';

for (const file of mdFiles) {
  const dir = dirname(file);
  const relFile = relative(ROOT, file).replaceAll('\\', '/');
  // Strip fenced code blocks and inline code spans before scanning links
  const text = readFileSync(file, 'utf8')
    .replace(/```[\s\S]*?```/g, '')
    .replace(/`[^`\n]+`/g, '');

  const candidates = [];
  for (const m of text.matchAll(/!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) {
    candidates.push(m[1]);
  }
  for (const m of text.matchAll(/\b(?:src|srcset|href)="([^"]+)"/g)) {
    candidates.push(m[1]);
  }

  for (const raw of candidates) {
    const clean = raw.split('#')[0].split('?')[0].trim();
    if (isExternal(raw) || !clean) continue;
    const targetPath = resolve(dir, clean);
    if (!existsSync(targetPath)) {
      broken.push(`${relFile} -> ${raw}`);
    }
  }
}

if (broken.length) {
  console.error(`not ok - ${broken.length} broken local link(s)/asset(s):`);
  for (const b of broken) console.error('  ' + b);
  process.exit(1);
}

console.log(`ok - all local links and assets verified across ${mdFiles.length} Markdown files`);
