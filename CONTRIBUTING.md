# Contributing to Dopamine Talk

Thanks for wanting to make AI coding agents sharper and more fun to build with.

## High-Value Contributions

- **Real Before vs After comparisons** on frontier models (same prompt, clean baseline vs skill loaded).
- **New native language editions** — adapted idiomatically to how engineers actually speak in that language, never literal machine translations.
- **New coding-agent adapters or installer fixes** in [`install.sh`](install.sh) and [`INSTALL.md`](INSTALL.md).
- **Prompt sharpness improvements** that tighten signal without turning the skills into rigid checklists.

## Editing Guidelines

1. Keep `skills/` strictly native Western English (no cross-lingual baggage or non-English examples) and `skills-ru/` strictly native Russian.
2. Keep every `SKILL.md` frontmatter `description` under 1024 characters with clear trigger phrases.
3. Preserve zero runtime dependencies — pure Markdown skills and standard shell/Node checks only.

## Verify Locally Before Opening a PR

Run the full CI suite in one command:

```bash
node tests/frontmatter.mjs && node tests/text-encoding.mjs && node tests/links.mjs && bash -n install.sh
```

Every check runs automatically via GitHub Actions on pull requests to `main`.
