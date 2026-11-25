#!/usr/bin/env bash
# Dopamine Talk Interactive Installer
# Supports both local clones (`./install.sh`) and one-line remote installs:
#   curl -fsSL https://dopamine.annenkov.me/install.sh | bash
#   curl -fsSL https://dopamine.annenkov.me/install.sh | bash -s -- --lang ru
#
# Quick non-interactive examples:
#   ./install.sh --lang en --all-agents --yes
#   ./install.sh --lang ru --claude --codex --yes
#   ./install.sh --lang ru --skills talk,readme --claude --force --yes
#   ./install.sh --status
#   ./install.sh --uninstall --yes
#
# Compatible with Bash 3.2+ (macOS, Linux, WSL, Windows Git Bash). Zero dependencies.

set -euo pipefail

REPO_SLUG="AnnenkovLabs/dopamine-talk"
REPO_URL="https://github.com/${REPO_SLUG}.git"
TARBALL_URL="https://github.com/${REPO_SLUG}/archive/refs/heads/main.tar.gz"
SHORT_URL="https://dopamine.annenkov.me/install.sh"
MANAGED_CLONE_DIR="${DOPAMINE_HOME:-$HOME/.local/share/dopamine-talk}"

MARKER_START="<!-- dopamine-talk:start -->"
MARKER_END="<!-- dopamine-talk:end -->"

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
MODE="install"        # install | uninstall | list | status
EDITION=""            # en | ru
METHOD=""             # link | copy
ASSUME_YES=0
FORCE=0
GLOBAL_RULES="ask"    # ask | yes | no (always-on global agent rules)
INSTALL_LOCAL_RULES=0
RULES_DIR="."
SELECTED_SKILLS=()
TARGETS=()
CLEANUP_TMP=""

trap 'if [[ -n "${CLEANUP_TMP:-}" && -d "${CLEANUP_TMP:-}" ]]; then rm -rf "$CLEANUP_TMP"; fi' EXIT

