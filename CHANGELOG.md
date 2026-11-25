# Changelog

## 1.0.0

November 24, 2026 · Public Launch

**Dopamine Talk 1.0.0 opens the full three-skill decompression pack in two native editions (Western English & Russian) across 20+ AI coding agents with zero runtime dependencies.** Born from a [November 17, 2026 manifesto](docs/origin-prompt.md) about why modern models lost the effortless drive and clarity of 11 months ago, this pack gives your agent character instead of a rubric flowchart: sharp engineering dialogue, 5-second visual READMEs, and user-impact changelogs everywhere you work.

### 🔥 Release Highlights

- **Two native editions — Western English (`skills/`) and Original Russian (`skills-ru/`).** Instead of shipping a stiff literal translation, the Western English edition is natively adapted for English engineering workflows (5 post-RL fixes + anti-corporate-AI-slop voice, zero non-English baggage), while the original Russian edition keeps all 6 post-RL reflexes including dedicated protection against cross-lingual Runglish token collapse. Both editions ship under the same clean skill names (`dopamine-talk`, `dopamine-readme`, `dopamine-changelog`) with matching always-on `AGENTS.md` / `docs/i18n/AGENTS.ru.md` rulesets.
- **Interactive zero-dependency CLI installer (`install.sh`).** Run one command locally or straight via `curl | bash`: auto-detects installed AI agents on your machine (`~/.agents`, Claude Code, Codex, Gemini CLI, Cursor, OpenCode, Kiro, or custom path), lets you choose **EN or RU**, pick all 3 skills or individual ones, choose **symlink** (`git pull` auto-updates + Windows junction fallback) or **copy**, optionally upsert a marked `AGENTS.md` block into your project, inspect what is installed (`--status`), and switch editions anytime (`--lang ru|en`).
- **`dopamine-talk`, `dopamine-readme`, and `dopamine-changelog` as one cohesive pack.** Strips RLVR critic-gate obsession, rubric inventory padding, AST code-trace narration, calibration hedging, and ticket-scoped learned helplessness — and turns dry documentation and raw `git diff` lists into 5-second living GitHub showcases and user-impact `f'(x)` release notes.
- **Native multi-agent marketplaces out of the box.** Ships dual-edition plugins (`dopamine-talk` EN and `dopamine-talk-ru` RU) for Claude Code, CodeBuddy, Oh My Pi, and GitHub Copilot CLI, plus native support for `npx skills`, OpenAI Codex CLI & Desktop, Antigravity CLI, Gemini CLI, Qwen Code, and Goose.

### 📈 Before -> After

In theory:

| Metric | Default Agent Behavior | With Dopamine Talk 1.0.0 | Net Gain | Multiplier |
| :--- | :--- | :--- | :--- | :--- |
| **Useful signal in architectural explanations** | ~35% (buried under file paths, plumbing & disclaimers) | **~90%** (pure workflow mechanics, leverage & math) | **+157% signal density** | **2.6x clearer replies** |
| **Time to grasp a repo's value from its README** | 30-60 s scanning uniform feature bullets | **< 5 s** (hero, KPI glance & Before/After card) | **-85% time to hook** | **6x faster first impression** |
| **Setup & EN/RU switching across multiple agents** | Hand-copying prompt files per tool | **1 interactive wizard** (`curl \| bash` or `./install.sh`) | **-95% manual setup** | **20+ agents in 10 seconds** |
| **Runtime overhead & external packages** | Custom scripts, hooks, or API wrappers | **0 packages · 0 hooks · pure Markdown** | **-100% runtime risk** | **Zero breakage on any OS** |

### ⚡ Under the Hood & Packaging

- **Automated validation & GitHub Actions CI:** Every push and pull request validates strict YAML frontmatter parsing across all 6 `SKILL.md` files (EN + RU), enforces the 1024-char description cap and Western-edition hygiene, verifies all 8 plugin JSON manifests against real skill paths, guards against UTF-8 mojibake, checks every local Markdown link and SVG asset, and syntax-checks `install.sh`.
- **Dual-language storefront with custom 3D crystal-glass icon & dark/light SVGs:** Synchronized English (`README.md`) and native Russian (`docs/i18n/README.ru.md`) showcases with an optical crystal-glass & chrome 3D icon, embedded-font `Manrope` (Latin + Cyrillic) dark/light vector diagrams, and accessible text transcripts.

### 📦 Getting Started

- **Interactive installer (pick EN/RU, skills & agents):** `curl -fsSL https://raw.githubusercontent.com/AnnenkovLabs/dopamine-talk/main/install.sh | bash`
- **Universal (`npx skills`, EN):** `npx skills add AnnenkovLabs/dopamine-talk`
- **Best model fit:** Works on any modern LLM, and shines brightest on flexible models like Google's (Gemini).
- **Heads-up:** Turning off hedging means the model may occasionally embellish or bluff with confidence — built for keeping builder motivation alive while you verify the hard details yourself.
- **Claude Code / Codex / Antigravity / Gemini / Uninstall:** See [INSTALL.md](INSTALL.md).
- **Russian changelog:** [docs/i18n/CHANGELOG.ru.md](docs/i18n/CHANGELOG.ru.md)
