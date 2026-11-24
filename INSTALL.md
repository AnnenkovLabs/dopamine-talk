# Install Dopamine Talk

Dopamine Talk ships in **two native editions**:

- **English (Western edition — [`skills/`](skills/)):** 5 post-RL fixes adapted for English engineering workflows (zero critic-gates, zero AST narration, zero corporate AI slop, zero timid caveats).
- **Russian (Original native edition — [`skills-ru/`](skills-ru/)):** All 6 post-RL reflexes including full anti-Runglish cross-lingual collapse protection.

Zero runtime dependencies, zero API keys, zero hooks required. For which manifest maps to which host, see [Agent Portability](docs/agent-portability.md).

---

## Interactive Installer (Recommended — Pick Edition, Skills & Agents)

Works on Linux, macOS, WSL, and Windows (Git Bash) with zero dependencies. Automatically detects installed AI agents on your machine and lets you pick **English or Russian**, **all 3 skills or specific ones**, **symlink or copy**, and optional **`AGENTS.md` rules**:

```bash
curl -fsSL https://raw.githubusercontent.com/AnnenkovLabs/dopamine-talk/main/install.sh | bash
```

Or from a local clone:

```bash
git clone https://github.com/AnnenkovLabs/dopamine-talk.git
cd dopamine-talk
./install.sh
```

### One-Line Non-Interactive Commands

```bash
# English (Western) edition across Universal + Claude + Codex + Gemini
./install.sh --lang en --all-agents --yes

# Russian native edition across Claude Code and Codex
./install.sh --lang ru --claude --codex --yes

# Pick individual skills (short aliases: talk, readme, changelog)
./install.sh --lang en --skills talk,readme --claude --yes

# Switch installed edition EN <-> RU in one second
./install.sh --lang ru --all-agents --force --yes

# Check which edition (EN/RU) and skills are currently installed
./install.sh --status

# Also copy compact always-on AGENTS.md into the current project
./install.sh --lang en --claude --rules . --yes
```

<details>
<summary><strong>All installer flags</strong></summary>

| Flag | What it does |
| --- | --- |
| `--lang en\|ru` | Pick Western English (`skills/`) or Russian native (`skills-ru/`) edition |
| `--skills LIST` | Comma-separated skills: `all`, `talk`, `readme`, `changelog` (or full names) |
| `--agents` | `~/.agents/skills` (Antigravity, OpenCode, Cline, Pi, DSH, Command Code) |
| `--claude` | `~/.claude/skills` (Claude Code) |
| `--codex` | `~/.codex/skills` (OpenAI Codex) |
| `--gemini` | `~/.gemini/config/skills` (Gemini CLI / Antigravity config) |
| `--cursor` | `~/.cursor/skills` (Cursor) |
| `--opencode` | `~/.config/opencode/skills` (OpenCode) |
| `--kiro` | `~/.kiro/skills` (Kiro) |
| `--dir PATH` | Any custom skills directory |
| `--all-agents` | Universal + Claude Code + Codex + Gemini CLI |
| `--link` / `--copy` | Symlink (auto-updates via `git pull`) or standalone copy |
| `--rules [DIR]` | Also copy matching-language `AGENTS.md` into `DIR` (default `.`) |
| `--force`, `-f` | Replace existing Dopamine Talk installs (ideal for switching EN <-> RU) |
| `-y`, `--yes` | Run non-interactively using detected/specified defaults |
| `--status` | Inspect installed edition (`EN`/`RU`) and link/copy status across agents |
| `--list` | Print all available skills across both editions |
| `--uninstall` | Cleanly remove Dopamine Talk skills from selected or all targets |

</details>

---

## Claude Code & CodeBuddy

Add the marketplace once, then install whichever edition you want:

```text
/plugin marketplace add AnnenkovLabs/dopamine-talk
```

**English (Western) edition:**

```text
/plugin install dopamine-talk@dopamine-talk
```

**Russian native edition:**

```text
/plugin install dopamine-talk-ru@dopamine-talk
```

Update later with `/plugin update`.

---

## Universal (`npx skills` / skills.sh)

Installs the English Western edition out of the box across 20+ agents:

```bash
npx skills add AnnenkovLabs/dopamine-talk
```

Install all three skills globally without prompts:

```bash
npx skills add AnnenkovLabs/dopamine-talk --skill '*' --global
```

*(Want the Russian edition across 20+ agents? Use the [Interactive Installer](#interactive-installer-recommended--pick-edition-skills--agents) with `--lang ru`.)*

---

## OpenAI Codex (CLI & Desktop)

```bash
codex plugin marketplace add AnnenkovLabs/dopamine-talk
codex plugin add dopamine-talk@dopamine-talk
```

Start a new session (or restart Codex Desktop) so the skills load.

---

## Antigravity CLI

```bash
agy plugin install https://github.com/AnnenkovLabs/dopamine-talk
```

For always-on workspace rules, copy [`AGENTS.md`](AGENTS.md) (English) or [`docs/i18n/AGENTS.ru.md`](docs/i18n/AGENTS.ru.md) (Russian) into your repository root.

---

## Gemini CLI & Qwen Code

```bash
gemini extensions install https://github.com/AnnenkovLabs/dopamine-talk
```

Loads [`AGENTS.md`](AGENTS.md) as always-on context and discovers the skills in `skills/`.

---

## GitHub Copilot CLI

```bash
copilot plugin marketplace add AnnenkovLabs/dopamine-talk
copilot plugin install dopamine-talk@dopamine-talk     # English edition
copilot plugin install dopamine-talk-ru@dopamine-talk  # Russian edition
```

---

## Goose & Oh My Pi (`omp`)

```bash
# Goose
goose plugin install https://github.com/AnnenkovLabs/dopamine-talk.git

# Oh My Pi
omp plugin marketplace add AnnenkovLabs/dopamine-talk
omp plugin install dopamine-talk@dopamine-talk
```

---

## Rules-Only Hosts (Cursor, Windsurf, Cline, Zed, Amp, Jules, CodeWhale)

Copy [`AGENTS.md`](AGENTS.md) (English) or [`docs/i18n/AGENTS.ru.md`](docs/i18n/AGENTS.ru.md) (Russian) into your project root or global user rules file (`~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md`, `~/.agents/AGENTS.md`).

---

## Uninstall

| Host | Command |
| --- | --- |
| Interactive installer | `./install.sh --uninstall` (or add `--claude`, `--all-agents`, etc.) |
| `npx skills` | `npx skills remove dopamine-talk dopamine-readme dopamine-changelog` |
| Claude Code | `/plugin remove dopamine-talk` (or `dopamine-talk-ru`) |
| Codex | `codex plugin remove dopamine-talk` |
| Gemini CLI | `gemini extensions uninstall dopamine-talk` |
| GitHub Copilot CLI | `copilot plugin uninstall dopamine-talk` |
| Rules-only hosts | Delete the copied `AGENTS.md` |
