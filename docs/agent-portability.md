# Agent Portability

Dopamine Talk ships **two clean, independent skill editions** with thin zero-code adapters so every major AI coding agent loads only the language you actually want — zero prompt collision.

## Included Editions

| Edition | Folder | Always-On Rules | What's Inside |
| --- | --- | --- | --- |
| **English (Western)** | [`skills/`](../skills/) | [`AGENTS.md`](../AGENTS.md) | Adapted for Western/English workflows: 5 post-RL fixes, zero corporate AI slop, zero Runglish noise |
| **Russian (Original)** | [`skills-ru/`](../skills-ru/) | [`docs/i18n/AGENTS.ru.md`](i18n/AGENTS.ru.md) | Original native Russian edition: all 6 post-RL fixes including cross-lingual Runglish collapse protection |

Both editions expose the exact same clean skill names (`dopamine-talk`, `dopamine-readme`, `dopamine-changelog`).

## Host Adapter Map

| Host | Files Read | Install Path |
| --- | --- | --- |
| **Interactive Installer** (EN & RU) | `skills/` or `skills-ru/`, `AGENTS.md` or `AGENTS.ru.md` | `curl -fsSL https://raw.githubusercontent.com/AnnenkovLabs/dopamine-talk/main/install.sh \| bash` |
| `npx skills` (20+ agents, EN) | `skills/*/SKILL.md` | `npx skills add AnnenkovLabs/dopamine-talk` |
| Claude Code / CodeBuddy (EN & RU) | `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json` | `/plugin install dopamine-talk@dopamine-talk` or `dopamine-talk-ru@dopamine-talk` |
| Codex CLI & Desktop | `.agents/plugins/marketplace.json`, `.codex-plugin/plugin.json`, `skills/`, `assets/icon.png` | `codex plugin marketplace add AnnenkovLabs/dopamine-talk` + `codex plugin add dopamine-talk@dopamine-talk` |
| Antigravity CLI | `plugin.json`, `skills/`, `AGENTS.md` | `agy plugin install https://github.com/AnnenkovLabs/dopamine-talk` |
| Gemini CLI / Qwen Code | `gemini-extension.json`, `AGENTS.md`, `skills/` | `gemini extensions install https://github.com/AnnenkovLabs/dopamine-talk` |
| GitHub Copilot CLI (EN & RU) | `.github/plugin/marketplace.json`, `.github/plugin/plugin.json` | `copilot plugin install dopamine-talk@dopamine-talk` or `dopamine-talk-ru@dopamine-talk` |
| Goose | `plugin.json`, `skills/`, `AGENTS.md` | `goose plugin install https://github.com/AnnenkovLabs/dopamine-talk.git` |
| Oh My Pi (`omp`) | `.claude-plugin/marketplace.json` | `omp plugin install dopamine-talk@dopamine-talk` (or `dopamine-talk-ru`) |
| Cursor / Windsurf / Cline / Zed / Amp / Jules | `AGENTS.md` / `docs/i18n/AGENTS.ru.md` + `install.sh` | Run `./install.sh --rules .` or copy `AGENTS.md` |

## Zero-Dependency Guarantee

None of the skills require Node.js, Python, Docker, hooks, MCP servers, or API keys at runtime. Every adapter points directly at static Markdown files.
