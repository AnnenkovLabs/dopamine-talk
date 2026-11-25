#!/usr/bin/env bash
# Regression tests for install.sh: marker safety, status detection, overwrite
# protection, partial/targeted uninstall and project rules. Runs from the repo
# with a temporary HOME, a forced copy install and no network access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CHECKS=0
FAILED=0
ok()   { CHECKS=$((CHECKS + 1)); }
fail() { printf 'not ok - %s\n' "$*" >&2; FAILED=$((FAILED + 1)); }

new_home() {
  local name="$1"
  mkdir -p "$TMP/$name"
  printf '%s' "$TMP/$name"
}

run_installer() {
  local home="$1"
  shift
  HOME="$home" bash "$ROOT/install.sh" "$@"
}

assert_contains() {
  local file="$1" needle="$2" what="$3"
  if grep -Fq "$needle" "$file" 2>/dev/null; then ok; else fail "$what: expected '$needle' in $file"; fi
}

assert_not_contains() {
  local file="$1" needle="$2" what="$3"
  if [[ -f "$file" ]] && grep -Fq "$needle" "$file" 2>/dev/null; then fail "$what: unexpected '$needle' in $file"; else ok; fi
}

assert_count() {
  local file="$1" needle="$2" expected="$3" what="$4"
  local count=0
  if [[ -f "$file" ]]; then count="$(grep -cF "$needle" "$file" 2>/dev/null || true)"; fi
  if [[ "$count" == "$expected" ]]; then ok; else fail "$what: expected $expected '$needle', got $count in $file"; fi
}

assert_file() {
  local file="$1" what="$2"
  if [[ -f "$file" ]]; then ok; else fail "$what: missing file $file"; fi
}

assert_missing() {
  local file="$1" what="$2"
  if [[ -e "$file" ]]; then fail "$what: $file should not exist"; else ok; fi
}

# 1. Fresh install, status, idempotent reinstall and edition switch.
home="$(new_home fresh)"
run_installer "$home" --lang en --claude --yes --copy --no-global-rules >/dev/null 2>&1
for skill in dopamine-talk dopamine-readme dopamine-changelog; do
  assert_file "$home/.claude/skills/$skill/SKILL.md" "fresh install writes $skill"
done
assert_contains <(run_installer "$home" --status 2>/dev/null) "dopamine-talk" "status shows installed skill"
run_installer "$home" --lang ru --claude --yes --copy --no-global-rules >/dev/null 2>&1
assert_contains "$home/.claude/skills/dopamine-talk/SKILL.md" "name: dopamine-talk" "edition switch keeps skill name"
assert_contains <(run_installer "$home" --status 2>/dev/null) "RU" "status reports RU edition"

# 2. An unrelated same-named directory is not deleted without --force.
home="$(new_home unrelated)"
mkdir -p "$home/.claude/skills/dopamine-talk"
printf 'SENTINEL\n' > "$home/.claude/skills/dopamine-talk/sentinel.txt"
if run_installer "$home" --lang en --claude --yes --copy --no-global-rules >/dev/null 2>&1; then
  fail "install over an unrelated directory must exit non-zero"
else
  ok
fi
assert_file "$home/.claude/skills/dopamine-talk/sentinel.txt" "unrelated directory survives without --force"
run_installer "$home" --lang en --claude --yes --copy --no-global-rules --force >/dev/null 2>&1
assert_missing "$home/.claude/skills/dopamine-talk/sentinel.txt" "--force replaces the conflicting directory"
assert_file "$home/.claude/skills/dopamine-talk/SKILL.md" "--force installs the skill"

# 3. Marker safety: duplicate blocks collapse, inverted/lone markers never eat
#    the user's text.
home="$(new_home markers)"
mkdir -p "$home/.claude"
cat > "$home/.claude/CLAUDE.md" <<'EOF'
user-before
<!-- dopamine-talk:start -->
old block
<!-- dopamine-talk:end -->
<!-- dopamine-talk:start -->
second block
<!-- dopamine-talk:end -->
user-after
EOF
run_installer "$home" --lang en --claude --yes --copy --global-rules >/dev/null 2>&1
assert_count "$home/.claude/CLAUDE.md" "<!-- dopamine-talk:start -->" 1 "duplicate blocks collapse to one"
assert_contains "$home/.claude/CLAUDE.md" "user-before" "text before blocks is preserved"
assert_contains "$home/.claude/CLAUDE.md" "user-after" "text after blocks is preserved"
assert_not_contains "$home/.claude/CLAUDE.md" "old block" "old block body is replaced"
assert_not_contains "$home/.claude/CLAUDE.md" "second block" "duplicate block body is dropped"

