param(
  [string]$CommitMessage = "versioning update"
)

$ErrorActionPreference = "Stop"

function Get-RepoPaths {
  $root = $PSScriptRoot
  if (-not $root) { $root = (Get-Location).Path }

  $paths = New-Object System.Collections.Generic.List[string]
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

function Bump-Version([string]$version) {
  $parts = $version.Trim().Split(".")
  if ($parts.Count -ne 3) {
    throw "Invalid version: $version"
  }
  $major = [int]$parts[0]
  $minor = [int]$parts[1]
  $patch = [int]$parts[2]

  $patch += 1
  if ($patch -gt 99) {
    $patch = 0
    $minor += 1
    if ($minor -gt 99) {
      $minor = 0
      $major += 1
    }
  }
  return "$major.$minor.$patch"
}

function Update-PackageVersions([string]$root) {
  $script = @'
import json
import pathlib

def bump(version: str) -> str:
    parts = version.strip().split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise ValueError(f"Invalid version: {version}")
    major, minor, patch = map(int, parts)
    patch += 1
    if patch > 99:
        patch = 0
        minor += 1
        if minor > 99:
            minor = 0
            major += 1
    return f"{major}.{minor}.{patch}"

root = pathlib.Path(r"__ROOT__")
targets = [
    (root / ".." / "solid-dataspace-manager" / "package.json", "0.3.0"),
    (root / ".." / "solid-data-manager" / "package.json", "0.4.0"),
    (root / ".." / "smart-city-urban-heat-monitoring" / "package.json", "0.3.0"),
    (root / ".." / "semantic-data-catalog" / "frontend" / "package.json", "0.8.0"),
]

for pkg_path, start in targets:
    if not pkg_path.exists():
        continue
    new_version = bump(start)
    data = json.loads(pkg_path.read_text(encoding="utf-8"))
    data["version"] = new_version
    pkg_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    lock_path = pkg_path.parent / "package-lock.json"
    if lock_path.exists():
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
        if "version" in lock:
            lock["version"] = new_version
        packages = lock.get("packages")
        if isinstance(packages, dict) and "" in packages and isinstance(packages[""], dict):
            packages[""]["version"] = new_version
        lock_path.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")

    if pkg_path.name == "package.json" and pkg_path.parent.name == "solid-data-manager":
        version_js = pkg_path.parent / "src" / "version.js"
        if version_js.exists():
            version_js.write_text(f'export const appVersion = "{new_version}";\n', encoding="utf-8")

version_file = root / "VERSION"
version_file.write_text(bump("0.3.0") + "\n", encoding="utf-8")
'@
  $escapedRoot = $root.Replace("\\", "\\\\")
  $script = $script.Replace("__ROOT__", $escapedRoot)
  $script | python -
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

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

Update-PackageVersions -root $root

$repos = Get-RepoPaths | Select-Object -Unique
foreach ($repo in $repos) {
  Invoke-GitCommitAndPush -repoPath $repo -message $CommitMessage
}