print_help() {
  cat <<'EOF'
Dopamine Talk Installer — install EN or RU skills + always-on rules across 20+ AI agents.

Usage:
  curl -fsSL https://dopamine.annenkov.me/install.sh | bash
  ./install.sh [options] [skill...]

Options:
  --lang en|ru          Skill edition:
                          en = Western English (sharp, zero AI slop)
                          ru = Native Russian (живой русский, без Runglish)
  --skills LIST         Comma-separated skills: all, talk, readme, changelog
                        (or full names: dopamine-talk, dopamine-readme, dopamine-changelog)
  --link                Install via symlinks (auto-updates on git pull)
  --copy                Install standalone copies
  --global-rules        Enable always-on global rules for selected agents (default with --yes)
  --no-global-rules     Install SKILL.md files only (do not touch global CLAUDE.md/AGENTS.md)
  --rules [DIR]         Also upsert a marked AGENTS.md block into project DIR (default: .)
                        With --uninstall, remove that project AGENTS.md block again
  --force, -f           Replace any existing target, even an unrelated same-named directory
                        (Dopamine Talk copies are upgraded automatically without it)
  -y, --yes             Skip interactive prompts and use detected/specified defaults
  --status              Show installed edition (EN/RU), skills, and active always-on rules
  --list                List available skills across EN and RU editions
  --uninstall           Remove selected skills and their always-on rule blocks
                        (combine with target flags; partial --skills keeps pack rules)
  -h, --help            Show this help message

Target Agent Shortcuts:
  --agents              ~/.agents/skills (Antigravity, OpenCode, Cline, Pi, Command Code)
  --claude              ~/.claude/skills (Claude Code)
  --codex               ~/.codex/skills (OpenAI Codex)
  --gemini              ~/.gemini/config/skills (Gemini CLI / Antigravity)
  --antigravity         ~/.agents/skills + ~/.gemini/config/skills
  --cursor              ~/.cursor/skills (Cursor)
  --windsurf            ~/.codeium/windsurf/skills (Windsurf)
  --copilot             ~/.copilot/skills (GitHub Copilot)
  --opencode            ~/.config/opencode/skills (OpenCode)
  --kiro                ~/.kiro/skills (Kiro)
  --dir PATH            Install into any custom skills directory
  --all-agents          Universal + Claude Code + Codex + Gemini CLI + Cursor + Windsurf + Copilot
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
      _skills_seen=0
      for _p in "${_parts[@]}"; do
        _p="$(printf '%s' "$_p" | tr -d '[:space:]')"
        [[ -z "$_p" ]] && continue
        _skills_seen=1
        _norm="$(normalize_skill_name "$_p")" || { echo "${RED}error:${RESET} unknown skill '$_p'" >&2; exit 2; }
        if [[ "$_norm" == "ALL" ]]; then
          add_skill_unique "dopamine-talk"
          add_skill_unique "dopamine-readme"
          add_skill_unique "dopamine-changelog"
        else
          add_skill_unique "$_norm"
        fi
      done
      [[ $_skills_seen -eq 1 ]] || { echo "${RED}error:${RESET} --skills requires at least one skill" >&2; exit 2; }
      shift ;;
    --agents)      add_target_unique "$HOME/.agents/skills" ;;
    --claude)      add_target_unique "$HOME/.claude/skills" ;;
    --codex)       add_target_unique "$HOME/.codex/skills" ;;
    --gemini)      add_target_unique "$HOME/.gemini/config/skills" ;;
    --antigravity) add_target_unique "$HOME/.agents/skills"; add_target_unique "$HOME/.gemini/config/skills" ;;
    --cursor)      add_target_unique "$HOME/.cursor/skills" ;;
    --windsurf)    add_target_unique "$HOME/.codeium/windsurf/skills" ;;
    --copilot)     add_target_unique "$HOME/.copilot/skills" ;;
    --opencode)    add_target_unique "$HOME/.config/opencode/skills" ;;
    --kiro)        add_target_unique "$HOME/.kiro/skills" ;;
    --all-agents)
      add_target_unique "$HOME/.agents/skills"
      add_target_unique "$HOME/.claude/skills"
      add_target_unique "$HOME/.codex/skills"
      add_target_unique "$HOME/.gemini/config/skills"
      add_target_unique "$HOME/.cursor/skills"
      add_target_unique "$HOME/.codeium/windsurf/skills"
      add_target_unique "$HOME/.copilot/skills" ;;
    --dir)
      [[ $# -ge 2 && -n "$2" ]] || { echo "${RED}error:${RESET} --dir requires a non-empty directory path" >&2; exit 2; }
      add_target_unique "$2"
      shift ;;
    --link|--symlink)  METHOD="link" ;;
    --copy)            METHOD="copy" ;;
    --global-rules)    GLOBAL_RULES="yes" ;;
    --no-global-rules) GLOBAL_RULES="no" ;;
    --rules)
      INSTALL_LOCAL_RULES=1
      if [[ $# -ge 2 && "$2" != -* ]]; then
        [[ -n "$2" ]] || { echo "${RED}error:${RESET} --rules requires a non-empty directory path" >&2; exit 2; }
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
  if grep -q 'Деактивирует\|Пишет и переписывает\|Включает режим\|Всегда активные правила\|Пять главных правил' "$md" 2>/dev/null; then
    printf 'RU'
  else
    printf 'EN'
  fi
}

# Detect the edition from the managed block only, so unrelated Russian text in a
# user's CLAUDE.md/AGENTS.md cannot make an EN install look like RU.
detect_edition_from_block() {
  local md="$1"
  awk -v s="$MARKER_START" -v e="$MARKER_END" -v md="$md" '
    BEGIN {
      n = 0
      while ((getline line < md) > 0) {
        sub(/\r$/, "", line)
        lines[++n] = line
      }
      close(md)

      pending = 0
      pairs = 0
      for (i = 1; i <= n; i++) {
        if (lines[i] == s) pending = i
        else if (pending && lines[i] == e) {
          pairs++
          start[pairs] = pending
          end[pairs] = i
          pending = 0
        }
      }
      if (pairs == 0) { print "unknown"; exit }

      found = 0
      for (i = start[1] + 1; i < end[1]; i++) {
        if (lines[i] ~ /Деактивирует|Пишет и переписывает|Включает режим|Всегда активные правила|Пять главных правил/) {
          found = 1
          break
        }
      }
      print (found ? "RU" : "EN")
      exit
    }
  ' "$md"
}

# Preserve the mode of a file we rewrite, or use 0644 for a new file. mktemp
# creates 0600, and a plain mv would silently make CLAUDE.md/AGENTS.md private.
set_file_mode() {
  local src="$1"
  local dst="$2"
  local mode=""
  if [[ -e "$src" ]]; then
    mode="$(stat -c '%a' "$src" 2>/dev/null || stat -f '%Lp' "$src" 2>/dev/null || true)"
  fi
  if [[ -n "$mode" ]]; then
    chmod "$mode" "$dst" 2>/dev/null || true
  else
    chmod 644 "$dst" 2>/dev/null || true
  fi
}

# True when the file contains at least one complete start...end marker pair in
# that order. A lone or inverted marker must never be treated as a block.
has_ordered_marked_block() {
  local dst="$1"
  [[ -f "$dst" ]] || return 1
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    { line = $0; sub(/\r$/, "", line) }
    line == s { pending = 1; next }
    pending && line == e { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$dst"
}

# Portable POSIX awk helpers for marker-scoped always-on global rules.
# User content outside complete marker pairs is preserved; extra complete blocks
# are collapsed into one, and malformed markers never delete the text that
# follows them.
upsert_marked_block() {
  local dst="$1"
  local src="$2"
  mkdir -p "$(dirname "$dst")"
  local tmp_out
  tmp_out="$(mktemp)"

  if has_ordered_marked_block "$dst"; then
    awk -v s="$MARKER_START" -v e="$MARKER_END" -v rf="$src" -v dst="$dst" '
      BEGIN {
        n = 0
        while ((getline line < dst) > 0) lines[++n] = line
        close(dst)

        eol = ""
        for (i = 1; i <= n; i++) {
          if (lines[i] ~ /\r$/) { eol = "\r"; break }
        }

        inside = 0
        pairs = 0
        for (i = 1; i <= n; i++) {
          line = lines[i]
          sub(/\r$/, "", line)
          if (line == s) inside = i
          else if (inside && line == e) {
            pairs++
            start[pairs] = inside
            end[pairs] = i
            inside = 0
          }
        }

        # Keep the first complete block (rewritten below) and collapse later ones.
        for (p = 2; p <= pairs; p++)
          for (i = start[p]; i <= end[p]; i++) drop[i] = 1

        for (i = 1; i <= n; i++) {
          if (pairs > 0 && i == start[1]) {
            print s eol
            while ((getline line < rf) > 0) {
              sub(/\r$/, "", line)
              print line eol
            }
            close(rf)
            print e eol
            i = end[1]
            continue
          }
          if (drop[i]) continue
          print lines[i]
        }
        exit
      }
    ' "$dst" > "$tmp_out"
  elif [[ -f "$dst" ]] && grep -Fq "$MARKER_START" "$dst" 2>/dev/null; then
    # A lone start marker (interrupted or hand-edited install): put the fresh
    # block where the orphan started, keep every line after it as user content,
    # and drop only the duplicate start markers so they cannot pair with the new
    # end marker and swallow user text later.
    awk -v s="$MARKER_START" -v e="$MARKER_END" -v rf="$src" -v dst="$dst" '
      BEGIN {
        n = 0
        eol = ""
        while ((getline raw < dst) > 0) {
          if (raw ~ /\r$/) eol = "\r"
          sub(/\r$/, "", raw)
          lines[++n] = raw
        }
        close(dst)

        replaced = 0
        for (i = 1; i <= n; i++) {
          if (lines[i] == s) {
            if (!replaced) {
              print s eol
              while ((getline line < rf) > 0) {
                sub(/\r$/, "", line)
                print line eol
              }
              close(rf)
              print e eol
              replaced = 1
            }
            continue
          }
          print lines[i] eol
        }
        exit
      }
    ' "$dst" > "$tmp_out"
  else
    if [[ -f "$dst" && -s "$dst" ]]; then
      cat "$dst" > "$tmp_out"
      printf '\n\n' >> "$tmp_out"
    fi
    printf '%s\n' "$MARKER_START" >> "$tmp_out"
    cat "$src" >> "$tmp_out"
    printf '\n%s\n' "$MARKER_END" >> "$tmp_out"
  fi

  set_file_mode "$dst" "$tmp_out"
  mv "$tmp_out" "$dst"
}

remove_marked_block() {
  local dst="$1"
  [[ -f "$dst" ]] || return 1
  has_ordered_marked_block "$dst" || return 1
  local tmp_out
  tmp_out="$(mktemp)"
  awk -v s="$MARKER_START" -v e="$MARKER_END" -v dst="$dst" '
    BEGIN {
      n = 0
      while ((getline line < dst) > 0) lines[++n] = line
      close(dst)

      inside = 0
      pairs = 0
      for (i = 1; i <= n; i++) {
        line = lines[i]
        sub(/\r$/, "", line)
        if (line == s) inside = i
        else if (inside && line == e) {
          pairs++
          start[pairs] = inside
          end[pairs] = i
          inside = 0
        }
      }
      for (p = 1; p <= pairs; p++)
        for (i = start[p]; i <= end[p]; i++) drop[i] = 1
      for (i = 1; i <= n; i++) if (!drop[i]) print lines[i]
      exit
    }
  ' "$dst" > "$tmp_out"
  if [[ -z "$(tr -d '[:space:]' < "$tmp_out")" ]]; then
    rm -f "$tmp_out" "$dst"
  else
    set_file_mode "$dst" "$tmp_out"
    mv "$tmp_out" "$dst"
  fi
  return 0
}

# A directory is a verified Dopamine Talk install only when its SKILL.md declares
# the expected skill name. This lets a repeat non-interactive install upgrade its
# own copy while refusing to silently delete a same-named unrelated directory.
is_dopamine_skill_dir() {
  local dir="$1"
  local skill="$2"
  [[ -f "$dir/SKILL.md" ]] || return 1
  grep -Eq "^name:[[:space:]]*${skill}[[:space:]]*$" "$dir/SKILL.md" 2>/dev/null
}

# A file is ours only when it carries the exact signature written by this
# installer. A same-named user file is never deleted on uninstall.
is_owned_rule_file() {
  local f="$1"
  [[ -L "$f" ]] && return 1
  [[ -f "$f" ]] || return 1
  case "$f" in
    "$HOME/.cursor/rules/dopamine-talk.mdc")
      grep -Fq 'description: Dopamine Talk' "$f" 2>/dev/null &&
        grep -Fq 'alwaysApply: true' "$f" 2>/dev/null ;;
    "$HOME/.kiro/steering/dopamine-talk.md"|"$HOME/.gemini/config/rules/dopamine-talk.md")
      grep -Fq '# Dopamine Talk' "$f" 2>/dev/null &&
        { grep -Fq '## Core Rules' "$f" 2>/dev/null ||
          grep -Fq '## Пять главных правил' "$f" 2>/dev/null; } ;;
    *) return 1 ;;
  esac
}

