# Parse install.ps1 with the PowerShell language parser. This catches syntax
# errors on both Windows PowerShell 5.1 and PowerShell 7 before a user runs it.
param(
  [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1")
)

if (-not (Test-Path -LiteralPath $Path)) { throw "Installer not found: $Path" }

$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  foreach ($e in $errors) {
    Write-Error ("{0}:{1}: {2}" -f $Path, $e.Extent.StartLineNumber, $e.Message)
  }
  exit 1
}
Write-Host "ok - install.ps1 parses cleanly"
