param(
  [string]$CommitMessage = "versioning update"
)

$ErrorActionPreference = "Stop"

function Get-RepoPaths {
  $root = $PSScriptRoot
  if (-not $root) {
    $root = (Get-Location).Path
  }
  $paths = New-Object System.Collections.Generic.List[string]

  # Include this repo first
  $paths.Add($root)

  $reposFile = Join-Path $root "repos.yaml"
  if (-not (Test-Path $reposFile)) {
    return $paths
  }

  Get-Content $reposFile | ForEach-Object {
    if ($_ -match "^\s*path:\s*(.+)\s*$") {
      $rel = $Matches[1].Trim()
      $full = Resolve-Path (Join-Path $root $rel) -ErrorAction SilentlyContinue
      if ($full) { $paths.Add($full.Path) }
    }
  }

  return $paths
}

function Invoke-GitCommitAndPush([string]$repoPath, [string]$message) {
  if (-not (Test-Path (Join-Path $repoPath ".git"))) {
    Write-Host "Skip (no .git): $repoPath"
    return
  }

  Push-Location $repoPath
  try {
    $status = git status --porcelain
    if (-not $status) {
      Write-Host "Clean: $repoPath"
      return
    }

    Write-Host "Updating: $repoPath"
    git add .
    git commit -m $message
    git push origin main
  } finally {
    Pop-Location
  }
}

$repos = Get-RepoPaths | Select-Object -Unique
foreach ($repo in $repos) {
  Invoke-GitCommitAndPush -repoPath $repo -message $CommitMessage
}
