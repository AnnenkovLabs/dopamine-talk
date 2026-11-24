#!/usr/bin/env bash
# Dopamine Talk Interactive Installer
# Supports both local clones (`./install.sh`) and one-line remote installs:
#   curl -fsSL https://raw.githubusercontent.com/AnnenkovLabs/dopamine-talk/main/install.sh | bash
#
# Quick non-interactive examples:
#   ./install.sh --lang en --all-agents --yes
#   ./install.sh --lang ru --claude --codex --yes
#   ./install.sh --lang ru --skills talk,readme --claude --force --yes
#   ./install.sh --status
#   ./install.sh --uninstall --all-agents --yes
#
# Compatible with Bash 3.2+ (macOS, Linux, WSL, Windows Git Bash). Zero dependencies.

set -euo pipefail

REPO_SLUG="AnnenkovLabs/dopamine-talk"
REPO_URL="https://github.com/${REPO_SLUG}.git"
TARBALL_URL="https://github.com/${REPO_SLUG}/archive/refs/heads/main.tar.gz"
MANAGED_CLONE_DIR="${DOPAMINE_HOME:-$HOME/.local/share/dopamine-talk}"

WINDOWS=0
case "$(uname -s 2>/dev/null || echo Unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    WINDOWS=1
    export MSYS=winsymlinks:nativestrict CYGWIN=winsymlinks:nativestrict ;;
esac

# Colors (respect NO_COLOR and non-TTY stdout)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  CORAL=$'\033[38;5;209m'
  AMBER=$'\033[38;5;215m'
  GREEN=$'\033[38;5;114m'
  RED=$'\033[38;5;203m'
  CYAN=$'\033[38;5;117m'
  RESET=$'\033[0m'
else
  BOLD="" DIM="" CORAL="" AMBER="" GREEN="" RED="" CYAN="" RESET=""
fi

# Detect whether running from a local repository clone or piped remotely
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
LOCAL_REPO=""
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  CANDIDATE_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd || true)"
  if [[ -n "$CANDIDATE_DIR" && -d "$CANDIDATE_DIR/skills/dopamine-talk" && -d "$CANDIDATE_DIR/skills-ru/dopamine-talk" ]]; then
    LOCAL_REPO="$CANDIDATE_DIR"
  fi
fi

# CLI state
MODE="install"      # install | uninstall | list | status
EDITION=""          # en | ru
METHOD=""           # link | copy
ASSUME_YES=0
FORCE=0
INSTALL_RULES=0
RULES_DIR="."
SELECTED_SKILLS=()
TARGETS=()
CLEANUP_TMP=""

trap 'if [[ -n "${CLEANUP_TMP:-}" && -d "${CLEANUP_TMP:-}" ]]; then rm -rf "$CLEANUP_TMP"; fi' EXIT

print_help() {
  cat <<'EOF'
Dopamine Talk Installer — install EN (Western) or RU edition across 20+ AI agents.

Usage:
  ./install.sh                          Launch interactive setup wizard
  ./install.sh [options] [skill...]     Run directly with flags

Options:
  --lang en|ru          Skill edition:
                          en = Western English (5 post-RL fixes, zero AI slop)
                          ru = Russian native (all 6 reflexes + anti-Runglish)
  --skills LIST         Comma-separated skills: all, talk, readme, changelog
                        (or full names: dopamine-talk, dopamine-readme, dopamine-changelog)
  --link                Install via symlinks (auto-updates on git pull)
  --copy                Install standalone copies
  --force, -f           Overwrite existing Dopamine Talk installs (great for EN <-> RU switch)
  --rules [DIR]         Also install matching-language AGENTS.md into DIR (default: .)
  -y, --yes             Skip interactive prompts and use detected/specified defaults
  --status              Show which edition (EN/RU) and skills are currently installed
  --list                List available skills across EN and RU editions
  --uninstall           Remove installed Dopamine Talk skills from selected/all targets
  -h, --help            Show this help message

Target Agent Shortcuts:
  --agents              ~/.agents/skills (Antigravity, OpenCode, Cline, Pi, DSH, Command Code)
  --claude              ~/.claude/skills (Claude Code)
  --codex               ~/.codex/skills (OpenAI Codex)
  --gemini              ~/.gemini/config/skills (Gemini CLI / Antigravity config)
  --cursor              ~/.cursor/skills (Cursor)
  --opencode            ~/.config/opencode/skills (OpenCode)
  --kiro                ~/.kiro/skills (Kiro)
  --dir PATH            Install into any custom skills directory
  --all-agents          Universal + Claude Code + Codex + Gemini CLI
EOF
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_skill_name() {
  local raw
  raw="$(lower "$1")"
  case "$raw" in
    talk|dopamine-talk)           printf 'dopamine-talk\n' ;;
    readme|dopamine-readme)       printf 'dopamine-readme\n' ;;
    changelog|dopamine-changelog) printf 'dopamine-changelog\n' ;;
    all|'*')                      printf 'ALL\n' ;;
    *)                            return 1 ;;
  esac
}

