[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [ValidateNotNullOrEmpty()]
  [string]$Remote = "origin",

  [ValidateNotNullOrEmpty()]
  [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

function Get-CurrentScriptRoot {
  if ($PSScriptRoot) {
    return $PSScriptRoot
  }

  return (Get-Location).Path
}

function Test-GitRepository([string]$Path) {
  return Test-Path -LiteralPath (Join-Path $Path ".git")
}

function Get-ProjectPaths([string]$ScriptRoot) {
  $paths = New-Object System.Collections.Generic.List[string]
  $paths.Add((Resolve-Path -LiteralPath $ScriptRoot).Path)

  $reposFile = Join-Path $ScriptRoot "repos.yaml"
  if (Test-Path -LiteralPath $reposFile) {
    Get-Content -LiteralPath $reposFile | ForEach-Object {
      if ($_ -match "^\s*path:\s*(.+)\s*$") {
        $relativePath = $Matches[1].Trim()
        $resolved = Resolve-Path -LiteralPath (Join-Path $ScriptRoot $relativePath) -ErrorAction SilentlyContinue
        if ($resolved) {
          $paths.Add($resolved.Path)
        }
      }
    }
  }

  return $paths | Select-Object -Unique | Sort-Object
}

$scriptRoot = Get-CurrentScriptRoot
$projectPaths = Get-ProjectPaths -ScriptRoot $scriptRoot

$pushedCount = 0
$skippedCount = 0
$failures = New-Object System.Collections.Generic.List[object]

Write-Host "Projects root: $((Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')).Path)"

foreach ($repoPath in $projectPaths) {
  $projectName = Split-Path -Leaf $repoPath

  if (-not (Test-GitRepository -Path $repoPath)) {
    Write-Host "Skip (no .git): $projectName"
    $skippedCount += 1
    continue
  }

  Push-Location -LiteralPath $repoPath
  try {
    $command = "git push $Remote $Branch"

    if ($PSCmdlet.ShouldProcess($repoPath, $command)) {
      Write-Host "Push: $projectName"
      git push $Remote $Branch
      $exitCode = $LASTEXITCODE

      if ($exitCode -ne 0) {
        $failures.Add([pscustomobject]@{
          Repository = $projectName
          ExitCode = $exitCode
        })
        Write-Warning "Failed: $projectName (exit $exitCode)"
      } else {
        $pushedCount += 1
      }
    }
  } finally {
    Pop-Location
  }
}

Write-Host ""
Write-Host "Summary: pushed=$pushedCount skipped=$skippedCount failed=$($failures.Count)"

if ($failures.Count -gt 0) {
  Write-Host "Failures:"
  foreach ($failure in $failures) {
    Write-Host " - $($failure.Repository) (exit $($failure.ExitCode))"
  }
  exit 1
}
