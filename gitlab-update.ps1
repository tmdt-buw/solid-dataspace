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

$scriptRoot = Get-CurrentScriptRoot
$projectsRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot "..")).Path
$projectDirs = Get-ChildItem -LiteralPath $projectsRoot -Directory | Sort-Object Name

$tmdtProjects = @(
  "semantic-data-catalog",
  "solid-data-manager"
)

$pushedCount = 0
$skippedCount = 0
$failures = New-Object System.Collections.Generic.List[object]

Write-Host "Projects root: $projectsRoot"

foreach ($project in $projectDirs) {
  $repoPath = $project.FullName

  if (-not (Test-GitRepository -Path $repoPath)) {
    Write-Host "Skip (no .git): $($project.Name)"
    $skippedCount += 1
    continue
  }

  Push-Location -LiteralPath $repoPath
  try {
    $command = "git push $Remote $Branch"

    if ($PSCmdlet.ShouldProcess($repoPath, $command)) {
      Write-Host "Push: $($project.Name)"
      git push $Remote $Branch
      $exitCode = $LASTEXITCODE

      if ($exitCode -ne 0) {
        $failures.Add([pscustomobject]@{
          Repository = $project.Name
          Remote = $Remote
          Branch = $Branch
          ExitCode = $exitCode
        })
        Write-Warning "Failed: $($project.Name) (exit $exitCode)"
      } else {
        $pushedCount += 1
      }
    }

    if ($tmdtProjects -contains $project.Name) {
      $tmdtRemote = "tmdt"
      $tmdtBranch = "main"
      $command = "git push $tmdtRemote $tmdtBranch"

      if ($PSCmdlet.ShouldProcess($repoPath, $command)) {
        Write-Host "Push: $($project.Name) -> $tmdtRemote/$tmdtBranch"
        git push $tmdtRemote $tmdtBranch
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
          $failures.Add([pscustomobject]@{
            Repository = $project.Name
            Remote = $tmdtRemote
            Branch = $tmdtBranch
            ExitCode = $exitCode
          })
          Write-Warning "Failed: $($project.Name) -> $tmdtRemote/$tmdtBranch (exit $exitCode)"
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
