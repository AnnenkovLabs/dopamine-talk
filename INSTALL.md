# Install Dopamine Talk

Dopamine Talk ships in **two native editions**:

- **English (Western edition — [`skills/`](skills/)):** sharp, energetic, zero-fluff engineering communication across chat, changelogs, and READMEs.
- **Russian (Original native edition — [`skills-ru/`](skills-ru/)):** written natively in Russian with dedicated protection against cross-lingual Runglish and corporate filler.

Zero runtime dependencies, zero API keys, zero hooks required. For which manifest maps to which host, see [Agent Portability](docs/agent-portability.md).

---

## One-Line Installer (Recommended — Skills + Always-On Mode)

Installs all 3 skills **and** safely appends a clean marker-scoped always-on rule block (`<!-- dopamine-talk:start --> ... <!-- dopamine-talk:end -->`) into your detected agents' global instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, Cursor `dopamine-talk.mdc`, Windsurf `global_rules.md`, Copilot `copilot-instructions.md`) — never touching your own rules, and cleanly removable with `--uninstall`.

### macOS / Linux / WSL / Git Bash

```bash
# Interactive wizard (auto-detects agents & language)
curl -fsSL https://dopamine.annenkov.me/install.sh | bash

# Russian edition directly
curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --lang ru
```

### Windows (PowerShell 5.1+ / 7+)

```powershell
# Interactive wizard
irm https://dopamine.annenkov.me/install.ps1 | iex

# Russian edition directly (non-interactive)
& ([scriptblock]::Create((irm https://dopamine.annenkov.me/install.ps1))) -Lang ru -Yes

# Replace existing copies, including an unrelated same-named skill directory
& ([scriptblock]::Create((irm https://dopamine.annenkov.me/install.ps1))) -Lang en -Yes -Force

# Remove only the Claude Code install and its CLAUDE.md rule block
& ([scriptblock]::Create((irm https://dopamine.annenkov.me/install.ps1))) -Uninstall -Claude
```

### Non-Interactive CLI Flags

```bash
# English across all detected agents (skills + always-on global rules)
curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --lang en --yes

# Russian edition for Claude Code & Codex only
curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --lang ru --claude --codex --yes

# Skills only (skip global always-on CLAUDE.md / AGENTS.md rules)
curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --lang en --no-global-rules --yes

# Switch EN <-> RU anytime
curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --lang ru --force --yes

# Check active edition, skills, and global always-on rules
curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --status

# Cleanly remove skills and marked always-on blocks (preserves your own rules)
curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --uninstall
```

<details>
<summary><strong>All installer flags</strong></summary>

| Flag | What it does |
| --- | --- |
| `--lang en\|ru` | Pick Western English (`skills/`) or native Russian (`skills-ru/`) edition |
| `--skills LIST` | Comma-separated skills: `all`, `talk`, `readme`, `changelog` |
| `--agents` | `~/.agents/skills` + `~/.agents/AGENTS.md` (Antigravity, OpenCode, Cline, Pi) |
| `--claude` | `~/.claude/skills` + `~/.claude/CLAUDE.md` (Claude Code) |
| `--codex` | `~/.codex/skills` + `~/.codex/AGENTS.md` (OpenAI Codex) |
| `--gemini` | `~/.gemini/config/skills` + `~/.gemini/GEMINI.md` + `rules/dopamine-talk.md` |
| `--antigravity` | Both `--agents` and `--gemini` |
| `--cursor` | `~/.cursor/skills` + `~/.cursor/rules/dopamine-talk.mdc` (`alwaysApply: true`) |
| `--windsurf` | `~/.codeium/windsurf/skills` + `~/.codeium/windsurf/memories/global_rules.md` |
| `--copilot` | `~/.copilot/skills` + `~/.copilot/copilot-instructions.md` |
| `--opencode` | `~/.config/opencode/skills` + `~/.config/opencode/AGENTS.md` |
| `--kiro` | `~/.kiro/skills` + `~/.kiro/steering/dopamine-talk.md` |
| `--dir PATH` | Any custom skills directory |
| `--all-agents` | Universal + Claude Code + Codex + Gemini + Cursor + Windsurf + Copilot |
| `--global-rules` / `--no-global-rules` | Toggle global always-on rules (on by default with `--yes`) |
| `--rules [DIR]` | Also upsert marked `AGENTS.md` into project `DIR` (default `.`) |
| `--link` / `--copy` | Symlink (auto-updates via `git pull`) or standalone copy |
| `--force`, `-f` | Replace existing Dopamine Talk installs (ideal for EN <-> RU switch) |
| `-y`, `--yes` | Run non-interactively using detected/specified defaults |
| `--status` | Inspect installed edition (`EN`/`RU`), skills, and active global rules |
| `--list` | Print all available skills across both editions |
| `--uninstall` | Cleanly remove skills and marked always-on blocks |