add_target_unique() {
  local dir="$1"
  local existing
  for existing in "${TARGETS[@]:-}"; do
    [[ "$existing" == "$dir" ]] && return 0
  done
  TARGETS+=("$dir")
}

add_skill_unique() {
  local name="$1"
  local existing
  for existing in "${SELECTED_SKILLS[@]:-}"; do
    [[ "$existing" == "$name" ]] && return 0
  done
  SELECTED_SKILLS+=("$name")
}

# Parse CLI flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang|--edition)
      [[ $# -ge 2 ]] || { echo "${RED}error:${RESET} --lang requires 'en' or 'ru'" >&2; exit 2; }
      EDITION="$(lower "$2")"
      case "$EDITION" in
        en|english) EDITION="en" ;;
        ru|russian) EDITION="ru" ;;
        *) echo "${RED}error:${RESET} unsupported language '$2' (use 'en' or 'ru')" >&2; exit 2 ;;
      esac
      shift ;;
    --skills)
      [[ $# -ge 2 ]] || { echo "${RED}error:${RESET} --skills requires a value" >&2; exit 2; }
      IFS=',' read -r -a _parts <<< "$2"
      for _p in "${_parts[@]}"; do
        _p="$(printf '%s' "$_p" | tr -d '[:space:]')"
        [[ -z "$_p" ]] && continue
        _norm="$(normalize_skill_name "$_p")" || { echo "${RED}error:${RESET} unknown skill '$_p'" >&2; exit 2; }
        if [[ "$_norm" == "ALL" ]]; then
          add_skill_unique "dopamine-talk"
          add_skill_unique "dopamine-readme"
          add_skill_unique "dopamine-changelog"
        else
          add_skill_unique "$_norm"
        fi
      done
      shift ;;
    --agents)      add_target_unique "$HOME/.agents/skills" ;;
    --claude)      add_target_unique "$HOME/.claude/skills" ;;
    --codex)       add_target_unique "$HOME/.codex/skills" ;;
    --gemini)      add_target_unique "$HOME/.gemini/config/skills" ;;
    --antigravity) add_target_unique "$HOME/.agents/skills"; add_target_unique "$HOME/.gemini/config/skills" ;;
    --cursor)      add_target_unique "$HOME/.cursor/skills" ;;
    --opencode)    add_target_unique "$HOME/.config/opencode/skills" ;;
    --kiro)        add_target_unique "$HOME/.kiro/skills" ;;
    --all-agents)
      add_target_unique "$HOME/.agents/skills"
      add_target_unique "$HOME/.claude/skills"
      add_target_unique "$HOME/.codex/skills"
      add_target_unique "$HOME/.gemini/config/skills" ;;
    --dir)
      [[ $# -ge 2 ]] || { echo "${RED}error:${RESET} --dir requires a directory path" >&2; exit 2; }
      add_target_unique "$2"
      shift ;;
    --link|--symlink) METHOD="link" ;;
    --copy)           METHOD="copy" ;;
    --rules)
      INSTALL_RULES=1
      if [[ $# -ge 2 && "$2" != -* ]]; then
        RULES_DIR="$2"
        shift
      fi ;;
    -f|--force)   FORCE=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    --list)       MODE="list" ;;
    --status)     MODE="status" ;;
    --uninstall)  MODE="uninstall" ;;
    -h|--help)    print_help; exit 0 ;;
    -*)           echo "${RED}error:${RESET} unknown flag '$1' (run with --help)" >&2; exit 2 ;;
    *)
      _norm="$(normalize_skill_name "$1")" || { echo "${RED}error:${RESET} unknown skill '$1'" >&2; exit 2; }
      if [[ "$_norm" == "ALL" ]]; then
        add_skill_unique "dopamine-talk"
        add_skill_unique "dopamine-readme"
        add_skill_unique "dopamine-changelog"
      else
        add_skill_unique "$_norm"
      fi ;;
  esac
  shift