write_cursor_mdc() {
  local dst="$1"
  local src="$2"
  mkdir -p "$(dirname "$dst")"
  {
    printf '%s\n' '---'
    printf '%s\n' 'description: Dopamine Talk — Always-On Communication Rules'
    printf '%s\n' 'alwaysApply: true'
    printf '%s\n\n' '---'
    cat "$src"
    printf '\n'
  } > "$dst"
}

KNOWN_AGENT_LABELS=(
  "Universal (~/.agents/skills — Antigravity, OpenCode, Cline, Pi)"
  "Claude Code (~/.claude/skills)"
  "OpenAI Codex (~/.codex/skills)"
  "Gemini CLI / Antigravity (~/.gemini/config/skills)"
  "Cursor (~/.cursor/skills)"
  "Windsurf (~/.codeium/windsurf/skills)"
  "GitHub Copilot (~/.copilot/skills)"
  "OpenCode (~/.config/opencode/skills)"
  "Kiro (~/.kiro/skills)"
)
KNOWN_AGENT_DIRS=(
  "$HOME/.agents/skills"
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.gemini/config/skills"
  "$HOME/.cursor/skills"
  "$HOME/.codeium/windsurf/skills"
  "$HOME/.copilot/skills"
  "$HOME/.config/opencode/skills"
  "$HOME/.kiro/skills"
)
KNOWN_AGENT_PROBES=(
  "$HOME/.agents"
  "$HOME/.claude"
  "$HOME/.codex"
  "$HOME/.gemini"
  "$HOME/.cursor"
  "$HOME/.codeium"
  "$HOME/.copilot"
  "$HOME/.config/opencode"
  "$HOME/.kiro"
)

