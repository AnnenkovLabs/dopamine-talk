#!/usr/bin/env node
// Validate every SKILL.md frontmatter (EN in skills/ and RU in skills-ru/) and every plugin manifest.
// Claude Code, Codex, and skills.sh drop skills silently when frontmatter YAML is malformed
// or descriptions exceed 1024 characters.
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const errors = [];
const fail = (where, msg) => errors.push(`${where}: ${msg}`);

let YAML = null;
try {
  YAML = await import('yaml');
} catch {
  // Zero-dependency fallback when running locally without installing yaml
}

function parseFrontmatter(text, where) {
  if (YAML) {
    const doc = YAML.parseDocument(text, { strict: true, uniqueKeys: true, prettyErrors: true });
    for (const e of [...doc.errors, ...doc.warnings]) {
      fail(where, `YAML ${e.name}: ${e.message.split('\n')[0]}`);
    }
    return doc.errors.length ? null : doc.toJS();
  }

  const result = {};
  const lines = text.split(/\r?\n/);
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim() || line.trim().startsWith('#')) { i++; continue; }
    const m = line.match(/^([a-zA-Z0-9_-]+):\s*(.*)$/);
    if (!m) { fail(where, `unparseable frontmatter line ${i + 1}: ${line}`); return null; }
    const [, key, rawVal] = m;
    if (key in result) fail(where, `duplicate frontmatter key "${key}"`);
    if (/^[>|][-+]?$/.test(rawVal)) {
      const block = [];
      i++;
      while (i < lines.length && (/^\s+/.test(lines[i]) || lines[i] === '')) {
        block.push(lines[i].trim());
        i++;
      }
      result[key] = block.join(' ').trim();
    } else {
      if (!/^["']/.test(rawVal) && /:\s/.test(rawVal)) {
        fail(where, `unquoted ": " in scalar value for "${key}" breaks strict YAML parsers`);
      }
      result[key] = rawVal.replace(/^["']|["']$/g, '').trim();
      i++;
    }
  }
  return result;
}

const editions = [
  { rootRel: 'skills', label: 'EN' },
  { rootRel: 'skills-ru', label: 'RU' },
];

let totalSkills = 0;

for (const { rootRel, label } of editions) {
  const dirRoot = join(ROOT, rootRel);
  if (!existsSync(dirRoot)) {
    fail(rootRel, `missing ${label} skills directory`);
    continue;
  }

  const names = new Map();
  for (const dir of readdirSync(dirRoot).sort()) {
    const fullDir = join(dirRoot, dir);
    if (!statSync(fullDir).isDirectory()) continue;
    const file = join(fullDir, 'SKILL.md');
    if (!existsSync(file)) {
      fail(`${rootRel}/${dir}`, 'skill directory is missing SKILL.md');
      continue;
    }
    const where = `${rootRel}/${dir}/SKILL.md`;
    const src = readFileSync(file, 'utf8');
    const m = src.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n/);
    if (!m) {
      fail(where, 'missing YAML frontmatter block (--- ... ---) at top of file');
      continue;
    }
    const fm = parseFrontmatter(m[1], where);
    if (!fm) continue;

    if (typeof fm.name !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(fm.name) || fm.name.length > 64) {
      fail(where, `name must be kebab-case <= 64 chars (got ${JSON.stringify(fm.name)})`);
    } else if (fm.name !== dir) {
      fail(where, `frontmatter name "${fm.name}" does not match folder name "${dir}"`);
    }

    if (typeof fm.description !== 'string' || !fm.description.trim()) {
      fail(where, 'description must be a non-empty string');
    } else if (fm.description.length > 1024) {
      fail(where, `description is ${fm.description.length} chars; max allowed is 1024`);
    }

    if (fm.license !== 'MIT') {
      fail(where, `expected license: MIT (got ${JSON.stringify(fm.license)})`);
    }

    if (label === 'EN' && /runglish/i.test(src)) {
      fail(where, 'Western EN skill should not contain Runglish-specific instructions');
    }

    if (fm.name) {
      if (names.has(fm.name)) fail(where, `duplicate skill name "${fm.name}" in ${rootRel}/`);
      else names.set(fm.name, where);
    }
    totalSkills++;
  }

  if (names.size === 0) fail(rootRel, `no ${label} skills found`);
}

// Validate all plugin & marketplace JSON manifests
const manifests = [
  'plugin.json',
  'gemini-extension.json',
  '.claude-plugin/plugin.json',
  '.claude-plugin/marketplace.json',
  '.codex-plugin/plugin.json',
  '.agents/plugins/marketplace.json',
  '.github/plugin/plugin.json',
  '.github/plugin/marketplace.json',
];

for (const rel of manifests) {
  const p = join(ROOT, rel);
  if (!existsSync(p)) {
    fail(rel, 'expected manifest file is missing');
    continue;
  }
  let j;
  try {
    j = JSON.parse(readFileSync(p, 'utf8'));
  } catch (e) {
    fail(rel, `invalid JSON: ${e.message}`);
    continue;
  }

  if (typeof j.skills === 'string' && !existsSync(join(ROOT, j.skills))) {
    fail(rel, `skills path "${j.skills}" does not exist`);
  }
  if (typeof j.contextFileName === 'string' && !existsSync(join(ROOT, j.contextFileName))) {
    fail(rel, `contextFileName "${j.contextFileName}" does not exist`);
  }
  for (const [field, value] of [
    ['logo', j.logo],
    ['interface.logo', j.interface?.logo],
    ['interface.composerIcon', j.interface?.composerIcon],
  ]) {
    if (value === undefined) continue;
    if (typeof value !== 'string') {
      fail(rel, `${field} must be a string path`);
    } else if (!existsSync(join(ROOT, value))) {
      fail(rel, `${field} "${value}" does not exist`);
    }
  }

  if (j.plugins !== undefined && !Array.isArray(j.plugins)) {
    fail(rel, 'plugins must be an array');
    continue;
  }
  for (const plugin of j.plugins || []) {
    if (!plugin || typeof plugin !== 'object' || Array.isArray(plugin)) {
      fail(rel, 'plugin entries must be objects');
      continue;
    }
    if (typeof plugin.name !== 'string' || !plugin.name) {
      fail(rel, 'plugin.name must be a non-empty string');
      continue;
    }
    if (
      plugin.skills !== undefined &&
      typeof plugin.skills !== 'string' &&
      !Array.isArray(plugin.skills)
    ) {
      fail(rel, `plugin "${plugin.name}" skills must be a string or an array`);
      continue;
    }
    const skillEntries = Array.isArray(plugin.skills)
      ? plugin.skills
      : typeof plugin.skills === 'string'
        ? [plugin.skills]
        : [];
    for (const s of skillEntries) {
      const resolved = join(ROOT, s);
      if (!existsSync(resolved)) {
        fail(rel, `plugin "${plugin.name}" references missing path "${s}"`);
      } else if (
        statSync(resolved).isDirectory() &&
        !['skills/', './skills/', 'skills-ru/', './skills-ru/'].includes(s) &&
        !existsSync(join(resolved, 'SKILL.md'))
      ) {
        fail(rel, `plugin "${plugin.name}" lists skill folder "${s}" without SKILL.md`);
      }
    }
  }
}

if (errors.length) {
  console.error(`not ok - ${errors.length} problem(s):`);
  for (const e of errors) console.error('  ' + e);
  process.exit(1);
}

console.log(`ok - ${totalSkills} skills (EN + RU) and ${manifests.length} manifests validated (${YAML ? 'strict yaml' : 'built-in parser'})`);