done

# TTY helper (works even when script is piped via `curl ... | bash`)
CAN_PROMPT=0
if [[ $ASSUME_YES -eq 0 ]]; then
  if [[ -t 0 ]]; then
    CAN_PROMPT=1
    TTY_IN="/dev/stdin"
  elif [[ -r /dev/tty ]]; then
    CAN_PROMPT=1
    TTY_IN="/dev/tty"
  fi
fi

prompt_line() {
  local label="$1"
  local reply=""
  printf '%s' "$label" >&2
  IFS= read -r reply < "$TTY_IN" || reply=""
  reply="${reply%$'\r'}"
  printf '%s' "$reply"
}

detect_edition_from_file() {
  local md="$1"
  [[ -f "$md" ]] || { printf 'unknown'; return; }
  if grep -q 'Деактивирует\|Пишет и переписывает\|Включает режим' "$md" 2>/dev/null; then
    printf 'RU'
  else
    printf 'EN'
  fi
}

KNOWN_AGENT_LABELS=(
  "Universal (~/.agents/skills — Antigravity, OpenCode, Cline, Pi, DSH)"
  "Claude Code (~/.claude/skills)"
  "OpenAI Codex (~/.codex/skills)"
  "Gemini CLI / Antigravity (~/.gemini/config/skills)"
  "Cursor (~/.cursor/skills)"
  "OpenCode (~/.config/opencode/skills)"
  "Kiro (~/.kiro/skills)"
)
KNOWN_AGENT_DIRS=(
  "$HOME/.agents/skills"
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.gemini/config/skills"
  "$HOME/.cursor/skills"
  "$HOME/.config/opencode/skills"
  "$HOME/.kiro/skills"
)
KNOWN_AGENT_PROBES=(
  "$HOME/.agents"
  "$HOME/.claude"
  "$HOME/.codex"
  "$HOME/.gemini"
  "$HOME/.cursor"
  "$HOME/.config/opencode"
  "$HOME/.kiro"
)

# --- MODE: STATUS ---
if [[ "$MODE" == "status" ]]; then
  echo ""
  echo "${BOLD}${CORAL}Dopamine Talk — Installed Status${RESET}"
  echo "${DIM}Checking standard agent skill directories...${RESET}"
  echo ""
  found_any=0
  for i in "${!KNOWN_AGENT_DIRS[@]}"; do
    dir="${KNOWN_AGENT_DIRS[$i]}"
    [[ -d "$dir" ]] || continue
    for s in dopamine-talk dopamine-readme dopamine-changelog; do
      p="$dir/$s"
      if [[ -L "$p" || -d "$p" ]]; then
        found_any=1
        ed="$(detect_edition_from_file "$p/SKILL.md")"
        kind="copy"
        extra=""
        if [[ -L "$p" ]]; then
          kind="link"
          extra=" ${DIM}-> $(readlink "$p" 2>/dev/null || true)${RESET}"
        fi
        printf '  %s✓%s %-20s %s[%s · %s]%s  %s%s\n' "$GREEN" "$RESET" "$s" "$AMBER" "$ed" "$kind" "$RESET" "$p" "$extra"
      fi
    done
  done
  if [[ $found_any -eq 0 ]]; then
    echo "  ${DIM}No Dopamine Talk skills currently installed.${RESET}"
  fi
  echo ""
  exit 0
fi