# Standalone rule files owned 100% by Dopamine Talk
KNOWN_OWNED_RULE_FILES=(
  "$HOME/.gemini/config/rules/dopamine-talk.md"
  "$HOME/.cursor/rules/dopamine-talk.mdc"
  "$HOME/.kiro/steering/dopamine-talk.md"
)
# Shared global rule files where we only touch <!-- dopamine-talk:start/end -->
KNOWN_MARKED_RULE_FILES=(
  "$HOME/.agents/AGENTS.md"
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.codex/AGENTS.md"
  "$HOME/.gemini/GEMINI.md"
  "$HOME/.codeium/windsurf/memories/global_rules.md"
  "$HOME/.copilot/copilot-instructions.md"
  "$HOME/.config/opencode/AGENTS.md"
)

# Write an installer-owned rule file only when it is missing or carries our
# signature. A foreign same-named file is preserved unless --force is explicit.
install_owned_rule() {
  local dst="$1"
  local src="$2"
  local kind="$3"
  if [[ -e "$dst" || -L "$dst" ]]; then
    if ! is_owned_rule_file "$dst"; then
      if [[ $FORCE -ne 1 ]]; then
        echo "  ${AMBER}!${RESET} skip     $dst ${DIM}(unrelated file — pass --force to replace)${RESET}" >&2
        return 1
      fi
      remove_entry "$dst"
    fi
  fi
  mkdir -p "$(dirname "$dst")"
  case "$kind" in
    cursor) write_cursor_mdc "$dst" "$src" ;;
    copy)   cp "$src" "$dst" ;;
    *)      return 1 ;;
  esac
}

install_global_rule_for_target() {
  local target="$1"
  local rules_src="$2"
  local ed_label="$3"
  case "$target" in
    "$HOME/.agents/skills")
      upsert_marked_block "$HOME/.agents/AGENTS.md" "$rules_src"
      echo "  ${GREEN}✓${RESET} rule     $HOME/.agents/AGENTS.md ${DIM}[always-on · ${ed_label}]${RESET}"
      return 0 ;;
    "$HOME/.claude/skills")
      upsert_marked_block "$HOME/.claude/CLAUDE.md" "$rules_src"
      echo "  ${GREEN}✓${RESET} rule     $HOME/.claude/CLAUDE.md ${DIM}[always-on · ${ed_label}]${RESET}"
      return 0 ;;
    "$HOME/.codex/skills")
      upsert_marked_block "$HOME/.codex/AGENTS.md" "$rules_src"
      echo "  ${GREEN}✓${RESET} rule     $HOME/.codex/AGENTS.md ${DIM}[always-on · ${ed_label}]${RESET}"
      return 0 ;;
    "$HOME/.gemini/config/skills")
      upsert_marked_block "$HOME/.gemini/GEMINI.md" "$rules_src"
      echo "  ${GREEN}✓${RESET} rule     $HOME/.gemini/GEMINI.md ${DIM}[always-on · ${ed_label}]${RESET}"
      if install_owned_rule "$HOME/.gemini/config/rules/dopamine-talk.md" "$rules_src" copy; then
        echo "  ${GREEN}✓${RESET} rule     $HOME/.gemini/config/rules/dopamine-talk.md ${DIM}[always-on · ${ed_label}]${RESET}"
      fi
      return 0 ;;
    "$HOME/.cursor/skills")
      if install_owned_rule "$HOME/.cursor/rules/dopamine-talk.mdc" "$rules_src" cursor; then
        echo "  ${GREEN}✓${RESET} rule     $HOME/.cursor/rules/dopamine-talk.mdc ${DIM}[alwaysApply · ${ed_label}]${RESET}"
        return 0
      fi
      return 1 ;;
    "$HOME/.codeium/windsurf/skills")
      upsert_marked_block "$HOME/.codeium/windsurf/memories/global_rules.md" "$rules_src"
      echo "  ${GREEN}✓${RESET} rule     $HOME/.codeium/windsurf/memories/global_rules.md ${DIM}[always-on · ${ed_label}]${RESET}"
      return 0 ;;
    "$HOME/.copilot/skills")
      upsert_marked_block "$HOME/.copilot/copilot-instructions.md" "$rules_src"
      echo "  ${GREEN}✓${RESET} rule     $HOME/.copilot/copilot-instructions.md ${DIM}[always-on · ${ed_label}]${RESET}"
      return 0 ;;
    "$HOME/.config/opencode/skills")
      upsert_marked_block "$HOME/.config/opencode/AGENTS.md" "$rules_src"
      echo "  ${GREEN}✓${RESET} rule     $HOME/.config/opencode/AGENTS.md ${DIM}[always-on · ${ed_label}]${RESET}"
      return 0 ;;
    "$HOME/.kiro/skills")
      if install_owned_rule "$HOME/.kiro/steering/dopamine-talk.md" "$rules_src" copy; then
        echo "  ${GREEN}✓${RESET} rule     $HOME/.kiro/steering/dopamine-talk.md ${DIM}[always-on · ${ed_label}]${RESET}"
        return 0
      fi
      return 1 ;;
  esac
  return 1
}

