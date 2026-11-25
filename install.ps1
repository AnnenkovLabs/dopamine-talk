#Requires -Version 5.1
<#
.SYNOPSIS
  Dopamine Talk Native Windows Installer (PowerShell 5.1+ & PowerShell 7+)

.EXAMPLE
  irm https://dopamine.annenkov.me/install.ps1 | iex
  & ([scriptblock]::Create((irm https://dopamine.annenkov.me/install.ps1))) -Lang ru -Yes
  & ([scriptblock]::Create((irm https://dopamine.annenkov.me/install.ps1))) -Status
  & ([scriptblock]::Create((irm https://dopamine.annenkov.me/install.ps1))) -Uninstall
#>
[CmdletBinding()]
param(
  [ValidateSet("", "en", "ru", "english", "russian")]
  [string]$Lang = "",
  [string]$Skills = "",
  [switch]$Agents,
  [switch]$Claude,
  [switch]$Codex,
  [switch]$Gemini,
  [switch]$Antigravity,
  [switch]$Cursor,
  [switch]$Windsurf,
  [switch]$Copilot,
  [switch]$OpenCode,
  [switch]$Kiro,
  [switch]$AllAgents,
  [string]$Dir = "",
  [switch]$NoGlobalRules,
  [switch]$Force,
  [switch]$Yes,
  [switch]$Status,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoSlug = "AnnenkovLabs/dopamine-talk"
$ZipUrl = "https://github.com/$RepoSlug/archive/refs/heads/main.zip"
$MarkerStart = "<!-- dopamine-talk:start -->"
$MarkerEnd = "<!-- dopamine-talk:end -->"
$HomeDir = $env:USERPROFILE

$KnownAgents = @(
  @{ Name = "Universal (Antigravity, OpenCode, Cline, Pi)"; Probe = (Join-Path $HomeDir ".agents"); Skills = (Join-Path $HomeDir ".agents\skills"); RuleKind = "marked"; RulePath = (Join-Path $HomeDir ".agents\AGENTS.md") },
  @{ Name = "Claude Code"; Probe = (Join-Path $HomeDir ".claude"); Skills = (Join-Path $HomeDir ".claude\skills"); RuleKind = "marked"; RulePath = (Join-Path $HomeDir ".claude\CLAUDE.md") },
  @{ Name = "OpenAI Codex"; Probe = (Join-Path $HomeDir ".codex"); Skills = (Join-Path $HomeDir ".codex\skills"); RuleKind = "marked"; RulePath = (Join-Path $HomeDir ".codex\AGENTS.md") },
  @{ Name = "Gemini CLI / Antigravity"; Probe = (Join-Path $HomeDir ".gemini"); Skills = (Join-Path $HomeDir ".gemini\config\skills"); RuleKind = "gemini"; RulePath = (Join-Path $HomeDir ".gemini\GEMINI.md") },
  @{ Name = "Cursor"; Probe = (Join-Path $HomeDir ".cursor"); Skills = (Join-Path $HomeDir ".cursor\skills"); RuleKind = "cursor"; RulePath = (Join-Path $HomeDir ".cursor\rules\dopamine-talk.mdc") },
  @{ Name = "Windsurf"; Probe = (Join-Path $HomeDir ".codeium"); Skills = (Join-Path $HomeDir ".codeium\windsurf\skills"); RuleKind = "marked"; RulePath = (Join-Path $HomeDir ".codeium\windsurf\memories\global_rules.md") },
  @{ Name = "GitHub Copilot"; Probe = (Join-Path $HomeDir ".copilot"); Skills = (Join-Path $HomeDir ".copilot\skills"); RuleKind = "marked"; RulePath = (Join-Path $HomeDir ".copilot\copilot-instructions.md") },
  @{ Name = "OpenCode"; Probe = (Join-Path $HomeDir ".config\opencode"); Skills = (Join-Path $HomeDir ".config\opencode\skills"); RuleKind = "marked"; RulePath = (Join-Path $HomeDir ".config\opencode\AGENTS.md") },
  @{ Name = "Kiro"; Probe = (Join-Path $HomeDir ".kiro"); Skills = (Join-Path $HomeDir ".kiro\skills"); RuleKind = "owned"; RulePath = (Join-Path $HomeDir ".kiro\steering\dopamine-talk.md") }
)

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  # Never follow a symlink/junction into its target. Replace the link with a
  # regular file, leaving the target untouched.
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
    Remove-SkillPath $Path
  }
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Detect-Edition([string]$FilePath) {
  if (-not (Test-Path $FilePath)) { return "unknown" }
  $txt = Get-Content -Raw -Encoding UTF8 $FilePath
  if ($txt -match 'Деактивирует|Пишет и переписывает|Включает режим|Всегда активные правила|Пять главных правил') { return "RU" }
  return "EN"
}

# Read the edition from the managed block only. Unrelated Russian text in the
# user's CLAUDE.md/AGENTS.md must not turn an EN install into RU.
function Detect-MarkedEdition([string]$FilePath) {
  if (-not (Test-Path $FilePath)) { return "unknown" }
  $txt = Get-Content -Raw -Encoding UTF8 $FilePath
  $s = [regex]::Escape($MarkerStart)
  $e = [regex]::Escape($MarkerEnd)
  $m = [regex]::Match($txt, "(?s).*$s((?:(?!$s).)*?)$e")
  if (-not $m.Success) { return "unknown" }
  if ($m.Groups[1].Value -match 'Деактивирует|Пишет и переписывает|Включает режим|Всегда активные правила|Пять главных правил') { return "RU" }
  return "EN"
}

# A directory is a verified Dopamine Talk install only when its SKILL.md declares
# the expected skill name. This protects same-named unrelated directories.
function Test-DopamineSkill([string]$Path, [string]$SkillName) {
  $manifest = Join-Path $Path "SKILL.md"
  if (-not (Test-Path -LiteralPath $manifest)) { return $false }
  $text = Get-Content -Raw -Encoding UTF8 $manifest
  return [bool]($text -match "(?m)^name:\s*$([regex]::Escape($SkillName))\s*$")
}

# Remove a skill directory without following a symlink/junction into its target.
# Windows PowerShell 5.1's Remove-Item -Recurse is known to delete link targets.
# A path is safe to uninstall only when it is a link (removing the link does not
# touch its target) or a directory whose SKILL.md declares the expected name.
function Test-InstalledSkillPath([string]$Path, [string]$SkillName) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { return $false }
  if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $true }
  if (-not $item.PSIsContainer) { return $false }
  return (Test-DopamineSkill $Path $SkillName)
}

# A file is ours only when it carries the signature this installer writes.
# Same-named user files are never deleted or reported as installed.
function Test-OwnedRule([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { return $false }
  if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
  if ($item.PSIsContainer) { return $false }
  $text = Get-Content -Raw -Encoding UTF8 $Path
  if ([System.IO.Path]::GetExtension($Path) -eq ".mdc") {
    return ($text -match 'description:\s*Dopamine Talk' -and $text -match 'alwaysApply:\s*true')
  }
  return ($text -match '# Dopamine Talk' -and
    ($text -match '## Core Rules' -or $text -match '## Пять главных правил'))
}

# Write an installer-owned rule only when it is missing or carries our
# signature. A foreign same-named file is preserved unless -Force is explicit.
function Write-OwnedRule([string]$Path, [string]$Content, [string]$Kind) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($item -and -not (Test-OwnedRule $Path)) {
    if (-not $Force) {
      Write-Host "  ! skip     $Path (unrelated file - pass -Force to replace)" -ForegroundColor Yellow
      return $false
    }
    Remove-SkillPath $Path
  }
  if ($Kind -eq "cursor") {
    $mdc = "---`ndescription: Dopamine Talk — Always-On Communication Rules`nalwaysApply: true`n---`n`n" + $Content.Trim() + "`n"
    Write-Utf8NoBom $Path $mdc
  } else {
    Write-Utf8NoBom $Path ($Content.Trim() + "`n")
  }
  return $true
}

function Remove-SkillPath([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { return }
  if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    if ($item.PSIsContainer) {
      [System.IO.Directory]::Delete($item.FullName, $false)
    } else {
      [System.IO.File]::Delete($item.FullName)
    }
    return
  }
  Remove-Item -LiteralPath $Path -Recurse -Force
}

# Resolve -Skills once for install and uninstall. Invalid tokens fail loudly
# instead of silently installing/removing nothing.
function Resolve-SkillSelection([string]$Value) {
  $all = @("dopamine-talk", "dopamine-readme", "dopamine-changelog")
  if (-not $Value) { return $all }
  $tokens = @($Value -split "," | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
  if ($tokens -contains "all") { return $all }
  $out = @()
  foreach ($t in $tokens) {
    switch ($t) {
      { $_ -in @("talk", "dopamine-talk") } { $out += "dopamine-talk" }
      { $_ -in @("readme", "dopamine-readme") } { $out += "dopamine-readme" }
      { $_ -in @("changelog", "dopamine-changelog") } { $out += "dopamine-changelog" }
      default { throw "Unknown skill '$t'. Use talk, readme, changelog or all." }
    }
  }
  if ($out.Count -eq 0) { throw "No valid skills selected. Use talk, readme, changelog or all." }
  return @($out | Select-Object -Unique)
}

# Explicit agent switches for uninstall, deduplicated by skills directory.
function Get-ExplicitAgentList {
  $list = @()
  if ($AllAgents) { return @($KnownAgents) }
  if ($Agents) { $list += $KnownAgents[0] }
  if ($Claude) { $list += $KnownAgents[1] }
  if ($Codex) { $list += $KnownAgents[2] }
  if ($Gemini) { $list += $KnownAgents[3] }
  if ($Antigravity) { $list += $KnownAgents[0]; $list += $KnownAgents[3] }
  if ($Cursor) { $list += $KnownAgents[4] }
  if ($Windsurf) { $list += $KnownAgents[5] }
  if ($Copilot) { $list += $KnownAgents[6] }
  if ($OpenCode) { $list += $KnownAgents[7] }
  if ($Kiro) { $list += $KnownAgents[8] }
  $deduped = @()
  foreach ($a in $list) {
    if (-not ($deduped | Where-Object { $_.Skills -eq $a.Skills })) { $deduped += $a }
  }
  return @($deduped)
}

function Remove-AgentRule($Agent) {
  $removed = $false
  if ($Agent.RuleKind -eq "marked" -or $Agent.RuleKind -eq "gemini") {
    if (Remove-MarkedBlock $Agent.RulePath) {
      Write-Host "  [OK] cleaned  $($Agent.RulePath)" -ForegroundColor Green
      $removed = $true
    }
    if ($Agent.RuleKind -eq "gemini") {
      $agRule = Join-Path $HomeDir ".gemini\config\rules\dopamine-talk.md"
      if (Test-OwnedRule $agRule) {
        Remove-Item -Force $agRule
        Write-Host "  [OK] removed  $agRule" -ForegroundColor Green
        $removed = $true
      }
    }
  } elseif ($Agent.RuleKind -ne "none" -and (Test-OwnedRule $Agent.RulePath)) {
    Remove-Item -Force $Agent.RulePath
    Write-Host "  [OK] removed  $($Agent.RulePath)" -ForegroundColor Green
    $removed = $true
  }
  return $removed
}

function Upsert-MarkedBlock([string]$Dst, [string]$RuleContent) {
  $block = "$MarkerStart`n$($RuleContent.Trim())`n$MarkerEnd"
  if (-not (Test-Path $Dst)) {
    Write-Utf8NoBom $Dst ($block + "`n")
    return
  }

  $existing = Get-Content -Raw -Encoding UTF8 $Dst
  $s = [regex]::Escape($MarkerStart)
  $e = [regex]::Escape($MarkerEnd)
  # A nested start marker means the earlier one is an orphan: never let it pair
  # with an end marker that belongs to a later real block.
  $pairPattern = "(?s)$s(?:(?!$s).)*?$e"
  $matches = [regex]::Matches($existing, $pairPattern)

  if ($matches.Count -gt 0) {
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    for ($i = 0; $i -lt $matches.Count; $i++) {
      $m = $matches[$i]
      [void]$sb.Append($existing.Substring($pos, $m.Index - $pos))
      if ($i -eq 0) { [void]$sb.Append($block) }
      $pos = $m.Index + $m.Length
    }
    [void]$sb.Append($existing.Substring($pos))
    Write-Utf8NoBom $Dst $sb.ToString()
    return
  }

  if ($existing.Contains($MarkerStart)) {
    $first = $existing.IndexOf($MarkerStart, [System.StringComparison]::Ordinal)
    $before = $existing.Substring(0, $first)
    $after = $existing.Substring($first + $MarkerStart.Length).Replace($MarkerStart, "")
    Write-Utf8NoBom $Dst ($before + $block + $after)
    return
  }

  $sep = if ($existing.Trim().Length -gt 0) { "`n`n" } else { "" }
  Write-Utf8NoBom $Dst ($existing.TrimEnd() + $sep + $block + "`n")
}

function Remove-MarkedBlock([string]$Dst) {
  if (-not (Test-Path $Dst)) { return $false }
  $existing = Get-Content -Raw -Encoding UTF8 $Dst
  $s = [regex]::Escape($MarkerStart)
  $e = [regex]::Escape($MarkerEnd)
  $pattern = "(?s)\r?\n*$s(?:(?!$s).)*?$e\r?\n*"
  if ($existing -notmatch $pattern) { return $false }
  $cleaned = ([regex]::Replace($existing, $pattern, "`n")).Trim()
  if ($cleaned.Length -eq 0) {
    Remove-Item -Force $Dst
  } else {
    Write-Utf8NoBom $Dst ($cleaned + "`n")
  }
  return $true
}

if ($Status) {
  Write-Host "`nDopamine Talk — Installed Status`n" -ForegroundColor Cyan
  $found = $false
  foreach ($a in $KnownAgents) {
    foreach ($s in @("dopamine-talk", "dopamine-readme", "dopamine-changelog")) {
      $p = Join-Path $a.Skills $s
      if (Test-InstalledSkillPath $p $s) {
        $found = $true
        $ed = Detect-Edition (Join-Path $p "SKILL.md")
        Write-Host ("  [OK] {0,-20} [{1}]  {2}" -f $s, $ed, $p) -ForegroundColor Green
      }
    }
    if (Test-Path $a.RulePath) {
      $marked = $a.RuleKind -eq "marked" -or $a.RuleKind -eq "gemini"
      $isHit = (-not $marked) -or ((Get-Content -Raw -Encoding UTF8 $a.RulePath) -like "*$MarkerStart*")
      if ($a.RuleKind -in @("cursor", "owned") -and -not (Test-OwnedRule $a.RulePath)) { $isHit = $false }
      if ($isHit) {
        $found = $true
        $ed = if ($marked) { Detect-MarkedEdition $a.RulePath } else { Detect-Edition $a.RulePath }
        Write-Host ("  [OK] {0,-20} [{1} always-on]  {2}" -f "global-rule", $ed, $a.RulePath) -ForegroundColor Cyan
      }
    }
  }
  if (-not $found) { Write-Host "  No Dopamine Talk skills or global rules installed." -ForegroundColor DarkGray }
  Write-Host ""
  return
}

if ($Uninstall) {
  $skillsToRemove = @(Resolve-SkillSelection $Skills)
  $targets = @(Get-ExplicitAgentList)
  if ($targets.Count -eq 0 -and -not $Dir) { $targets = @($KnownAgents) }

  Write-Host "`nUninstalling Dopamine Talk...`n" -ForegroundColor Cyan
  $removed = 0
  foreach ($a in $targets) {
    foreach ($s in $skillsToRemove) {
      $p = Join-Path $a.Skills $s
      if (Test-InstalledSkillPath $p $s) {
        Remove-SkillPath $p
        Write-Host "  [OK] removed  $p" -ForegroundColor Green
        $removed++
      }
    }
    # Pack-wide rules are cleaned only for a full pack removal.
    if ($skillsToRemove.Count -eq 3 -and (Remove-AgentRule $a)) { $removed++ }
  }

  if ($Dir) {
    foreach ($s in $skillsToRemove) {
      $p = Join-Path $Dir $s
      if (Test-InstalledSkillPath $p $s) {
        Remove-SkillPath $p
        Write-Host "  [OK] removed  $p" -ForegroundColor Green
        $removed++
      }
    }
  }

  if ($removed -eq 0) { Write-Host "  Nothing to remove." -ForegroundColor DarkGray }
  Write-Host ""
  return
}

# Language selection
$edition = ""
if ($Lang) {
  $edition = if ($Lang.ToLower().StartsWith("ru")) { "ru" } else { "en" }
} else {
  $uiLang = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName.ToLower()
  $defChoice = if ($uiLang -in @("ru", "uk", "be", "kk")) { "2" } else { "1" }
  if ($Yes) {
    $edition = if ($defChoice -eq "2") { "ru" } else { "en" }
  } else {
    Write-Host "`n=== Dopamine Talk Windows Installer ===" -ForegroundColor Cyan
    Write-Host "1. Choose edition / Выбери язык:"
    Write-Host "   1) English (Western English — sharp, zero AI slop)"
    Write-Host "   2) Русский (Живой русский — без духоты и Runglish)"
    $pick = Read-Host "   Pick [1/2] (default $defChoice)"
    if (-not $pick) { $pick = $defChoice }
    switch ($pick.Trim().ToLower()) {
      { $_ -in @("1", "en", "english") } { $edition = "en" }
      { $_ -in @("2", "ru", "russian") } { $edition = "ru" }
      default { throw "Invalid language choice '$pick'. Use 1 (English) or 2 (Russian)." }
    }
  }
}

if ($Dir -and $Dir.Trim().Length -eq 0) { throw "-Dir requires a non-empty directory path." }

# Skill selection
$selectedSkills = @(Resolve-SkillSelection $Skills)

# Target selection
$selectedAgents = @()
if ($AllAgents) { $selectedAgents = $KnownAgents[0..6] }
else {
  if ($Agents) { $selectedAgents += $KnownAgents[0] }
  if ($Claude) { $selectedAgents += $KnownAgents[1] }
  if ($Codex) { $selectedAgents += $KnownAgents[2] }
  if ($Gemini) { $selectedAgents += $KnownAgents[3] }
  if ($Antigravity) { $selectedAgents += $KnownAgents[0]; $selectedAgents += $KnownAgents[3] }
  if ($Cursor) { $selectedAgents += $KnownAgents[4] }
  if ($Windsurf) { $selectedAgents += $KnownAgents[5] }
  if ($Copilot) { $selectedAgents += $KnownAgents[6] }
  if ($OpenCode) { $selectedAgents += $KnownAgents[7] }
  if ($Kiro) { $selectedAgents += $KnownAgents[8] }
}

if ($selectedAgents.Count -eq 0 -and -not $Dir) {
  $detected = @($KnownAgents | Where-Object { Test-Path $_.Probe })
  if ($detected.Count -eq 0) { $detected = @($KnownAgents[0]) }
  if ($Yes) {
    $selectedAgents = $detected
  } else {
    Write-Host ""
    if ($edition -eq "ru") { Write-Host "2. В какие агенты поставить? (найденные отмечены [detected])" }
    else { Write-Host "2. Select target agents (detected agents are highlighted):" }
    $defIdx = @()
    for ($i = 0; $i -lt $KnownAgents.Count; $i++) {
      $a = $KnownAgents[$i]
      $isDet = Test-Path $a.Probe
      if ($isDet) { $defIdx += ($i + 1) }
      $tag = if ($isDet) { " [detected]" } else { "" }
      Write-Host ("   {0}) {1}{2}" -f ($i + 1), $a.Name, $tag)
    }
    if ($defIdx.Count -eq 0) { $defIdx = @(1) }
    $defStr = $defIdx -join ","
    $pick = Read-Host "   Pick numbers, 'all', or Enter for [$defStr]"
    if (-not $pick) { $pick = $defStr }
    if ($pick.Trim().ToLower() -eq "all") {
      $selectedAgents = $KnownAgents[0..6]
    } else {
      foreach ($n in ($pick -split ",")) {
        $idx = 0
        if (-not [int]::TryParse($n.Trim(), [ref]$idx) -or $idx -lt 1 -or $idx -gt $KnownAgents.Count) {
          throw "Invalid target '$($n.Trim())'. Pick numbers 1-$($KnownAgents.Count), 'all', or press Enter."
        }
        $selectedAgents += $KnownAgents[$idx - 1]
      }
    }
  }
}

$dedupedAgents = @()
foreach ($a in $selectedAgents) {
  if (-not ($dedupedAgents | Where-Object { $_.Skills -eq $a.Skills })) { $dedupedAgents += $a }
}
$selectedAgents = $dedupedAgents
if ($selectedAgents.Count -eq 0 -and -not $Dir) { throw "No target agents selected. Use -Claude, -Codex, -Dir PATH, -AllAgents, or pick at least one number." }

$enableGlobalRules = -not $NoGlobalRules
if (-not $Yes -and -not $NoGlobalRules) {
  $q = if ($edition -eq "ru") { "3. Включить всегда по умолчанию в CLAUDE.md / AGENTS.md / GEMINI.md? [Y/n]" } else { "3. Enable always-on mode globally (CLAUDE.md / AGENTS.md / GEMINI.md)? [Y/n]" }
  $ans = Read-Host $q
  if ($ans -and $ans.Trim().ToLower() -in @("n", "no", "н", "нет")) { $enableGlobalRules = $false }
}

$tmpDir = Join-Path $env:TEMP ("dopamine-talk-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
try {
  $zipPath = Join-Path $tmpDir "repo.zip"
  Write-Host "`nDownloading $RepoSlug..." -ForegroundColor DarkGray
  Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing
  Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
  $srcRoot = (Get-ChildItem -Directory $tmpDir | Select-Object -First 1).FullName

  $skillsSrc = if ($edition -eq "ru") { Join-Path $srcRoot "skills-ru" } else { Join-Path $srcRoot "skills" }
  $rulesSrc = if ($edition -eq "ru") { Join-Path $srcRoot "docs\i18n\AGENTS.ru.md" } else { Join-Path $srcRoot "AGENTS.md" }
  $rulesText = Get-Content -Raw -Encoding UTF8 $rulesSrc
  $edLabel = if ($edition -eq "ru") { "RU" } else { "EN" }

  $installed = 0
  $skipped = 0
  $rulesCount = 0
  Write-Host "Installing Dopamine Talk [$edLabel]...`n" -ForegroundColor Cyan

  $targetList = @($selectedAgents)
  if ($Dir) {
    $targetList += @{ Name = "Custom"; Skills = $Dir; RuleKind = "none"; RulePath = "" }
  }

  foreach ($a in $targetList) {
    if (-not (Test-Path $a.Skills)) { New-Item -ItemType Directory -Path $a.Skills -Force | Out-Null }
    foreach ($s in $selectedSkills) {
      $src = Join-Path $skillsSrc $s
      $dst = Join-Path $a.Skills $s
      if (-not (Test-Path (Join-Path $src "SKILL.md"))) { throw "Skill source missing: $src" }
      if (Test-Path -LiteralPath $dst) {
        if ($Force -or (Test-DopamineSkill $dst $s)) {
          Remove-SkillPath $dst
        } else {
          Write-Host "  [SKIP] $dst exists and is not a Dopamine Talk install (use -Force to replace)" -ForegroundColor Yellow
          $skipped++
          continue
        }
      }
      Copy-Item -Recurse -Force $src $dst
      Write-Host "  [OK] copied  $dst" -ForegroundColor Green
      $installed++
    }
    if ($enableGlobalRules -and $a.RuleKind -ne "none") {
      switch ($a.RuleKind) {
        "marked" {
          Upsert-MarkedBlock $a.RulePath $rulesText
          Write-Host "  [OK] rule    $($a.RulePath) [always-on]" -ForegroundColor Cyan
          $rulesCount++
        }
        "gemini" {
          Upsert-MarkedBlock $a.RulePath $rulesText
          $agRule = Join-Path $HomeDir ".gemini\config\rules\dopamine-talk.md"
          Write-Host "  [OK] rule    $($a.RulePath) [always-on]" -ForegroundColor Cyan
          if (Write-OwnedRule $agRule $rulesText "copy") {
            Write-Host "  [OK] rule    $agRule [always-on]" -ForegroundColor Cyan
          }
          $rulesCount++
        }
        "cursor" {
          if (Write-OwnedRule $a.RulePath $rulesText "cursor") {
            Write-Host "  [OK] rule    $($a.RulePath) [alwaysApply]" -ForegroundColor Cyan
            $rulesCount++
          }
        }
        "owned" {
          if (Write-OwnedRule $a.RulePath $rulesText "copy") {
            Write-Host "  [OK] rule    $($a.RulePath) [always-on]" -ForegroundColor Cyan
            $rulesCount++
          }
        }
      }
    }
  }

  Write-Host ""
  if ($edition -eq "ru") {
    Write-Host "Готово! Установлено скиллов: $installed, глобальных правил: $rulesCount ($edLabel)." -ForegroundColor Green
    Write-Host "Открой новый чат в агенте — режим уже активен." -ForegroundColor DarkGray
  } else {
    Write-Host "Done! Installed $installed skill(s) and $rulesCount always-on rule target(s) ($edLabel)." -ForegroundColor Green
    Write-Host "Open a new chat — Dopamine Talk is active immediately." -ForegroundColor DarkGray
  }
  if ($skipped -gt 0) { Write-Host "$skipped target(s) skipped - see messages above." -ForegroundColor Yellow }
  Write-Host ""
} finally {
  if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
}