# --- MODE: LIST ---
if [[ "$MODE" == "list" ]]; then
  echo ""
  echo "${BOLD}${CORAL}Available Dopamine Talk Skills${RESET}"
  echo ""
  echo "  ${BOLD}English (Western edition — skills/)${RESET}"
  printf '    %-22s %s\n' "dopamine-talk"      "skills/dopamine-talk       (5 post-RL fixes, zero corporate AI slop)"
  printf '    %-22s %s\n' "dopamine-readme"    "skills/dopamine-readme     (5-second visual GitHub showcases)"
  printf '    %-22s %s\n' "dopamine-changelog" "skills/dopamine-changelog  (user-impact f'(x) release notes)"
  echo ""
  echo "  ${BOLD}Русский (Оригинальная версия — skills-ru/)${RESET}"
  printf '    %-22s %s\n' "dopamine-talk"      "skills-ru/dopamine-talk       (все 6 рефлексов RLVR + анти-Runglish)"
  printf '    %-22s %s\n' "dopamine-readme"    "skills-ru/dopamine-readme     (живые витрины README под тест 5 секунд)"
  printf '    %-22s %s\n' "dopamine-changelog" "skills-ru/dopamine-changelog  (чейнджлоги пользы f'(x) и точные CVE)"
  echo ""
  exit 0
fi

# Symlink / copy helpers
make_link() {
  local src="$1" dst="$2"
  if ln -s "$src" "$dst" 2>/dev/null && [[ -L "$dst" ]]; then return 0; fi
  [[ -e "$dst" && ! -L "$dst" ]] && rm -rf "$dst"
  if [[ $WINDOWS -eq 1 ]] && command -v cygpath >/dev/null 2>&1; then
    cmd //c mklink //J "$(cygpath -w "$dst")" "$(cygpath -w "$src")" >/dev/null 2>&1 && [[ -L "$dst" || -d "$dst" ]] && return 0
  fi
  return 1
}

remove_entry() {
  local target="$1"
  if [[ -L "$target" ]]; then
    if [[ $WINDOWS -eq 1 ]] && command -v cygpath >/dev/null 2>&1; then
      cmd //c rmdir "$(cygpath -w "$target")" >/dev/null 2>&1 && return 0
    fi
    rm -f "$target"
  elif [[ -d "$target" ]]; then
    rm -rf "$target"
  fi
}