# Remove only the always-on rule owned by one selected agent target. Used by
# targeted uninstalls so `--uninstall --claude` also cleans CLAUDE.md instead of
# leaving an active rule block behind.
remove_global_rule_for_target() {
  local target="$1"
  local rf=""
  case "$target" in
    "$HOME/.agents/skills")                   rf="$HOME/.agents/AGENTS.md" ;;
    "$HOME/.claude/skills")                   rf="$HOME/.claude/CLAUDE.md" ;;
    "$HOME/.codex/skills")                    rf="$HOME/.codex/AGENTS.md" ;;
    "$HOME/.gemini/config/skills")            rf="$HOME/.gemini/GEMINI.md" ;;
    "$HOME/.codeium/windsurf/skills")         rf="$HOME/.codeium/windsurf/memories/global_rules.md" ;;
    "$HOME/.copilot/skills")                  rf="$HOME/.copilot/copilot-instructions.md" ;;
    "$HOME/.config/opencode/skills")          rf="$HOME/.config/opencode/AGENTS.md" ;;
    "$HOME/.cursor/skills")
      if is_owned_rule_file "$HOME/.cursor/rules/dopamine-talk.mdc"; then
        rm -f "$HOME/.cursor/rules/dopamine-talk.mdc"
        echo "  ${GREEN}✓${RESET} removed  $HOME/.cursor/rules/dopamine-talk.mdc"
        return 0
      fi
      return 1 ;;
    "$HOME/.kiro/skills")
      if is_owned_rule_file "$HOME/.kiro/steering/dopamine-talk.md"; then
        rm -f "$HOME/.kiro/steering/dopamine-talk.md"
        echo "  ${GREEN}✓${RESET} removed  $HOME/.kiro/steering/dopamine-talk.md"
        return 0
      fi
      return 1 ;;
  esac

  [[ -n "$rf" ]] || return 1
  local removed=0
  if remove_marked_block "$rf"; then
    echo "  ${GREEN}✓${RESET} cleaned  $rf"
    removed=1
  fi
  if [[ "$target" == "$HOME/.gemini/config/skills" ]] && is_owned_rule_file "$HOME/.gemini/config/rules/dopamine-talk.md"; then
    rm -f "$HOME/.gemini/config/rules/dopamine-talk.md"
    echo "  ${GREEN}✓${RESET} removed  $HOME/.gemini/config/rules/dopamine-talk.md"
    removed=1
  fi
  [[ $removed -eq 1 ]]
}