</details>

---

## Claude Code

Run directly in your terminal:

```bash
# English edition
claude plugin marketplace add AnnenkovLabs/dopamine-talk && claude plugin install dopamine-talk@dopamine-talk

# Russian edition
claude plugin marketplace add AnnenkovLabs/dopamine-talk && claude plugin install dopamine-talk-ru@dopamine-talk
```

*(Inside an interactive Claude Code chat, run `/plugin marketplace add AnnenkovLabs/dopamine-talk` first, then `/plugin install dopamine-talk@dopamine-talk` as a second message.)*

---

## Universal (`npx skills` / skills.sh)

Installs the English edition across 20+ agents:

```bash
npx skills add AnnenkovLabs/dopamine-talk
```

*(For the Russian edition or always-on global rules, use the [One-Line Installer](#one-line-installer-recommended--skills--always-on-mode).)*

---

## OpenAI Codex (CLI & Desktop)

```bash
codex plugin marketplace add AnnenkovLabs/dopamine-talk && codex plugin add dopamine-talk@dopamine-talk
```

*(For the Russian edition + always-on `~/.codex/AGENTS.md`: `curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --lang ru --codex --yes`.)*

---

## Antigravity CLI

`agy plugin install` installs from a local plugin directory (bundles all 3 skills, custom 3D icon, and always-on `rules/AGENTS.md`):

```bash
git clone --depth 1 https://github.com/AnnenkovLabs/dopamine-talk.git ~/.local/share/dopamine-talk && agy plugin install ~/.local/share/dopamine-talk
```

Or install skills + always-on rules (EN or RU) without keeping a clone:

```bash
curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --lang ru --antigravity --yes
```

---

## Gemini CLI & Qwen Code

```bash
gemini extensions install https://github.com/AnnenkovLabs/dopamine-talk
```

Loads [`AGENTS.md`](AGENTS.md) as always-on context and discovers the skills in `skills/`.

---

## GitHub Copilot CLI

```bash
copilot plugin marketplace add AnnenkovLabs/dopamine-talk && copilot plugin install dopamine-talk@dopamine-talk
# Russian edition:
copilot plugin marketplace add AnnenkovLabs/dopamine-talk && copilot plugin install dopamine-talk-ru@dopamine-talk
```

---

## Goose & Oh My Pi (`omp`)

```bash
# Goose
goose plugin install https://github.com/AnnenkovLabs/dopamine-talk.git

# Oh My Pi
omp plugin marketplace add AnnenkovLabs/dopamine-talk && omp plugin install dopamine-talk@dopamine-talk
```

---

## Uninstall

| Host | Command |
| --- | --- |
| One-line installer (macOS/Linux) | `curl -fsSL https://dopamine.annenkov.me/install.sh \| bash -s -- --uninstall` |
| One-line installer (Windows) | `& ([scriptblock]::Create((irm https://dopamine.annenkov.me/install.ps1))) -Uninstall` |
| `npx skills` | `npx skills remove dopamine-talk dopamine-readme dopamine-changelog` |
| Claude Code | `claude plugin uninstall dopamine-talk@dopamine-talk` (or `dopamine-talk-ru@dopamine-talk`) |
| Codex | `codex plugin remove dopamine-talk` |
| Antigravity | `agy plugin uninstall dopamine-talk` |
| Gemini CLI | `gemini extensions uninstall dopamine-talk` |
| GitHub Copilot CLI | `copilot plugin uninstall dopamine-talk` |