# --- MODE: UNINSTALL ---
if [[ "$MODE" == "uninstall" ]]; then
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    for d in "${KNOWN_AGENT_DIRS[@]}"; do
      add_target_unique "$d"
    done
  fi
  if [[ ${#SELECTED_SKILLS[@]} -eq 0 ]]; then
    SELECTED_SKILLS=("dopamine-talk" "dopamine-readme" "dopamine-changelog")
  fi

  echo ""
  echo "${BOLD}${CORAL}Uninstalling Dopamine Talk...${RESET}"
  removed=0
  for dir in "${TARGETS[@]}"; do
    [[ -d "$dir" ]] || continue
    for s in "${SELECTED_SKILLS[@]}"; do
      p="$dir/$s"
      if [[ -L "$p" || -d "$p" ]]; then
        if [[ -f "$p/SKILL.md" || -L "$p" ]]; then
          remove_entry "$p"
          echo "  ${GREEN}✓${RESET} removed  $p"
          removed=$((removed + 1))
        fi
      fi
    done
  done
  if [[ $removed -eq 0 ]]; then
    echo "  ${DIM}Nothing to remove in selected directories.${RESET}"
  fi
  echo ""
  exit 0
fi

# --- MODE: INSTALL ---
# Interactive wizard header
if [[ $CAN_PROMPT -eq 1 && ( -z "$EDITION" || ${#TARGETS[@]} -eq 0 || ${#SELECTED_SKILLS[@]} -eq 0 || -z "$METHOD" ) ]]; then
  echo ""
  echo "${BOLD}${CORAL}━━━ Dopamine Talk Installer ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  if [[ -n "$LOCAL_REPO" ]]; then
    echo "${DIM}Source: local clone (${LOCAL_REPO})${RESET}"
  else
    echo "${DIM}Source: github.com/${REPO_SLUG} (remote)${RESET}"
  fi
  echo ""
fi

# Step 1: Choose Language Edition
if [[ -z "$EDITION" ]]; then
  default_ed="1"
  case "${LANG:-}" in
    ru_*|uk_*|be_*) default_ed="2" ;;
  esac

  if [[ $CAN_PROMPT -eq 1 ]]; then
    echo "${BOLD}1. Choose skill edition / Выбери версию скиллов:${RESET}"
    echo "   ${AMBER}1)${RESET} ${BOLD}English${RESET}  ${DIM}(Western edition — 5 post-RL fixes, zero corporate AI slop)${RESET}"
    echo "   ${AMBER}2)${RESET} ${BOLD}Русский${RESET}  ${DIM}(Оригинальная версия — 6 рефлексов RLVR + защита от Runglish)${RESET}"
    ans="$(prompt_line "   Pick [1/2] (default ${default_ed}): ")"
    ans="${ans:-$default_ed}"
    case "$(lower "$ans")" in
      1|en|english) EDITION="en" ;;
      2|ru|russian) EDITION="ru" ;;
      *) echo "${RED}error:${RESET} invalid choice '$ans'" >&2; exit 2 ;;
    esac
    echo ""
  else
    EDITION="$([[ "$default_ed" == "2" ]] && echo "ru" || echo "en")"
  fi
fi

# Step 2: Choose Skills
if [[ ${#SELECTED_SKILLS[@]} -eq 0 ]]; then
  if [[ $CAN_PROMPT -eq 1 ]]; then
    if [[ "$EDITION" == "ru" ]]; then
      echo "${BOLD}2. Какие скиллы поставить?${RESET}"
      echo "   ${AMBER}1)${RESET} ${BOLD}dopamine-talk${RESET}       ${DIM}— декомпрессия после RLVR и живой диалог${RESET}"
      echo "   ${AMBER}2)${RESET} ${BOLD}dopamine-readme${RESET}     ${DIM}— живые витрины README под тест 5 секунд${RESET}"
      echo "   ${AMBER}3)${RESET} ${BOLD}dopamine-changelog${RESET}  ${DIM}— чейнджлоги пользы f'(x) и точные CVE${RESET}"
      ans="$(prompt_line "   Номера через запятую или Enter для всех трёх [all]: ")"
    else
      echo "${BOLD}2. Which skills do you want?${RESET}"
      echo "   ${AMBER}1)${RESET} ${BOLD}dopamine-talk${RESET}       ${DIM}— post-RL decompression & sharp engineering voice${RESET}"
      echo "   ${AMBER}2)${RESET} ${BOLD}dopamine-readme${RESET}     ${DIM}— living GitHub storefronts built for 5-second scroll${RESET}"
      echo "   ${AMBER}3)${RESET} ${BOLD}dopamine-changelog${RESET}  ${DIM}— user-impact f'(x) release notes & CVE clarity${RESET}"
      ans="$(prompt_line "   Numbers separated by commas, or Enter for all 3 [all]: ")"
    fi
    ans="$(printf '%s' "${ans:-all}" | tr -d '[:space:]')"
    if [[ -z "$ans" || "$(lower "$ans")" == "all" || "$ans" == "*" ]]; then
      SELECTED_SKILLS=("dopamine-talk" "dopamine-readme" "dopamine-changelog")
    else
      IFS=',' read -r -a _nums <<< "$ans"
      for n in "${_nums[@]}"; do
        case "$n" in
          1|talk|dopamine-talk)           add_skill_unique "dopamine-talk" ;;
          2|readme|dopamine-readme)       add_skill_unique "dopamine-readme" ;;
          3|changelog|dopamine-changelog) add_skill_unique "dopamine-changelog" ;;
          *) echo "${RED}error:${RESET} invalid skill selection '$n'" >&2; exit 2 ;;
        esac
      done
    fi
    echo ""
  else
    SELECTED_SKILLS=("dopamine-talk" "dopamine-readme" "dopamine-changelog")
  fi
fi

# Step 3: Auto-detect & Choose Target Agents
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  detected_indices=()
  for i in "${!KNOWN_AGENT_PROBES[@]}"; do
    if [[ -d "${KNOWN_AGENT_PROBES[$i]}" ]]; then
      detected_indices+=("$((i + 1))")
    fi
  done
  if [[ ${#detected_indices[@]} -eq 0 ]]; then
    detected_indices=("1")
  fi
  default_agents="$(IFS=','; echo "${detected_indices[*]}")"

  if [[ $CAN_PROMPT -eq 1 ]]; then
    if [[ "$EDITION" == "ru" ]]; then
      echo "${BOLD}3. Куда установить? (найденные среды отмечены зелёным)${RESET}"
    else
      echo "${BOLD}3. Where should we install? (detected agents are highlighted)${RESET}"
    fi
    for i in "${!KNOWN_AGENT_LABELS[@]}"; do
      num=$((i + 1))
      tag=""
      if [[ -d "${KNOWN_AGENT_PROBES[$i]}" ]]; then
        tag=" ${GREEN}[detected]${RESET}"
      fi
      echo "   ${AMBER}${num})${RESET} ${KNOWN_AGENT_LABELS[$i]}${tag}"
    done
    if [[ "$EDITION" == "ru" ]]; then
      echo "   ${AMBER}8)${RESET} Свой путь к папке..."
      ans="$(prompt_line "   Номера через запятую, 'all' или Enter для [${default_agents}]: ")"
    else
      echo "   ${AMBER}8)${RESET} Custom directory path..."
      ans="$(prompt_line "   Numbers separated by commas, 'all', or Enter for [${default_agents}]: ")"
    fi
    ans="$(printf '%s' "${ans:-$default_agents}" | tr -d '[:space:]')"
    if [[ "$(lower "$ans")" == "all" ]]; then
      for i in 0 1 2 3; do add_target_unique "${KNOWN_AGENT_DIRS[$i]}"; done
    else
      IFS=',' read -r -a _picks <<< "$ans"
      for pk in "${_picks[@]}"; do
        case "$pk" in
          1|2|3|4|5|6|7) add_target_unique "${KNOWN_AGENT_DIRS[$((pk - 1))]}" ;;
          8)
            custom_dir="$(prompt_line "   Enter full target path: ")"
            custom_dir="${custom_dir/#\~/$HOME}"
            [[ -n "$custom_dir" ]] && add_target_unique "$custom_dir" ;;
          *) echo "${RED}error:${RESET} invalid target choice '$pk'" >&2; exit 2 ;;
        esac
      done
    fi
    echo ""
  else
    for idx in "${detected_indices[@]}"; do
      add_target_unique "${KNOWN_AGENT_DIRS[$((idx - 1))]}"
    done
  fi
fi

# Step 4: Install Method (Symlink vs Copy)
if [[ -z "$METHOD" ]]; then
  if [[ $CAN_PROMPT -eq 1 ]]; then
    if [[ -n "$LOCAL_REPO" ]]; then
      if [[ "$EDITION" == "ru" ]]; then
        echo "${BOLD}4. Способ установки:${RESET}"
        echo "   ${AMBER}1)${RESET} ${BOLD}Симлинк${RESET} ${DIM}(рекомендуется — git pull обновляет скиллы автоматически)${RESET}"
        echo "   ${AMBER}2)${RESET} ${BOLD}Копия${RESET}   ${DIM}(автономные файлы, клон можно удалить)${RESET}"
        ans="$(prompt_line "   Выбор [1/2] (default 1): ")"
      else
        echo "${BOLD}4. Install method:${RESET}"
        echo "   ${AMBER}1)${RESET} ${BOLD}Symlink${RESET} ${DIM}(recommended — git pull updates every skill in place)${RESET}"
        echo "   ${AMBER}2)${RESET} ${BOLD}Copy${RESET}    ${DIM}(standalone files, safe to delete the clone afterwards)${RESET}"
        ans="$(prompt_line "   Pick [1/2] (default 1): ")"
      fi
      case "${ans:-1}" in
        1|link|symlink) METHOD="link" ;;
        2|copy)         METHOD="copy" ;;
        *) echo "${RED}error:${RESET} invalid method '$ans'" >&2; exit 2 ;;
      esac
    else
      if [[ "$EDITION" == "ru" ]]; then
        echo "${BOLD}4. Способ установки:${RESET}"
        echo "   ${AMBER}1)${RESET} ${BOLD}Копия${RESET}   ${DIM}(чистые файлы прямо в папки агентов, без лишних клонов)${RESET}"
        echo "   ${AMBER}2)${RESET} ${BOLD}Симлинк${RESET} ${DIM}(клонирует репо в ~/.local/share/dopamine-talk для обновлений через git pull)${RESET}"
        ans="$(prompt_line "   Выбор [1/2] (default 1): ")"
      else
        echo "${BOLD}4. Install method:${RESET}"
        echo "   ${AMBER}1)${RESET} ${BOLD}Copy${RESET}    ${DIM}(clean standalone files directly in agent folders)${RESET}"
        echo "   ${AMBER}2)${RESET} ${BOLD}Symlink${RESET} ${DIM}(keeps managed clone in ~/.local/share/dopamine-talk for git pull updates)${RESET}"
        ans="$(prompt_line "   Pick [1/2] (default 1): ")"
      fi
      case "${ans:-1}" in
        1|copy)         METHOD="copy" ;;
        2|link|symlink) METHOD="link" ;;
        *) echo "${RED}error:${RESET} invalid method '$ans'" >&2; exit 2 ;;
      esac
    fi
    echo ""
  else
    METHOD="$([[ -n "$LOCAL_REPO" ]] && echo "link" || echo "copy")"
  fi
