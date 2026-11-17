[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [ValidateSet("origin", "gitlab", "tmdt")]
  [string]$Remote = "gitlab",

  [ValidateNotNullOrEmpty()]
  [string]$Branch = "main",

  [ValidateNotNullOrEmpty()]
  [string]$WorkspaceRoot = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
$targets = switch ($Remote) {
  "origin" { @("origin", "gitlab", "tmdt") }
  "gitlab" { @("gitlab", "tmdt") }
  "tmdt" { @("tmdt") }
}

# WhatIf still validates every repository, but creates no commits and pushes nothing.
if (-not $WhatIfPreference -and -not $PSCmdlet.ShouldProcess(
    $WorkspaceRoot, "Synchronize the committed release to GitLab and TMDT-BUW ($Branch)")) {
  return
}

& (Join-Path $PSScriptRoot "scripts/invoke-repository-sync.ps1") `
  -WorkspaceRoot $WorkspaceRoot -Branch $Branch -Targets $targets -DryRun:$WhatIfPreference
exit $LASTEXITCODE
