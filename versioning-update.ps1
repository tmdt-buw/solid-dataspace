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

function Update-PackageVersions([string]$root, [string[]]$dirtyRepos) {
  $script = @'
import json
import pathlib
import os
import re

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

def parse(version: str):
    parts = version.strip().split(".")
    nums = []
    for i in range(3):
        if i < len(parts) and parts[i].isdigit():
            nums.append(int(parts[i]))
        else:
            nums.append(0)
    return nums

def cmp(a: str, b: str) -> int:
    pa = parse(a)
    pb = parse(b)
    for i in range(3):
        if pa[i] > pb[i]:
            return 1
        if pa[i] < pb[i]:
            return -1
    return 0

root = pathlib.Path(r"__ROOT__")
dirty_raw = os.environ.get("DIRTY_JSON", "[]")
dirty_list = [p.strip().lower() for p in json.loads(dirty_raw) if p.strip()]
dirty_set = set(dirty_list)
targets = [
    (root / ".." / "solid-dataspace-manager" / "package.json", "0.3.0"),
    (root / ".." / "solid-data-manager" / "package.json", "0.4.0"),
    (root / ".." / "smart-city-urban-heat-monitoring" / "package.json", "0.3.0"),
    (root / ".." / "semantic-data-catalog" / "frontend" / "package.json", "0.8.0"),
    (root / ".." / "solid-chatbot" / "package.json", "0.1.0"),
]

versions = {}

for pkg_path, start in targets:
    if not pkg_path.exists():
        continue
    repo_root = pkg_path.parent if pkg_path.name == "package.json" else pkg_path
    # map to actual repo root for frontend
    if pkg_path.parent.name == "frontend":
        repo_root = pkg_path.parent.parent
    repo_key = str(repo_root.resolve()).lower()
    if repo_key not in dirty_set:
        continue
    data = json.loads(pkg_path.read_text(encoding="utf-8"))
    current = data.get("version", "0.0.0")
    base = start if cmp(current, start) < 0 else current
    new_version = bump(base)
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
        version_js.write_text(f'export const appVersion = "{new_version}";\n', encoding="utf-8")
        versions["dataManagerVersion"] = new_version
    if pkg_path.name == "package.json" and pkg_path.parent.name == "solid-dataspace-manager":
        versions["appVersion"] = new_version
    if pkg_path.name == "package.json" and pkg_path.parent.name == "frontend":
        version_js = pkg_path.parent / "src" / "version.js"
        version_js.write_text(f'export const appVersion = "{new_version}";\n', encoding="utf-8")
    if pkg_path.name == "package.json" and pkg_path.parent.name == "smart-city-urban-heat-monitoring":
        version_ts = pkg_path.parent / "src" / "app" / "version.ts"
        version_ts.write_text(f'export const appVersion = "{new_version}";\n', encoding="utf-8")
    if pkg_path.name == "package.json" and pkg_path.parent.name == "solid-chatbot":
        version_js = pkg_path.parent / "frontend" / "src" / "version.js"
        version_js.write_text(f'export const appVersion = "{new_version}";\n', encoding="utf-8")

versions_path = root / ".." / "solid-dataspace-manager" / "src" / "versions.js"
if versions_path.exists():
    existing = versions_path.read_text(encoding="utf-8")
    if "appVersion" not in versions:
        match = re.search(r'export const appVersion = \"([^\"]+)\";', existing)
        if match:
            versions["appVersion"] = match.group(1)
    if "dataManagerVersion" not in versions:
        match = re.search(r'export const dataManagerVersion = \"([^\"]+)\";', existing)
        if match:
            versions["dataManagerVersion"] = match.group(1)

if versions:
    app_version = versions.get("appVersion", "0.0.0")
    data_manager_version = versions.get("dataManagerVersion", "0.0.0")
    versions_path.write_text(
        f'export const appVersion = \"{app_version}\";\n'
        f'export const dataManagerVersion = \"{data_manager_version}\";\n',
        encoding="utf-8"
    )

version_file = root / "VERSION"
if str(root.resolve()).lower() in dirty_set:
    version_file.write_text(bump("0.3.0") + "\n", encoding="utf-8")
'@
  $escapedRoot = $root.Replace("\\", "\\\\")
  $script = $script.Replace("__ROOT__", $escapedRoot)
  $env:DIRTY_JSON = ($dirtyRepos | ConvertTo-Json -Compress)
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

$repos = Get-RepoPaths | Select-Object -Unique
$dirty = New-Object System.Collections.Generic.List[string]
foreach ($repo in $repos) {
  if (-not (Test-Path (Join-Path $repo ".git"))) { continue }
  Push-Location $repo
  try {
    $status = git status --porcelain
    if ($status) { $dirty.Add($repo) }
  } finally {
    Pop-Location
  }
}

Update-PackageVersions -root $root -dirtyRepos $dirty

foreach ($repo in $repos) {
  Invoke-GitCommitAndPush -repoPath $repo -message $CommitMessage
}
