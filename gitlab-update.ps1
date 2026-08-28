[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [ValidateNotNullOrEmpty()]
  [string]$Remote = "gitlab",

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

$tmdtProjects = @(
  "semantic-data-catalog",
  "solid-data-manager"
)

# These repositories are intentionally published only through GitHub and must
# not be considered by the GitLab mirror/update pass.
$githubOnlyProjects = @(
  "plasma"
)

$pushedCount = 0
$skippedCount = 0
$failures = New-Object System.Collections.Generic.List[object]

Write-Host "Projects root: $((Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')).Path)"

foreach ($repoPath in $projectPaths) {
  $projectName = Split-Path -Leaf $repoPath

  if ($githubOnlyProjects -contains $projectName) {
    Write-Host "Skip (GitHub only): $projectName"
    $skippedCount += 1
    continue
  }

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
          Remote = $Remote
          Branch = $Branch
          ExitCode = $exitCode
        })
        Write-Warning "Failed: $projectName (exit $exitCode)"
      } else {
        $pushedCount += 1
      }
    }

    if ($tmdtProjects -contains $projectName) {
      $tmdtRemote = "tmdt"
      $tmdtBranch = "main"
      $command = "git push $tmdtRemote $tmdtBranch"

      if ($PSCmdlet.ShouldProcess($repoPath, $command)) {
        Write-Host "Push: $projectName -> $tmdtRemote/$tmdtBranch"
        git push $tmdtRemote $tmdtBranch
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
          $failures.Add([pscustomobject]@{
            Repository = $projectName
            Remote = $tmdtRemote
            Branch = $tmdtBranch
            ExitCode = $exitCode
          })
          Write-Warning "Failed: $projectName -> $tmdtRemote/$tmdtBranch (exit $exitCode)"
        } else {
          $pushedCount += 1
        }
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
    Write-Host " - $($failure.Repository) -> $($failure.Remote)/$($failure.Branch) (exit $($failure.ExitCode))"
  }
  exit 1
}