home="$(new_home inverted)"
mkdir -p "$home/.claude"
cat > "$home/.claude/CLAUDE.md" <<'EOF'
user-before
<!-- dopamine-talk:end -->
<!-- dopamine-talk:start -->
user-after
EOF
run_installer "$home" --lang en --claude --yes --copy --global-rules >/dev/null 2>&1
assert_contains "$home/.claude/CLAUDE.md" "user-before" "inverted markers keep content before"
assert_contains "$home/.claude/CLAUDE.md" "user-after" "inverted markers keep content after"
assert_count "$home/.claude/CLAUDE.md" "<!-- dopamine-talk:start -->" 1 "inverted markers yield one block"
run_installer "$home" --uninstall --claude >/dev/null 2>&1
assert_contains "$home/.claude/CLAUDE.md" "user-after" "uninstall with inverted markers preserves user text"

home="$(new_home lone)"
mkdir -p "$home/.claude"
cat > "$home/.claude/CLAUDE.md" <<'EOF'
user-before
<!-- dopamine-talk:start -->
legacy managed text
EOF
run_installer "$home" --lang en --claude --yes --copy --global-rules >/dev/null 2>&1
assert_count "$home/.claude/CLAUDE.md" "<!-- dopamine-talk:start -->" 1 "lone start marker yields one block"
assert_contains "$home/.claude/CLAUDE.md" "legacy managed text" "lone start marker keeps trailing user text"

# 4. Status reads the edition from the managed block, not from unrelated text.
home="$(new_home status)"
run_installer "$home" --lang en --claude --yes --copy --global-rules >/dev/null 2>&1
printf '\n## Мои правила\nВсегда активные правила для моего проекта.\n' >> "$home/.claude/CLAUDE.md"
status_out="$(run_installer "$home" --status 2>/dev/null)"
case "$status_out" in
  *"global-rule"*"[EN · always-on]"*) ok ;;
  *) fail "status must report EN even when the file contains Russian user text" ;;
esac

# 5. Targeted uninstall cleans only that agent's rule, partial --skills keeps
#    pack-wide rules, full uninstall removes them.
home="$(new_home uninstall)"
run_installer "$home" --lang en --claude --codex --yes --copy --global-rules >/dev/null 2>&1
run_installer "$home" --uninstall --claude >/dev/null 2>&1
assert_missing "$home/.claude/skills/dopamine-talk" "targeted uninstall removes Claude skill"
assert_count "$home/.claude/CLAUDE.md" "<!-- dopamine-talk:start -->" 0 "targeted uninstall cleans CLAUDE.md"
assert_file "$home/.codex/skills/dopamine-talk/SKILL.md" "targeted uninstall leaves Codex skill"
assert_count "$home/.codex/AGENTS.md" "<!-- dopamine-talk:start -->" 1 "targeted uninstall leaves Codex rule"

home="$(new_home partial)"
run_installer "$home" --lang en --claude --yes --copy --global-rules >/dev/null 2>&1
run_installer "$home" --uninstall --skills talk --claude >/dev/null 2>&1
assert_missing "$home/.claude/skills/dopamine-talk" "partial uninstall removes selected skill"
assert_file "$home/.claude/skills/dopamine-readme/SKILL.md" "partial uninstall keeps other skills"
assert_count "$home/.claude/CLAUDE.md" "<!-- dopamine-talk:start -->" 1 "partial uninstall keeps pack rules"
run_installer "$home" --uninstall --skills all --claude >/dev/null 2>&1
assert_count "$home/.claude/CLAUDE.md" "<!-- dopamine-talk:start -->" 0 "full skill uninstall removes pack rules"

# 6. Project AGENTS.md installed with --rules can be removed with --rules.
home="$(new_home project)"
mkdir -p "$home/project"
run_installer "$home" --lang en --claude --yes --copy --no-global-rules --rules "$home/project" >/dev/null 2>&1
assert_count "$home/project/AGENTS.md" "<!-- dopamine-talk:start -->" 1 "project rules block is installed"
run_installer "$home" --uninstall --claude --rules "$home/project" >/dev/null 2>&1
assert_count "$home/project/AGENTS.md" "<!-- dopamine-talk:start -->" 0 "project rules block is removed"

# 7. CRLF marker files are updated without duplicating or corrupting content.
home="$(new_home crlf)"
mkdir -p "$home/.claude"
printf '# user\r\n<!-- dopamine-talk:start -->\r\nOLD-BLOCK-SENTINEL\r\n<!-- dopamine-talk:end -->\r\nuser-tail\r\n' > "$home/.claude/CLAUDE.md"
run_installer "$home" --lang en --claude --yes --copy --global-rules >/dev/null 2>&1
assert_count "$home/.claude/CLAUDE.md" "<!-- dopamine-talk:start -->" 1 "CRLF markers update in place"
assert_contains "$home/.claude/CLAUDE.md" "user-tail" "CRLF file keeps trailing content"
assert_not_contains "$home/.claude/CLAUDE.md" "OLD-BLOCK-SENTINEL" "CRLF file drops the old block body"

if [[ $FAILED -gt 0 ]]; then
  printf 'not ok - %d installer assertion(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'ok - %d installer assertions passed\n' "$CHECKS"