fi

# Step 5: Optional Always-On Rules File (AGENTS.md)
if [[ $INSTALL_RULES -eq 0 && $CAN_PROMPT -eq 1 ]]; then
  if [[ "$EDITION" == "ru" ]]; then
    ans="$(prompt_line "${BOLD}5. Скопировать компактные всегда-активные правила AGENTS.md в текущую папку? [y/N]: ${RESET}")"
  else
    ans="$(prompt_line "${BOLD}5. Also copy compact always-on AGENTS.md rules into current folder? [y/N]: ${RESET}")"
  fi
  case "$(lower "${ans:-n}")" in
    y|yes|д|да) INSTALL_RULES=1 ;;
  esac
  echo ""
fi

# Resolve source directory (local clone vs remote fetch)
SOURCE_ROOT="$LOCAL_REPO"
if [[ -z "$SOURCE_ROOT" ]]; then
  if [[ "$METHOD" == "link" ]]; then
    if ! command -v git >/dev/null 2>&1; then
      echo "${RED}error:${RESET} symlink install from remote requires 'git' (use --copy instead)" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$MANAGED_CLONE_DIR")"
    if [[ -d "$MANAGED_CLONE_DIR/.git" ]]; then
      echo "${DIM}Updating managed clone in ${MANAGED_CLONE_DIR}...${RESET}"
      git -C "$MANAGED_CLONE_DIR" pull --ff-only --quiet
    else
      echo "${DIM}Cloning ${REPO_SLUG} into ${MANAGED_CLONE_DIR}...${RESET}"
      git clone --depth 1 --quiet "$REPO_URL" "$MANAGED_CLONE_DIR"
    fi
    SOURCE_ROOT="$MANAGED_CLONE_DIR"
  else
    CLEANUP_TMP="$(mktemp -d)"
    echo "${DIM}Downloading ${REPO_SLUG}...${RESET}"
    if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
      curl -fsSL "$TARBALL_URL" | tar -xz -C "$CLEANUP_TMP"
      SOURCE_ROOT="$(find "$CLEANUP_TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    elif command -v git >/dev/null 2>&1; then
      git clone --depth 1 --quiet "$REPO_URL" "$CLEANUP_TMP/repo"
      SOURCE_ROOT="$CLEANUP_TMP/repo"
    else
      echo "${RED}error:${RESET} need either 'curl + tar' or 'git' to fetch ${REPO_SLUG}" >&2
      exit 1
    fi
  fi
