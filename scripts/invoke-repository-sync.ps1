param(
  [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
  [Parameter(Mandatory = $true)][string]$Branch,
  [Parameter(Mandatory = $true)][string[]]$Targets,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$pythonCommand = $null
$pythonPrefix = @()
foreach ($candidate in @("python3", "python", "py")) {
  $command = Get-Command $candidate -ErrorAction SilentlyContinue
  if (-not $command) { continue }
  $prefix = @()
  if ($candidate -eq "py") { $prefix = @("-3") }
  $version = & $command.Source @prefix --version 2>&1
  if ($LASTEXITCODE -eq 0 -and "$version" -match "Python (\d+\.\d+)" -and
      [version]$Matches[1] -ge [version]"3.9") {
    $pythonCommand = $command.Source
    $pythonPrefix = $prefix
    break
  }
}
if (-not $pythonCommand) { throw "Python 3.9 or newer is required for repository synchronization." }

$arguments = @("-B", (Join-Path $PSScriptRoot "sync_repositories.py"),
  "--workspace", $WorkspaceRoot, "--branch", $Branch, "--targets") + $Targets
if ($DryRun) { $arguments += "--dry-run" }
& $pythonCommand @pythonPrefix @arguments
exit $LASTEXITCODE