# --- MODE: STATUS ---
if [[ "$MODE" == "status" ]]; then
  echo ""
  echo "${BOLD}${CORAL}Dopamine Talk — Installed Status${RESET}"
  echo "${DIM}Checking skills and active always-on rules...${RESET}"
  echo ""
  found_any=0
  for i in "${!KNOWN_AGENT_DIRS[@]}"; do
    dir="${KNOWN_AGENT_DIRS[$i]}"
    [[ -d "$dir" ]] || continue
    for s in dopamine-talk dopamine-readme dopamine-changelog; do
      p="$dir/$s"
      if [[ -L "$p" ]] || { [[ -d "$p" ]] && is_dopamine_skill_dir "$p" "$s"; }; then
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

  for rf in "${KNOWN_OWNED_RULE_FILES[@]}"; do
    if is_owned_rule_file "$rf"; then
      found_any=1
      ed="$(detect_edition_from_file "$rf")"
      printf '  %s✓%s %-20s %s[%s · always-on]%s  %s\n' "$GREEN" "$RESET" "global-rule" "$CYAN" "$ed" "$RESET" "$rf"
    fi
  done
  for rf in "${KNOWN_MARKED_RULE_FILES[@]}"; do
    if has_ordered_marked_block "$rf"; then
      found_any=1
      ed="$(detect_edition_from_block "$rf")"
      printf '  %s✓%s %-20s %s[%s · always-on]%s  %s\n' "$GREEN" "$RESET" "global-rule" "$CYAN" "$ed" "$RESET" "$rf"
    fi
  done

  if [[ $found_any -eq 0 ]]; then
    echo "  ${DIM}No Dopamine Talk skills or global rules currently installed.${RESET}"
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
  printf '    %-22s %s\n' "dopamine-talk"      "skills/dopamine-talk       (sharp dialogue, zero caveats or AI slop)"
  printf '    %-22s %s\n' "dopamine-readme"    "skills/dopamine-readme     (5-second visual GitHub showcases)"
  printf '    %-22s %s\n' "dopamine-changelog" "skills/dopamine-changelog  (user-impact f'(x) release notes)"
  echo ""
  echo "  ${BOLD}Русский (Оригинальная версия — skills-ru/)${RESET}"
  printf '    %-22s %s\n' "dopamine-talk"      "skills-ru/dopamine-talk       (живое общение без духоты и Runglish)"
  printf '    %-22s %s\n' "dopamine-readme"    "skills-ru/dopamine-readme     (витрины README под правило 5 секунд)"
  printf '    %-22s %s\n' "dopamine-changelog" "skills-ru/dopamine-changelog  (понятные чейнджлоги и точные CVE)"
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
  elif [[ -e "$target" ]]; then
    rm -f "$target"
  fi
}