fi

if [[ "$EDITION" == "ru" ]]; then
  SKILLS_SRC="$SOURCE_ROOT/skills-ru"
  RULES_SRC="$SOURCE_ROOT/docs/i18n/AGENTS.ru.md"
  EDITION_LABEL="RU (Русский)"
else
  SKILLS_SRC="$SOURCE_ROOT/skills"
  RULES_SRC="$SOURCE_ROOT/AGENTS.md"
  EDITION_LABEL="EN (Western)"
fi

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "${RED}error:${RESET} skills source directory not found: $SKILLS_SRC" >&2
  exit 1
fi

# Perform Installation
installed=0
skipped=0

echo "${BOLD}Installing ${CORAL}Dopamine Talk${RESET}${BOLD} [${EDITION_LABEL} · ${METHOD}]...${RESET}"
echo ""

for skill in "${SELECTED_SKILLS[@]}"; do
  src="$SKILLS_SRC/$skill"
  if [[ ! -f "$src/SKILL.md" ]]; then
    echo "  ${RED}✗${RESET} missing source skill: $src" >&2
    skipped=$((skipped + 1))
    continue
  fi

  for target in "${TARGETS[@]}"; do
    mkdir -p "$target"
    dst="$target/$skill"

    if [[ -L "$dst" || -e "$dst" ]]; then
      if [[ $FORCE -eq 1 ]]; then
        remove_entry "$dst"
      elif [[ -L "$dst" ]]; then
        # Safely replace existing dopamine-talk symlinks (even when switching EN <-> RU!)
        cur_link="$(readlink "$dst" 2>/dev/null || true)"
        if [[ "$cur_link" == *"dopamine-talk"* || "$cur_link" == *"dopamine-readme"* || "$cur_link" == *"dopamine-changelog"* ]]; then
          remove_entry "$dst"
        else
          echo "  ${AMBER}!${RESET} skip     $dst ${DIM}(symlink to unrelated path — pass --force to replace)${RESET}" >&2
          skipped=$((skipped + 1))
          continue
        fi
      else
        if [[ $CAN_PROMPT -eq 1 ]]; then
          existing_ed="$(detect_edition_from_file "$dst/SKILL.md")"
          ans="$(prompt_line "  ${AMBER}!${RESET} $dst already exists [${existing_ed}]. Overwrite? [Y/n]: ")"
          case "$(lower "${ans:-y}")" in
            y|yes|д|да) remove_entry "$dst" ;;
            *) skipped=$((skipped + 1)); continue ;;
          esac
        else
          echo "  ${AMBER}!${RESET} skip     $dst ${DIM}(already exists — pass --force to overwrite)${RESET}" >&2
          skipped=$((skipped + 1))
          continue
        fi
      fi
    fi

    if [[ "$METHOD" == "link" ]]; then
      if make_link "$src" "$dst"; then
        echo "  ${GREEN}✓${RESET} linked   $dst ${DIM}-> $(basename "$SKILLS_SRC")/$skill${RESET}"
        installed=$((installed + 1))
      else
        echo "  ${RED}✗${RESET} failed   could not symlink $dst (try --copy)" >&2
        skipped=$((skipped + 1))
      fi
    else
      cp -R "$src" "$dst"
      echo "  ${GREEN}✓${RESET} copied   $dst ${DIM}[${EDITION_LABEL}]${RESET}"
      installed=$((installed + 1))
    fi
  done
