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

function Upsert-MarkedBlock([string]$Dst, [string]$RuleContent) {
  $block = "$MarkerStart`n$($RuleContent.Trim())`n$MarkerEnd"
  if (Test-Path $Dst) {
    $existing = Get-Content -Raw -Encoding UTF8 $Dst
    $pattern = "(?s)" + [regex]::Escape($MarkerStart) + ".*?" + [regex]::Escape($MarkerEnd)
    if ($existing -match $pattern) {
      $updated = [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
      Write-Utf8NoBom $Dst $updated
      return
    }
    $sep = if ($existing.Trim().Length -gt 0) { "`n`n" } else { "" }
    Write-Utf8NoBom $Dst ($existing.TrimEnd() + $sep + $block + "`n")
  } else {
    Write-Utf8NoBom $Dst ($block + "`n")
  }
}

function Remove-MarkedBlock([string]$Dst) {
  if (-not (Test-Path $Dst)) { return $false }
  $existing = Get-Content -Raw -Encoding UTF8 $Dst
  $pattern = "(?s)\r?\n*" + [regex]::Escape($MarkerStart) + ".*?" + [regex]::Escape($MarkerEnd) + "\r?\n*"
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
      if (Test-Path $p) {
        $found = $true
        $ed = Detect-Edition (Join-Path $p "SKILL.md")
        Write-Host ("  [OK] {0,-20} [{1}]  {2}" -f $s, $ed, $p) -ForegroundColor Green
      }
    }
    if (Test-Path $a.RulePath) {
      $isHit = ($a.RuleKind -ne "marked") -or ((Get-Content -Raw -Encoding UTF8 $a.RulePath) -like "*$MarkerStart*")
      if ($isHit) {
        $found = $true
        $ed = Detect-Edition $a.RulePath
        Write-Host ("  [OK] {0,-20} [{1} always-on]  {2}" -f "global-rule", $ed, $a.RulePath) -ForegroundColor Cyan
      }
    }
  }
  if (-not $found) { Write-Host "  No Dopamine Talk skills or global rules installed." -ForegroundColor DarkGray }
  Write-Host ""
  return
}

if ($Uninstall) {
  Write-Host "`nUninstalling Dopamine Talk...`n" -ForegroundColor Cyan
  $removed = 0
  foreach ($a in $KnownAgents) {
    foreach ($s in @("dopamine-talk", "dopamine-readme", "dopamine-changelog")) {
      $p = Join-Path $a.Skills $s
      if (Test-Path $p) {
        Remove-Item -Recurse -Force $p
        Write-Host "  [OK] removed  $p" -ForegroundColor Green
        $removed++
      }
    }
    if ($a.RuleKind -eq "marked" -or $a.RuleKind -eq "gemini") {
      if (Remove-MarkedBlock $a.RulePath) {
        Write-Host "  [OK] cleaned  $($a.RulePath)" -ForegroundColor Green
        $removed++
      }
      if ($a.RuleKind -eq "gemini") {
        $agRule = Join-Path $HomeDir ".gemini\config\rules\dopamine-talk.md"
        if (Test-Path $agRule) { Remove-Item -Force $agRule; Write-Host "  [OK] removed  $agRule" -ForegroundColor Green; $removed++ }
      }
    } elseif (Test-Path $a.RulePath) {
      Remove-Item -Force $a.RulePath
      Write-Host "  [OK] removed  $($a.RulePath)" -ForegroundColor Green
      $removed++
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
    $edition = if ($pick -in @("2", "ru", "russian")) { "ru" } else { "en" }
  }
}

# Skill selection
$selectedSkills = @("dopamine-talk", "dopamine-readme", "dopamine-changelog")
if ($Skills -and $Skills.ToLower() -ne "all") {
  $selectedSkills = @()
  foreach ($part in ($Skills -split ",")) {
    switch ($part.Trim().ToLower()) {
      { $_ -in @("talk", "dopamine-talk") } { $selectedSkills += "dopamine-talk" }
      { $_ -in @("readme", "dopamine-readme") } { $selectedSkills += "dopamine-readme" }
      { $_ -in @("changelog", "dopamine-changelog") } { $selectedSkills += "dopamine-changelog" }
    }
  }
}

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
        if ([int]::TryParse($n.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $KnownAgents.Count) {
          $selectedAgents += $KnownAgents[$idx - 1]
        }
      }
    }
  }
}

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
      if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
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
          Write-Utf8NoBom $agRule ($rulesText.Trim() + "`n")
          Write-Host "  [OK] rule    $($a.RulePath) [always-on]" -ForegroundColor Cyan
          Write-Host "  [OK] rule    $agRule [always-on]" -ForegroundColor Cyan
          $rulesCount++
        }
        "cursor" {
          $mdc = "---`ndescription: Dopamine Talk — Always-On Communication Rules`nalwaysApply: true`n---`n`n" + $rulesText.Trim() + "`n"
          Write-Utf8NoBom $a.RulePath $mdc
          Write-Host "  [OK] rule    $($a.RulePath) [alwaysApply]" -ForegroundColor Cyan
          $rulesCount++
        }
        "owned" {
          Write-Utf8NoBom $a.RulePath ($rulesText.Trim() + "`n")
          Write-Host "  [OK] rule    $($a.RulePath) [always-on]" -ForegroundColor Cyan
          $rulesCount++
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
  Write-Host ""
} finally {
  if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
}