# --- MODE: UNINSTALL ---
if [[ "$MODE" == "uninstall" ]]; then
  explicit_targets=0
  if [[ ${#TARGETS[@]} -gt 0 ]]; then
    explicit_targets=1
  else
    for d in "${KNOWN_AGENT_DIRS[@]}"; do
      add_target_unique "$d"
    done
  fi

  explicit_skills=0
  if [[ ${#SELECTED_SKILLS[@]} -gt 0 ]]; then
    explicit_skills=1
  else
    SELECTED_SKILLS=("dopamine-talk" "dopamine-readme" "dopamine-changelog")
  fi

  echo ""
  echo "${BOLD}${CORAL}Uninstalling Dopamine Talk...${RESET}"
  removed=0
  for dir in "${TARGETS[@]}"; do
    [[ -d "$dir" ]] || continue
    for s in "${SELECTED_SKILLS[@]}"; do
      p="$dir/$s"
      # Remove our symlink or a verified Dopamine Talk directory. An unrelated
      # file or a same-named directory with a foreign SKILL.md is not ours.
      if [[ -L "$p" ]]; then
        remove_entry "$p"
        echo "  ${GREEN}✓${RESET} removed  $p"
        removed=$((removed + 1))
      elif [[ -d "$p" ]] && is_dopamine_skill_dir "$p" "$s"; then
        remove_entry "$p"
        echo "  ${GREEN}✓${RESET} removed  $p"
        removed=$((removed + 1))
      fi
    done
  done

  # Rules are pack-wide: clean them only for a full pack uninstall (no --skills
  # filter, or all three skills selected). A partial skill removal keeps the
  # always-on rules so the remaining skills stay active.
  remove_rules=0
  if [[ $explicit_skills -eq 0 || ${#SELECTED_SKILLS[@]} -eq 3 ]]; then
    remove_rules=1
  fi

  if [[ $remove_rules -eq 1 ]]; then
    if [[ $explicit_targets -eq 0 ]]; then
      for rf in "${KNOWN_OWNED_RULE_FILES[@]}"; do
        if is_owned_rule_file "$rf"; then
          rm -f "$rf"
          echo "  ${GREEN}✓${RESET} removed  $rf"
          removed=$((removed + 1))
        fi
      done
      for rf in "${KNOWN_MARKED_RULE_FILES[@]}"; do
        if remove_marked_block "$rf"; then
          echo "  ${GREEN}✓${RESET} cleaned  $rf"
          removed=$((removed + 1))
        fi
      done
    else
      for dir in "${TARGETS[@]}"; do
        if remove_global_rule_for_target "$dir"; then
          removed=$((removed + 1))
        fi
      done
    fi
  fi

  # `--rules [DIR]` writes a marker block into a project AGENTS.md; honor the
  # same option on uninstall so that block can be removed again.
  if [[ $remove_rules -eq 1 && $INSTALL_LOCAL_RULES -eq 1 ]]; then
    rules_dst="${RULES_DIR%/}/AGENTS.md"
    if remove_marked_block "$rules_dst"; then
      echo "  ${GREEN}✓${RESET} cleaned  $rules_dst"
      removed=$((removed + 1))
    fi
  fi

  if [[ $removed -eq 0 ]]; then
    echo "  ${DIM}Nothing to remove in selected directories.${RESET}"
  fi
  echo ""
  exit 0
fi

# --- MODE: INSTALL ---
if [[ $CAN_PROMPT -eq 1 && ( -z "$EDITION" || ${#TARGETS[@]} -eq 0 || ${#SELECTED_SKILLS[@]} -eq 0 || -z "$METHOD" || "$GLOBAL_RULES" == "ask" ) ]]; then
  echo ""
  echo "${BOLD}${CORAL}━━━ Dopamine Talk Installer ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  if [[ -n "$LOCAL_REPO" ]]; then
    echo "${DIM}Source: local clone (${LOCAL_REPO})${RESET}"
  else
    echo "${DIM}Source: dopamine.annenkov.me / github.com/${REPO_SLUG}${RESET}"
  fi
  echo ""
fi

# Step 1: Choose Language Edition
if [[ -z "$EDITION" ]]; then
  default_ed="1"
  case "${LANG:-}${LC_ALL:-}" in
    *ru_*|*uk_*|*be_*|*kk_*) default_ed="2" ;;
  esac

  if [[ $CAN_PROMPT -eq 1 ]]; then
    echo "${BOLD}1. Choose edition / Выбери язык скиллов:${RESET}"
    echo "   ${AMBER}1)${RESET} ${BOLD}English${RESET}  ${DIM}(Western English — sharp, zero AI slop)${RESET}"
    echo "   ${AMBER}2)${RESET} ${BOLD}Русский${RESET}  ${DIM}(Живой русский — без духоты и англо-русской каши)${RESET}"
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
      echo "   ${AMBER}1)${RESET} ${BOLD}dopamine-talk${RESET}       ${DIM}— живое общение без духоты и оговорок${RESET}"
      echo "   ${AMBER}2)${RESET} ${BOLD}dopamine-readme${RESET}     ${DIM}— README на GitHub под правило 5 секунд${RESET}"
      echo "   ${AMBER}3)${RESET} ${BOLD}dopamine-changelog${RESET}  ${DIM}— понятные списки обновлений для людей${RESET}"
      ans="$(prompt_line "   Номера через запятую или Enter для всех трёх [all]: ")"
    else
      echo "${BOLD}2. Which skills do you want?${RESET}"
      echo "   ${AMBER}1)${RESET} ${BOLD}dopamine-talk${RESET}       ${DIM}— sharp, high-drive chat with zero caveats${RESET}"
      echo "   ${AMBER}2)${RESET} ${BOLD}dopamine-readme${RESET}     ${DIM}— 5-second visual GitHub showcases${RESET}"
      echo "   ${AMBER}3)${RESET} ${BOLD}dopamine-changelog${RESET}  ${DIM}— user-impact release notes & CVE clarity${RESET}"
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
      echo "${BOLD}3. В какие агенты поставить? (найденные на компьютере отмечены зелёным)${RESET}"
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
      echo "   ${AMBER}10)${RESET} Свой путь к папке..."
      ans="$(prompt_line "   Номера через запятую, 'all' или Enter для [${default_agents}]: ")"
    else
      echo "   ${AMBER}10)${RESET} Custom directory path..."
      ans="$(prompt_line "   Numbers separated by commas, 'all', or Enter for [${default_agents}]: ")"
    fi
    ans="$(printf '%s' "${ans:-$default_agents}" | tr -d '[:space:]')"
    if [[ "$(lower "$ans")" == "all" ]]; then
      for i in 0 1 2 3 4 5 6; do add_target_unique "${KNOWN_AGENT_DIRS[$i]}"; done
    else
      IFS=',' read -r -a _picks <<< "$ans"
      for pk in "${_picks[@]}"; do
        case "$pk" in
          1|2|3|4|5|6|7|8|9) add_target_unique "${KNOWN_AGENT_DIRS[$((pk - 1))]}" ;;
          10)
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

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "${RED}error:${RESET} no install target selected (use --claude, --codex, --dir PATH, --all-agents, or an interactive pick)" >&2
  exit 2
fi

# Step 4: Always-On Global Rules (so the agent actually uses Dopamine Talk in every chat!)
if [[ "$GLOBAL_RULES" == "ask" ]]; then
  if [[ $CAN_PROMPT -eq 1 ]]; then
    if [[ "$EDITION" == "ru" ]]; then
      echo "${BOLD}4. Включить режим всегда по умолчанию?${RESET} ${DIM}(добавит компактный блок правил в CLAUDE.md / AGENTS.md / GEMINI.md — не трогая твои правила)${RESET}"
      ans="$(prompt_line "   Включить всегда по умолчанию? [Y/n]: ")"
    else
      echo "${BOLD}4. Enable always-on mode globally?${RESET} ${DIM}(appends a clean marked block to CLAUDE.md / AGENTS.md / GEMINI.md without touching your rules)${RESET}"
      ans="$(prompt_line "   Enable always-on mode? [Y/n]: ")"
    fi
    case "$(lower "${ans:-y}")" in
      n|no|н|нет) GLOBAL_RULES="no" ;;
      *)          GLOBAL_RULES="yes" ;;
    esac
    echo ""
  else
    GLOBAL_RULES="yes"
  fi
fi

# Step 5: Install Method (Symlink vs Copy)
if [[ -z "$METHOD" ]]; then
  if [[ $CAN_PROMPT -eq 1 && -n "$LOCAL_REPO" ]]; then
    if [[ "$EDITION" == "ru" ]]; then
      echo "${BOLD}5. Способ установки:${RESET}"
      echo "   ${AMBER}1)${RESET} ${BOLD}Симлинк${RESET} ${DIM}(рекомендуется — git pull обновляет скиллы автоматически)${RESET}"
      echo "   ${AMBER}2)${RESET} ${BOLD}Копия${RESET}   ${DIM}(автономные файлы)${RESET}"
      ans="$(prompt_line "   Выбор [1/2] (default 1): ")"
    else
      echo "${BOLD}5. Install method:${RESET}"
      echo "   ${AMBER}1)${RESET} ${BOLD}Symlink${RESET} ${DIM}(recommended — git pull updates every skill in place)${RESET}"
      echo "   ${AMBER}2)${RESET} ${BOLD}Copy${RESET}    ${DIM}(standalone files)${RESET}"
      ans="$(prompt_line "   Pick [1/2] (default 1): ")"
    fi
    case "${ans:-1}" in
      1|link|symlink) METHOD="link" ;;
      2|copy)         METHOD="copy" ;;
      *) echo "${RED}error:${RESET} invalid method '$ans'" >&2; exit 2 ;;
    esac
    echo ""
  else
    METHOD="$([[ -n "$LOCAL_REPO" ]] && echo "link" || echo "copy")"
  fi
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
  EDITION_LABEL="EN (English)"
fi

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "${RED}error:${RESET} skills source directory not found: $SKILLS_SRC" >&2
  exit 1
fi

# Perform Installation
installed=0
skipped=0
rules_installed=0

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

    if [[ -L "$dst" ]]; then
      if [[ $FORCE -eq 1 ]]; then
        remove_entry "$dst"
      else
        cur_link="$(readlink "$dst" 2>/dev/null || true)"
        if [[ "$cur_link" == *"dopamine-talk"* || "$cur_link" == *"dopamine-readme"* || "$cur_link" == *"dopamine-changelog"* ]] || is_dopamine_skill_dir "$dst" "$skill"; then
          remove_entry "$dst"
        else
          echo "  ${AMBER}!${RESET} skip     $dst ${DIM}(symlink to unrelated path — pass --force to replace)${RESET}" >&2
          skipped=$((skipped + 1))
          continue
        fi
      fi
    elif [[ -e "$dst" ]]; then
      if [[ $FORCE -eq 1 ]]; then
        remove_entry "$dst"
      elif [[ $CAN_PROMPT -eq 1 ]]; then
        existing_ed="$(detect_edition_from_file "$dst/SKILL.md")"
        ans="$(prompt_line "  ${AMBER}!${RESET} $dst already exists [${existing_ed}]. Overwrite? [Y/n]: ")"
        case "$(lower "${ans:-y}")" in
          y|yes|д|да) remove_entry "$dst" ;;
          *) skipped=$((skipped + 1)); continue ;;
        esac
      elif is_dopamine_skill_dir "$dst" "$skill"; then
        remove_entry "$dst"
      else
        echo "  ${AMBER}!${RESET} skip     $dst ${DIM}(exists and is not a verified Dopamine Talk install — pass --force to replace)${RESET}" >&2
        skipped=$((skipped + 1))
        continue
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

if [[ "$GLOBAL_RULES" == "yes" && -f "$RULES_SRC" ]]; then
  echo ""
  for target in "${TARGETS[@]}"; do
    if install_global_rule_for_target "$target" "$RULES_SRC" "$EDITION_LABEL"; then
      rules_installed=$((rules_installed + 1))
    fi
  done
fi

if [[ $INSTALL_LOCAL_RULES -eq 1 && -f "$RULES_SRC" ]]; then
  mkdir -p "$RULES_DIR"
  rules_dst="${RULES_DIR%/}/AGENTS.md"
  upsert_marked_block "$rules_dst" "$RULES_SRC"
  echo "  ${GREEN}✓${RESET} rules    $rules_dst ${DIM}[${EDITION_LABEL}]${RESET}"
fi

echo ""
if [[ $installed -gt 0 || $rules_installed -gt 0 ]]; then
  if [[ "$EDITION" == "ru" ]]; then
    echo "${GREEN}${BOLD}Готово!${RESET} Установлено скиллов: ${BOLD}${installed}${RESET}, глобальных правил: ${BOLD}${rules_installed}${RESET} (${EDITION_LABEL})."
    echo "${DIM}Открой новый чат в агенте — режим уже активен. Триггеры: «дофаминовое общение», «дофаминовый ридми», «дофаминовый чейнджлог».${RESET}"
    echo "${DIM}Проверка: curl -fsSL ${SHORT_URL} | bash -s -- --status  |  Удалить: ... --uninstall${RESET}"
  else
    echo "${GREEN}${BOLD}Done!${RESET} Installed ${BOLD}${installed}${RESET} skill(s) and ${BOLD}${rules_installed}${RESET} always-on rule target(s) (${EDITION_LABEL})."
    echo "${DIM}Start a new chat — Dopamine Talk is active immediately. Triggers: \"dopamine-talk\", \"dopamine-readme\", \"dopamine-changelog\".${RESET}"
    echo "${DIM}Status: curl -fsSL ${SHORT_URL} | bash -s -- --status  |  Uninstall: ... --uninstall${RESET}"
  fi
fi

if [[ $skipped -gt 0 ]]; then
  echo "${AMBER}${skipped} target(s) skipped — see messages above.${RESET}" >&2
  exit 1
fi
echo ""