done

if [[ $INSTALL_RULES -eq 1 ]]; then
  mkdir -p "$RULES_DIR"
  rules_dst="${RULES_DIR%/}/AGENTS.md"
  if [[ -e "$rules_dst" && $FORCE -eq 0 ]]; then
    if [[ $CAN_PROMPT -eq 1 ]]; then
      ans="$(prompt_line "  ${AMBER}!${RESET} $rules_dst already exists. Overwrite? [y/N]: ")"
      case "$(lower "${ans:-n}")" in
        y|yes|д|да) cp "$RULES_SRC" "$rules_dst"; echo "  ${GREEN}✓${RESET} rules    $rules_dst" ;;
        *) echo "  ${DIM}skipped  $rules_dst${RESET}" ;;
      esac
    else
      echo "  ${AMBER}!${RESET} skip     $rules_dst ${DIM}(already exists — pass --force to overwrite)${RESET}" >&2
    fi
  else
    cp "$RULES_SRC" "$rules_dst"
    echo "  ${GREEN}✓${RESET} rules    $rules_dst ${DIM}[${EDITION_LABEL}]${RESET}"
  fi
fi

echo ""
if [[ $installed -gt 0 ]]; then
  if [[ "$EDITION" == "ru" ]]; then
    echo "${GREEN}${BOLD}Готово!${RESET} Установлено ${BOLD}${installed}${RESET} записей (${EDITION_LABEL})."
    echo "${DIM}Триггеры: «дофаминовое общение», «дофаминовый ридми», «дофаминовый чейнджлог».${RESET}"
    echo "${DIM}Переключить на английскую версию в любой момент: ./install.sh --lang en --force${RESET}"
  else
    echo "${GREEN}${BOLD}Done!${RESET} Installed ${BOLD}${installed}${RESET} skill target(s) (${EDITION_LABEL})."
    echo "${DIM}Triggers: \"dopamine-talk\", \"dopamine-readme\", \"dopamine-changelog\".${RESET}"
    echo "${DIM}Switch editions anytime: ./install.sh --lang ru --force  |  Check status: ./install.sh --status${RESET}"
  fi
fi

if [[ $skipped -gt 0 ]]; then
  echo "${AMBER}${skipped} target(s) skipped — see messages above.${RESET}" >&2
  exit 1
fi
echo ""
