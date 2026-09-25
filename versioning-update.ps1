param(
  [string]$CommitMessage = "versioning update",
  [switch]$WhatIf,
  [switch]$IncludeUntracked
)

$ErrorActionPreference = "Stop"

function Assert-LastExitCode([string]$Operation) {
  if ($LASTEXITCODE -ne 0) {
    throw "$Operation failed with exit code $LASTEXITCODE."
  }
}

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
      $candidate = Join-Path $root $rel
      $full = Resolve-Path $candidate -ErrorAction SilentlyContinue
      if (-not $full) {
        throw "Repository path from repos.yaml does not exist: $rel ($candidate)"
      }
      if (-not (Test-Path (Join-Path $full.Path ".git"))) {
        throw "Repository path from repos.yaml is not a Git repository: $rel ($($full.Path))"
      }
      $paths.Add($full.Path)
    }
  }

  return $paths
}

function Get-NormalizedPath([string]$Path) {
  return [System.IO.Path]::GetFullPath($Path).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ).ToLowerInvariant()
}

function Get-RepoChangeSnapshot([string]$RepoPath) {
  $trackedFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  $untrackedFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  Push-Location $RepoPath
  try {
    # --no-renames deliberately returns both sides of a rename. That lets the
    # later path-scoped git add stage the deletion and the addition explicitly.
    $tracked = @(
      git -c "safe.directory=$RepoPath" -c core.safecrlf=false diff --name-only --no-renames HEAD --
    )
    Assert-LastExitCode "Reading tracked changes for $RepoPath"
    $untracked = @(git -c "safe.directory=$RepoPath" ls-files --others --exclude-standard)
    Assert-LastExitCode "Reading untracked changes for $RepoPath"

    foreach ($relativePath in @($tracked)) {
      if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
      [void]$trackedFiles.Add([System.IO.Path]::GetFullPath((Join-Path $RepoPath $relativePath)))
    }
    foreach ($relativePath in @($untracked)) {
      if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
      [void]$untrackedFiles.Add([System.IO.Path]::GetFullPath((Join-Path $RepoPath $relativePath)))
    }
  } finally {
    Pop-Location
  }
  return [PSCustomObject]@{
    TrackedFiles = @($trackedFiles)
    UntrackedFiles = @($untrackedFiles)
  }
}

function Get-RepoHeadCommit([string]$RepoPath) {
  $commit = (git -c "safe.directory=$RepoPath" -C $RepoPath rev-parse HEAD).Trim().ToLowerInvariant()
  Assert-LastExitCode "Resolving local HEAD for $RepoPath"
  if ($commit -notmatch '^[0-9a-f]{40}$') {
    throw "Release aborted: local HEAD could not be resolved unambiguously for $RepoPath."
  }
  return $commit
}

function Get-MainCommit([string]$RepoPath) {
  $commit = (git -c "safe.directory=$RepoPath" -C $RepoPath rev-parse refs/heads/main).Trim().ToLowerInvariant()
  Assert-LastExitCode "Resolving local main for $RepoPath"
  if ($commit -notmatch '^[0-9a-f]{40}$') {
    throw "Release aborted: local main could not be resolved unambiguously for $RepoPath."
  }
  return $commit
}

function Assert-LocalHeadUnchanged(
  [string]$RepoPath,
  [string]$ExpectedCommit,
  [string]$Context
) {
  $actualCommit = Get-RepoHeadCommit -RepoPath $RepoPath
  if ($actualCommit -ne $ExpectedCommit.ToLowerInvariant()) {
    throw "Release aborted: local HEAD changed $Context for $RepoPath. Expected $ExpectedCommit, found $actualCommit."
  }
}

function Assert-MainHeadState(
  [string]$RepoPath,
  [string]$ExpectedCommit,
  [string]$Context
) {
  $branch = (git -c "safe.directory=$RepoPath" -C $RepoPath branch --show-current).Trim()
  Assert-LastExitCode "Reading current branch for $RepoPath"
  if ($branch -ne "main") {
    throw "Release aborted: $RepoPath left branch 'main' $Context (current branch: '$branch')."
  }

  Assert-LocalHeadUnchanged `
    -RepoPath $RepoPath `
    -ExpectedCommit $ExpectedCommit `
    -Context $Context
  $mainCommit = Get-MainCommit -RepoPath $RepoPath
  if ($mainCommit -ne $ExpectedCommit.ToLowerInvariant()) {
    throw "Release aborted: local main changed $Context for $RepoPath. Expected $ExpectedCommit, found $mainCommit."
  }
}

function Get-FileChangeFingerprint(
  [string]$RepoPath,
  [string]$FilePath
) {
  $repoRoot = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd("\", "/")
  $repoPrefix = $repoRoot + [System.IO.Path]::DirectorySeparatorChar
  $fullPath = [System.IO.Path]::GetFullPath($FilePath)
  if (-not $fullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Cannot fingerprint a path outside $RepoPath`: $fullPath"
  }

  $relativePath = $fullPath.Substring($repoPrefix.Length).Replace("\", "/")
  $pathspec = ":(literal)$relativePath"
  $status = @(
    git -c "safe.directory=$RepoPath" -C $RepoPath status --porcelain=v1 --untracked-files=all -- $pathspec
  )
  Assert-LastExitCode "Fingerprinting Git state for $fullPath"
  $indexState = @(
    git -c "safe.directory=$RepoPath" -C $RepoPath ls-files --stage -- $pathspec
  )
  Assert-LastExitCode "Fingerprinting index state for $fullPath"

  $contentIdentity = "missing"
  if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
    $contentIdentity = (git -c "safe.directory=$RepoPath" -C $RepoPath hash-object --no-filters -- $relativePath).Trim()
    Assert-LastExitCode "Fingerprinting file content for $fullPath"
  } elseif (Test-Path -LiteralPath $fullPath -PathType Container) {
    $contentIdentity = "directory"
  }

  $fingerprintSource = (
    ($status -join "`n") + "`n--index--`n" +
    ($indexState -join "`n") + "`n--worktree--`n" +
    $contentIdentity
  )
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($fingerprintSource)
    return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha256.Dispose()
  }
}

function Get-RepoFileFingerprints(
  [string]$RepoPath,
  [string[]]$Files
) {
  $fingerprints = @{}
  foreach ($file in @($Files | Select-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace($file)) { continue }
    $fullPath = [System.IO.Path]::GetFullPath($file)
    $fingerprints[$fullPath.ToLowerInvariant()] = Get-FileChangeFingerprint `
      -RepoPath $RepoPath `
      -FilePath $fullPath
  }
  return $fingerprints
}

function Assert-RepoFileFingerprints(
  [string]$RepoPath,
  [string[]]$Files,
  [hashtable]$ExpectedFingerprints,
  [string]$Context
) {
  foreach ($file in @($Files | Select-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace($file)) { continue }
    $fullPath = [System.IO.Path]::GetFullPath($file)
    $key = $fullPath.ToLowerInvariant()
    if (-not $ExpectedFingerprints.ContainsKey($key)) {
      throw "Release aborted: no approved content fingerprint exists for $fullPath."
    }
    $actual = Get-FileChangeFingerprint -RepoPath $RepoPath -FilePath $fullPath
    if ($actual -ne $ExpectedFingerprints[$key]) {
      throw "Release aborted: approved file content or Git state changed $Context in $RepoPath`: $fullPath"
    }
  }
}

function Assert-OnlyApprovedRepoChanges(
  [string]$RepoPath,
  [string[]]$ApprovedFiles,
  [string]$Context
) {
  $approved = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($file in @($ApprovedFiles)) {
    if ([string]::IsNullOrWhiteSpace($file)) { continue }
    [void]$approved.Add([System.IO.Path]::GetFullPath($file))
  }

  $snapshot = Get-RepoChangeSnapshot -RepoPath $RepoPath
  $unexpected = @(
    @($snapshot.TrackedFiles) + @($snapshot.UntrackedFiles) |
      Where-Object { -not $approved.Contains([System.IO.Path]::GetFullPath($_)) } |
      Select-Object -Unique
  )
  if ($unexpected.Count -gt 0) {
    $formatted = $unexpected -join "`n  - "
    throw "Release aborted: unapproved worktree changes appeared $Context in $RepoPath`:`n  - $formatted"
  }
}

function Assert-RequiredRepoChangesPresent(
  [string]$RepoPath,
  [string[]]$RequiredFiles,
  [string]$Context
) {
  $snapshot = Get-RepoChangeSnapshot -RepoPath $RepoPath
  $changed = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($file in @($snapshot.TrackedFiles) + @($snapshot.UntrackedFiles)) {
    [void]$changed.Add([System.IO.Path]::GetFullPath($file))
  }

  $missing = @(
    foreach ($file in @($RequiredFiles | Select-Object -Unique)) {
      if ([string]::IsNullOrWhiteSpace($file)) { continue }
      $fullPath = [System.IO.Path]::GetFullPath($file)
      if (-not $changed.Contains($fullPath)) { $fullPath }
    }
  )
  if ($missing.Count -gt 0) {
    $formatted = $missing -join "`n  - "
    throw "Release aborted: required selected changes disappeared $Context in $RepoPath`:`n  - $formatted"
  }
}

function Assert-LinearAheadRange(
  [string]$RepoPath,
  [string]$BaseCommit,
  [string]$HeadCommit
) {
  if ($BaseCommit -eq $HeadCommit) { return 0 }

  $range = "$BaseCommit..$HeadCommit"
  $mergeCommits = @(git -c "safe.directory=$RepoPath" -C $RepoPath rev-list --merges $range)
  Assert-LastExitCode "Checking local commit topology for $RepoPath"
  if ($mergeCommits.Count -gt 0) {
    throw "Release aborted: local commits ahead of origin/main are not linear in $RepoPath (merge commit $($mergeCommits[0])). Rebase or reconcile main first."
  }

  $countText = (git -c "safe.directory=$RepoPath" -C $RepoPath rev-list --count $range).Trim()
  Assert-LastExitCode "Counting local commits ahead of origin/main for $RepoPath"
  $count = 0
  if (-not [int]::TryParse($countText, [ref]$count) -or $count -lt 1) {
    throw "Release aborted: the local commit range could not be validated for $RepoPath."
  }
  return $count
}

function Assert-MainBranches([string[]]$RepoPaths) {
  foreach ($repoPath in @($RepoPaths | Select-Object -Unique)) {
    if (-not (Test-Path (Join-Path $repoPath ".git"))) {
      throw "Affected repository has no .git directory: $repoPath"
    }
    Push-Location $repoPath
    try {
      $branch = git -c "safe.directory=$repoPath" branch --show-current
      Assert-LastExitCode "Reading current branch for $repoPath"
      if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Detached HEAD is not allowed for a release: $repoPath"
      }
      if ($branch.Trim() -ne "main") {
        throw "Release aborted: $repoPath is on branch '$($branch.Trim())'; expected 'main'."
      }
    } finally {
      Pop-Location
    }
  }
}

function Assert-ManagerPublishGuard([string]$ManagerPath) {
  $workflow = Join-Path $ManagerPath ".github\workflows\docker-image.yml"
  if (-not (Test-Path $workflow)) {
    throw "Manager release workflow is missing: $workflow"
  }

  Push-Location $ManagerPath
  try {
    git -c "safe.directory=$ManagerPath" ls-files --error-unmatch -- ".github/workflows/docker-image.yml" | Out-Null
    Assert-LastExitCode "Checking tracked Manager release workflow"
  } finally {
    Pop-Location
  }

  $content = Get-Content -Raw -Encoding UTF8 $workflow
  $requiredMarkers = @(
    "Wait for pinned embed packages",
    "npm view",
    "@hoelk-f/solid-data-manager",
    "@hoelk-f/semantic-data-catalog",
    "@hoelk-f/solid-health-app",
    "@hoelk-f/city-tours",
    "@hoelk-f/solid-health-questionnaire",
    "@hoelk-f/solid-chatbot",
    "SOLID_DATA_MANAGER_PACKAGE_VERSION",
    "SEMANTIC_DATA_CATALOG_PACKAGE_VERSION",
    "SOLID_HEALTH_APP_PACKAGE_VERSION",
    "CITY_TOURS_PACKAGE_VERSION",
    "SOLID_HEALTH_QUESTIONNAIRE_PACKAGE_VERSION",
    "SOLID_CHATBOT_PACKAGE_VERSION"
  )
  foreach ($marker in $requiredMarkers) {
    if (-not $content.Contains($marker)) {
      throw "Manager release workflow does not contain its package-availability guard ('$marker')."
    }
  }
}

function Assert-PackageReleaseWorkflows([string]$Root) {
  $workflows = @(
    (Join-Path $Root "..\solid-data-manager\.github\workflows\docker-image.yml"),
    (Join-Path $Root "..\semantic-data-catalog\.github\workflows\docker-image_frontend.yml"),
    (Join-Path $Root "..\solid-health-app\.github\workflows\docker-image.yml"),
    (Join-Path $Root "..\solid-tours\.github\workflows\ci.yml"),
    (Join-Path $Root "..\solid-health-questionnaire\.github\workflows\ci.yml"),
    (Join-Path $Root "..\solid-chatbot\.github\workflows\docker-image-frontend.yml")
  )
  foreach ($workflow in $workflows) {
    if (-not (Test-Path $workflow)) {
      throw "Required package release workflow is missing: $workflow"
    }
    $content = Get-Content -Raw -Encoding UTF8 $workflow
    if ($content -notmatch '(?m)^\s*run:\s+npm publish(?:\s|$)') {
      throw "Package release workflow has no npm publish step: $workflow"
    }
    if ($content -match '(?i)Bump version for publish|\bnpm\s+version\b') {
      throw "Package release workflow mutates its version during CI: $workflow. Publish the exact source version instead."
    }
  }
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

function Update-PackageVersions(
  [string]$root,
  [string[]]$dirtyRepos,
  [switch]$ApplyChanges
) {
  $script = @'
import json
import pathlib
import os
import re
import datetime
import subprocess

apply_changes = os.environ.get("APPLY_CHANGES", "false").lower() == "true"
changed_files = set()
skipped_untracked = set()
repository_roots = []

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

def parse(version: str, context: str = "version"):
    if not isinstance(version, str) or re.fullmatch(r"\d+\.\d+\.\d+", version) is None:
        raise ValueError(f"Invalid stable semantic version for {context}: {version!r}")
    return [int(part) for part in version.split(".")]

def validate_dependency_request(
    value: str,
    context: str,
    allow_legacy_range: bool = False,
) -> None:
    if allow_legacy_range and isinstance(value, str) and re.fullmatch(
        r"[~^]\d+\.\d+\.\d+", value
    ):
        return
    parse(value, context)

def cmp(a: str, b: str) -> int:
    pa = parse(a)
    pb = parse(b)
    for i in range(3):
        if pa[i] > pb[i]:
            return 1
        if pa[i] < pb[i]:
            return -1
    return 0

def max_version(*versions: str) -> str:
    result = "0.0.0"
    for version in versions:
        if version and cmp(version, result) > 0:
            result = version
    return result

def read_json(path: pathlib.Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read valid JSON from {path}: {error}") from error

def write_json(path: pathlib.Path, data) -> None:
    write_text(path, json.dumps(data, indent=2) + "\n")

def repo_key(path: pathlib.Path) -> str:
    return str(path.resolve()).lower()

def committed_package_version(repo_path: pathlib.Path, package_path: pathlib.Path):
    try:
        relative_path = package_path.resolve().relative_to(repo_path.resolve()).as_posix()
    except ValueError:
        return None

    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repo_path}",
            "-C",
            str(repo_path),
            "show",
            f"HEAD:{relative_path}",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Cannot read committed package manifest HEAD:{relative_path} in {repo_path}")
    try:
        version = json.loads(result.stdout).get("version")
    except (json.JSONDecodeError, AttributeError) as error:
        raise ValueError(f"Committed package manifest is invalid: {repo_path}/HEAD:{relative_path}") from error
    parse(version, f"{repo_path}/HEAD:{relative_path}")
    return version

def committed_file_text(repo_path: pathlib.Path, file_path: pathlib.Path):
    try:
        relative_path = file_path.resolve().relative_to(repo_path.resolve()).as_posix()
    except ValueError:
        return None
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repo_path}",
            "-C",
            str(repo_path),
            "show",
            f"HEAD:{relative_path}",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None

def is_tracked(repo_path: pathlib.Path, file_path: pathlib.Path) -> bool:
    try:
        relative_path = file_path.resolve().relative_to(repo_path.resolve()).as_posix()
    except ValueError:
        return False
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repo_path}",
            "-C",
            str(repo_path),
            "ls-files",
            "--error-unmatch",
            "--",
            f":(literal){relative_path}",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0

def owning_repo(file_path: pathlib.Path):
    resolved = file_path.resolve()
    matches = []
    for repo_path in repository_roots:
        try:
            resolved.relative_to(repo_path)
            matches.append(repo_path)
        except ValueError:
            continue
    return max(matches, key=lambda value: len(str(value))) if matches else None

def require_tracked_file(repo_path: pathlib.Path, path: pathlib.Path, label: str) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Required {label} is missing: {path}")
    if not is_tracked(repo_path, path):
        raise RuntimeError(f"Required {label} is not tracked by Git: {path}")

def write_text(path: pathlib.Path, content: str) -> bool:
    # Release automation must never create files implicitly. In particular,
    # ignored/untracked dist manifests from a local build must stay untouched.
    repo_path = owning_repo(path)
    if not path.exists() or repo_path is None or not is_tracked(repo_path, path):
        if path.exists():
            skipped_untracked.add(str(path.resolve()))
        return False

    existing = path.read_text(encoding="utf-8")
    if existing == content:
        return False

    changed_files.add(str(path.resolve()))
    if apply_changes:
        path.write_text(content, encoding="utf-8")
    return True

def write_required_text(path: pathlib.Path, content: str, label: str) -> bool:
    repo_path = owning_repo(path)
    if repo_path is None:
        raise RuntimeError(f"Required {label} has no configured owning repository: {path}")
    require_tracked_file(repo_path, path, label)
    return write_text(path, content)

def replace_exactly_once(
    content: str,
    pattern: str,
    replacement: str,
    label: str,
):
    updated, replacements = re.subn(pattern, replacement, content, count=1)
    if replacements != 1:
        raise RuntimeError(f"Expected exactly one {label} replacement, found {replacements}")
    return updated

def set_exported_version(
    path: pathlib.Path,
    constant_name: str,
    new_version: str,
    label: str,
) -> None:
    parse(new_version, f"planned {label}")
    repo_path = owning_repo(path)
    if repo_path is None:
        raise RuntimeError(f"Required {label} has no configured repository: {path}")
    require_tracked_file(repo_path, path, label)
    content = path.read_text(encoding="utf-8")
    pattern = rf'(?m)^(export const {re.escape(constant_name)}\s*=\s*")([^"]+)(";\s*)$'
    matches = list(re.finditer(pattern, content))
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one {constant_name} declaration in {path}, found {len(matches)}")
    parse(matches[0].group(2), f"{path} {constant_name}")
    updated = re.sub(
        pattern,
        rf'\g<1>{new_version}\g<3>',
        content,
        count=1,
    )
    write_required_text(path, updated, label)

def write_package_version(pkg_path: pathlib.Path, new_version: str) -> None:
    parse(new_version, f"planned version for {pkg_path}")
    repo_path = owning_repo(pkg_path)
    if repo_path is None:
        raise RuntimeError(f"Package manifest has no configured owning repository: {pkg_path}")
    require_tracked_file(repo_path, pkg_path, "package manifest")

    data = read_json(pkg_path)
    parse(data.get("version"), f"{pkg_path} version")
    data["version"] = new_version
    write_required_text(pkg_path, json.dumps(data, indent=2) + "\n", "package manifest")

    lock_path = pkg_path.parent / "package-lock.json"
    if lock_path.exists():
        require_tracked_file(repo_path, lock_path, "package lockfile")
        lock = read_json(lock_path)
        parse(lock.get("version"), f"{lock_path} version")
        packages = lock.get("packages")
        if not isinstance(packages, dict) or not isinstance(packages.get(""), dict):
            raise ValueError(f"{lock_path} has no valid packages root entry")
        parse(packages[""].get("version"), f"{lock_path} packages root version")
        lock["version"] = new_version
        packages[""]["version"] = new_version
        write_required_text(
            lock_path,
            json.dumps(lock, indent=2) + "\n",
            "package lockfile",
        )
    if apply_changes:
        if read_json(pkg_path).get("version") != new_version:
            raise RuntimeError(f"Package version postcondition failed for {pkg_path}")
        if lock_path.exists():
            applied_lock = read_json(lock_path)
            if (
                applied_lock.get("version") != new_version
                or applied_lock.get("packages", {}).get("", {}).get("version") != new_version
            ):
                raise RuntimeError(f"Lockfile version postcondition failed for {lock_path}")

def dependency_metadata(pkg_path: pathlib.Path, version: str):
    metadata = {"version": version}
    if not pkg_path.exists():
        return metadata
    package = read_json(pkg_path)
    for field in (
        "license",
        "dependencies",
        "optionalDependencies",
        "peerDependencies",
        "peerDependenciesMeta",
        "engines",
        "bin",
    ):
        if field in package:
            metadata[field] = package[field]
    # Reproduce the manifests generated by each embed build when dist does not
    # exist in a clean checkout. The standalone source manifests deliberately
    # contain additional UI/auth dependencies that must not be copied into the
    # Manager lockfile.
    published_dependency_names = {
        "@hoelk-f/solid-data-manager": (),
        "@hoelk-f/semantic-data-catalog": (
            "@inrupt/solid-client",
            "@inrupt/vocab-common-rdf",
            "n3",
        ),
        "@hoelk-f/city-tours": (
            "@hoelk-f/semantic-data-catalog",
            "@inrupt/oidc-client-ext",
            "@inrupt/solid-client",
            "@inrupt/solid-client-authn-browser",
            "@inrupt/solid-client-authn-core",
            "leaflet",
        ),
        "@hoelk-f/solid-health-questionnaire": (
            "@inrupt/solid-client",
        ),
        "@hoelk-f/solid-health-app": (
            "@emotion/react",
            "@emotion/styled",
            "@inrupt/solid-client",
            "@inrupt/solid-client-authn-browser",
            "@inrupt/vocab-common-rdf",
            "@mui/material",
            "@mui/system",
            "@react-oauth/google",
            "react-router-dom",
            "recharts",
        ),
        "@hoelk-f/solid-chatbot": (
            "@fortawesome/fontawesome-svg-core",
            "@fortawesome/free-solid-svg-icons",
            "@fortawesome/react-fontawesome",
            "@inrupt/solid-client",
            "@inrupt/solid-client-authn-browser",
            "@inrupt/vocab-common-rdf",
        ),
    }
    package_name = package.get("name")
    allowed_dependencies = published_dependency_names.get(package_name)
    if allowed_dependencies is not None:
        source_dependencies = package.get("dependencies")
        if not isinstance(source_dependencies, dict):
            source_dependencies = {}
        metadata["dependencies"] = {
            name: source_dependencies[name]
            for name in allowed_dependencies
            if name in source_dependencies
        }
    elif isinstance(metadata.get("dependencies"), dict) and isinstance(
        metadata.get("peerDependencies"), dict
    ):
        metadata["dependencies"] = dict(metadata["dependencies"])
        for peer_name in metadata["peerDependencies"]:
            metadata["dependencies"].pop(peer_name, None)
    return metadata

def sync_dependency(
    consumer_pkg: pathlib.Path,
    dependency_name: str,
    dependency_version: str,
    dependency_metadata_path: pathlib.Path,
    allow_legacy_input: bool = False,
) -> None:
    parse(dependency_version, f"planned dependency {dependency_name}")
    consumer_repo = owning_repo(consumer_pkg)
    if consumer_repo is None:
        raise RuntimeError(f"Dependency consumer has no configured repository: {consumer_pkg}")
    require_tracked_file(consumer_repo, consumer_pkg, "dependency consumer package manifest")
    metadata_repo = owning_repo(dependency_metadata_path)
    if metadata_repo is None:
        raise RuntimeError(f"Dependency metadata has no configured repository: {dependency_metadata_path}")
    require_tracked_file(metadata_repo, dependency_metadata_path, "dependency metadata package manifest")
    lock_path = consumer_pkg.parent / "package-lock.json"
    require_tracked_file(consumer_repo, lock_path, "dependency consumer lockfile")

    package = read_json(consumer_pkg)
    dependencies = package.get("dependencies")
    if not isinstance(dependencies, dict) or dependency_name not in dependencies:
        raise ValueError(f"{consumer_pkg} has no existing dependency entry for {dependency_name}")
    validate_dependency_request(
        dependencies[dependency_name],
        f"{consumer_pkg} dependency {dependency_name}",
        allow_legacy_input,
    )
    dependencies[dependency_name] = dependency_version

    lock = read_json(lock_path)
    packages = lock.get("packages")
    if not isinstance(packages, dict):
        raise ValueError(f"{lock_path} has no valid packages object")
    root_package = packages.get("")
    if not isinstance(root_package, dict):
        raise ValueError(f"{lock_path} has no valid packages root entry")
    root_dependencies = root_package.get("dependencies")
    if not isinstance(root_dependencies, dict) or dependency_name not in root_dependencies:
        raise ValueError(f"{lock_path} root has no dependency entry for {dependency_name}")
    validate_dependency_request(
        root_dependencies[dependency_name],
        f"{lock_path} root dependency {dependency_name}",
        allow_legacy_input,
    )

    package_key = f"node_modules/{dependency_name}"
    old_entry = packages.get(package_key)
    if not isinstance(old_entry, dict):
        raise ValueError(f"{lock_path} has no installed entry {package_key}")
    parse(old_entry.get("version"), f"{lock_path} installed dependency {dependency_name}")

    root_dependencies[dependency_name] = dependency_version
    new_entry = dependency_metadata(dependency_metadata_path, dependency_version)
    for lock_field in ("dev", "optional", "devOptional", "inBundle", "hasInstallScript"):
        if lock_field in old_entry and lock_field not in new_entry:
            new_entry[lock_field] = old_entry[lock_field]
    if old_entry.get("version") == dependency_version:
        for lock_field in ("resolved", "integrity"):
            if lock_field in old_entry:
                new_entry[lock_field] = old_entry[lock_field]
    packages[package_key] = new_entry

    legacy_dependencies = lock.get("dependencies")
    if isinstance(legacy_dependencies, dict):
        legacy_entry = legacy_dependencies.get(dependency_name)
        if not isinstance(legacy_entry, dict):
            raise ValueError(f"{lock_path} legacy dependencies has no entry for {dependency_name}")
        legacy_entry["version"] = dependency_version
        if old_entry.get("version") != dependency_version:
            legacy_entry.pop("resolved", None)
            legacy_entry.pop("integrity", None)

    if dependencies.get(dependency_name) != dependency_version:
        raise RuntimeError(f"Package dependency postcondition failed for {dependency_name}")
    if root_dependencies.get(dependency_name) != dependency_version:
        raise RuntimeError(f"Lockfile root postcondition failed for {dependency_name}")
    if packages.get(package_key, {}).get("version") != dependency_version:
        raise RuntimeError(f"Lockfile installed-entry postcondition failed for {dependency_name}")

    write_required_text(
        consumer_pkg,
        json.dumps(package, indent=2) + "\n",
        "dependency consumer package manifest",
    )
    write_required_text(
        lock_path,
        json.dumps(lock, indent=2) + "\n",
        "dependency consumer lockfile",
    )

    dist_package = consumer_pkg.parent / "dist" / "package.json"
    if dist_package.exists() and is_tracked(consumer_repo, dist_package):
        dist = read_json(dist_package)
        dist_dependencies = dist.get("dependencies")
        if not isinstance(dist_dependencies, dict) or dependency_name not in dist_dependencies:
            raise ValueError(f"{dist_package} has no dependency entry for {dependency_name}")
        parse(dist_dependencies[dependency_name], f"{dist_package} dependency {dependency_name}")
        dist_dependencies[dependency_name] = dependency_version
        write_required_text(
            dist_package,
            json.dumps(dist, indent=2) + "\n",
            "tracked dist package manifest",
        )
    if apply_changes:
        if read_dependency(consumer_pkg, dependency_name) != dependency_version:
            raise RuntimeError(f"Applied package dependency postcondition failed for {dependency_name}")
        if not lock_dependency_matches(consumer_pkg, dependency_name, dependency_version):
            raise RuntimeError(f"Applied lockfile dependency postcondition failed for {dependency_name}")

def read_dependency(
    pkg_path: pathlib.Path,
    package_name: str,
    allow_legacy_range: bool = False,
):
    if not pkg_path.exists():
        return None
    package = read_json(pkg_path)
    dependencies = package.get("dependencies")
    if not isinstance(dependencies, dict):
        return None
    version = dependencies.get(package_name)
    if version is not None:
        validate_dependency_request(
            version,
            f"{pkg_path} dependency {package_name}",
            allow_legacy_range,
        )
    return version

def has_lock_dependency(pkg_path: pathlib.Path, package_name: str) -> bool:
    lock_path = pkg_path.parent / "package-lock.json"
    if not lock_path.exists():
        return False
    lock = read_json(lock_path)
    packages = lock.get("packages")
    return isinstance(packages, dict) and isinstance(
        packages.get(f"node_modules/{package_name}"), dict
    )

def locked_dependency_version(pkg_path: pathlib.Path, package_name: str) -> str:
    repo_path = owning_repo(pkg_path)
    if repo_path is None:
        raise RuntimeError(f"Lockfile owner is not configured for {pkg_path}")
    lock_path = pkg_path.parent / "package-lock.json"
    require_tracked_file(repo_path, lock_path, "dependency consumer lockfile")
    lock = read_json(lock_path)
    packages = lock.get("packages")
    if not isinstance(packages, dict):
        raise ValueError(f"{lock_path} has no valid packages object")
    root_package = packages.get("")
    installed = packages.get(f"node_modules/{package_name}")
    if not isinstance(root_package, dict) or not isinstance(installed, dict):
        raise ValueError(f"{lock_path} has no installed entry for {package_name}")
    root_dependencies = root_package.get("dependencies")
    if not isinstance(root_dependencies, dict) or package_name not in root_dependencies:
        raise ValueError(f"{lock_path} root has no dependency entry for {package_name}")
    requested = root_dependencies[package_name]
    installed_version = installed.get("version")
    validate_dependency_request(
        requested,
        f"{lock_path} root dependency {package_name}",
        allow_legacy_range=True,
    )
    parse(installed_version, f"{lock_path} installed dependency {package_name}")
    return installed_version

def lock_dependency_matches(
    pkg_path: pathlib.Path,
    package_name: str,
    version: str,
    allow_legacy_request: bool = False,
) -> bool:
    lock_path = pkg_path.parent / "package-lock.json"
    if not lock_path.exists():
        return False
    lock = read_json(lock_path)
    packages = lock.get("packages")
    if not isinstance(packages, dict):
        return False
    root_package = packages.get("")
    installed_package = packages.get(f"node_modules/{package_name}")
    if not isinstance(root_package, dict) or not isinstance(installed_package, dict):
        return False
    root_dependencies = root_package.get("dependencies")
    requested_version = root_dependencies.get(package_name) if isinstance(root_dependencies, dict) else None
    installed_version = installed_package.get("version")
    if requested_version is not None:
        validate_dependency_request(
            requested_version,
            f"{lock_path} root dependency {package_name}",
            allow_legacy_request,
        )
    if installed_version is not None:
        parse(installed_version, f"{lock_path} installed dependency {package_name}")
    return (
        isinstance(root_dependencies, dict)
        and requested_version == version
        and installed_version == version
    )

def read_docker_arg(dockerfile: pathlib.Path, arg_name: str):
    if not dockerfile.exists():
        return None
    match = re.search(
        rf"(?m)^ARG {re.escape(arg_name)}=([^\s]+)$",
        dockerfile.read_text(encoding="utf-8"),
    )
    if not match:
        return None
    version = match.group(1)
    parse(version, f"{dockerfile} ARG {arg_name}")
    return version

def set_docker_arg(dockerfile: pathlib.Path, arg_name: str, version: str) -> None:
    parse(version, f"planned Docker ARG {arg_name}")
    repo_path = owning_repo(dockerfile)
    if repo_path is None:
        raise RuntimeError(f"Manager Dockerfile has no configured repository: {dockerfile}")
    require_tracked_file(repo_path, dockerfile, "Manager Dockerfile")
    content = dockerfile.read_text(encoding="utf-8")
    content, replacements = re.subn(
        rf"(?m)^(ARG {re.escape(arg_name)}=)[^\s]+$",
        rf"\g<1>{version}",
        content,
        count=1,
    )
    if replacements != 1:
        raise RuntimeError(f"{dockerfile} does not define {arg_name} exactly once")
    write_required_text(dockerfile, content, "Manager Dockerfile")
    if apply_changes and read_docker_arg(dockerfile, arg_name) != version:
        raise RuntimeError(f"Docker ARG postcondition failed for {arg_name}")

root = pathlib.Path(r"__ROOT__").resolve()
dirty_raw = os.environ.get("DIRTY_JSON", "[]")
dirty_list = [p.strip().lower() for p in json.loads(dirty_raw) if p.strip()]
dirty_set = set(dirty_list)
manager_path = (root / ".." / "solid-dataspace-manager").resolve()
solid_data_manager_path = (root / ".." / "solid-data-manager").resolve()
sync_worker_path = (root / ".." / "solid-data-connection-sync-worker").resolve()
semantic_catalog_path = (root / ".." / "semantic-data-catalog").resolve()
environmental_path = (root / ".." / "environmental-monitoring").resolve()
solid_health_path = (root / ".." / "solid-health-app").resolve()
solid_health_questionnaire_path = (root / ".." / "solid-health-questionnaire").resolve()
city_tours_path = (root / ".." / "solid-tours").resolve()
solid_chatbot_path = (root / ".." / "solid-chatbot").resolve()

manager_repo = repo_key(manager_path)
solid_data_manager_repo = repo_key(solid_data_manager_path)
sync_worker_repo = repo_key(sync_worker_path)
semantic_catalog_repo = repo_key(semantic_catalog_path)
environmental_repo = repo_key(environmental_path)
solid_health_repo = repo_key(solid_health_path)
solid_health_questionnaire_repo = repo_key(solid_health_questionnaire_path)
city_tours_repo = repo_key(city_tours_path)
solid_chatbot_repo = repo_key(solid_chatbot_path)
affected_set = set(dirty_set)

targets = [
    (manager_path, manager_path / "package.json", "0.3.0"),
    (solid_data_manager_path, solid_data_manager_path / "package.json", "0.4.0"),
    (sync_worker_path, sync_worker_path / "package.json", "0.1.0"),
    (environmental_path, environmental_path / "package.json", "0.3.0"),
    (solid_health_path, solid_health_path / "package.json", "0.1.0"),
    (solid_health_questionnaire_path, solid_health_questionnaire_path / "package.json", "0.1.0"),
    (city_tours_path, city_tours_path / "package.json", "0.1.0"),
    (semantic_catalog_path, semantic_catalog_path / "frontend" / "package.json", "0.8.0"),
    (solid_chatbot_path, solid_chatbot_path / "package.json", "0.1.0"),
]
repository_roots = sorted(
    {root, *(repo_path for repo_path, _, _ in targets)},
    key=lambda value: len(str(value)),
    reverse=True,
)

current_versions = {}
for repo_path, pkg_path, _ in targets:
    if not repo_path.exists():
        raise FileNotFoundError(f"Required repository is missing: {repo_path}")
    require_tracked_file(repo_path, pkg_path, "target package manifest")
    current_version = read_json(pkg_path).get("version")
    parse(current_version, f"{pkg_path} version")
    current_versions[repo_key(repo_path)] = current_version

catalog_pkg = semantic_catalog_path / "frontend" / "package.json"
data_manager_pkg = solid_data_manager_path / "package.json"
health_pkg = solid_health_path / "package.json"
tours_pkg = city_tours_path / "package.json"
questionnaire_pkg = solid_health_questionnaire_path / "package.json"
chatbot_pkg = solid_chatbot_path / "package.json"
manager_pkg = manager_path / "package.json"
manager_dockerfile = manager_path / "Dockerfile"

catalog_current = current_versions.get(semantic_catalog_repo)
data_manager_current = current_versions.get(solid_data_manager_repo)
health_current = current_versions.get(solid_health_repo)
tours_current = current_versions.get(city_tours_repo)
questionnaire_current = current_versions.get(solid_health_questionnaire_repo)
chatbot_current = current_versions.get(solid_chatbot_repo)
tours_dist_package = city_tours_path / "dist" / "package.json"

# Build the dependency closure before calculating any version. This prevents a
# consumer from being pinned to an intermediate version that never gets a
# matching release.
if catalog_current and (
    semantic_catalog_repo in affected_set
    or read_dependency(tours_pkg, "@hoelk-f/semantic-data-catalog") != catalog_current
    or not lock_dependency_matches(
        tours_pkg, "@hoelk-f/semantic-data-catalog", catalog_current
    )
    or (
        is_tracked(city_tours_path, tours_dist_package)
        and read_dependency(
            tours_dist_package, "@hoelk-f/semantic-data-catalog"
        )
        != catalog_current
    )
):
    affected_set.add(city_tours_repo)

embedded_repos = {
    semantic_catalog_repo,
    solid_data_manager_repo,
    environmental_repo,
    solid_health_repo,
    solid_health_questionnaire_repo,
    city_tours_repo,
    solid_chatbot_repo,
}
if affected_set.intersection(embedded_repos):
    affected_set.add(manager_repo)

require_tracked_file(manager_path, manager_dockerfile, "Manager Dockerfile")
manager_dependency_sources = [
    (
        "@hoelk-f/solid-data-manager",
        solid_data_manager_repo,
        data_manager_current,
        data_manager_pkg,
        "SOLID_DATA_MANAGER_PACKAGE_VERSION",
    ),
    (
        "@hoelk-f/semantic-data-catalog",
        semantic_catalog_repo,
        catalog_current,
        catalog_pkg,
        "SEMANTIC_DATA_CATALOG_PACKAGE_VERSION",
    ),
    (
        "@hoelk-f/solid-health-app",
        solid_health_repo,
        health_current,
        health_pkg,
        "SOLID_HEALTH_APP_PACKAGE_VERSION",
    ),
    (
        "@hoelk-f/city-tours",
        city_tours_repo,
        tours_current,
        tours_pkg,
        "CITY_TOURS_PACKAGE_VERSION",
    ),
    (
        "@hoelk-f/solid-health-questionnaire",
        solid_health_questionnaire_repo,
        questionnaire_current,
        questionnaire_pkg,
        "SOLID_HEALTH_QUESTIONNAIRE_PACKAGE_VERSION",
    ),
    (
        "@hoelk-f/solid-chatbot",
        solid_chatbot_repo,
        chatbot_current,
        chatbot_pkg,
        "SOLID_CHATBOT_PACKAGE_VERSION",
    ),
]
manager_floor_versions = {}
manager_dependency_specs = []
for package_name, package_repo, source_version, metadata_path, docker_arg in manager_dependency_sources:
    floor_version = locked_dependency_version(manager_pkg, package_name)
    manager_floor_versions[package_repo] = floor_version
    package_version = max_version(source_version, floor_version)
    manager_dependency_specs.append(
        (package_name, package_repo, package_version, metadata_path, docker_arg)
    )

for package_name, _, package_version, _, docker_arg in manager_dependency_specs:
    manager_request = read_dependency(
        manager_pkg,
        package_name,
        allow_legacy_range=True,
    )
    if manager_request is None:
        raise ValueError(f"{manager_pkg} has no required dependency {package_name}")
    if not has_lock_dependency(manager_pkg, package_name):
        raise ValueError(
            f"{manager_pkg.parent / 'package-lock.json'} has no installed entry "
            f"node_modules/{package_name}"
        )
    docker_version = read_docker_arg(manager_dockerfile, docker_arg)
    if docker_version is None:
        raise ValueError(f"{manager_dockerfile} has no required ARG {docker_arg}")
    if (
        manager_request != package_version
        or not lock_dependency_matches(
            manager_pkg,
            package_name,
            package_version,
            allow_legacy_request=True,
        )
        or docker_version != package_version
    ):
        affected_set.add(manager_repo)

# Resolve every final version first, then write files and dependency pins in a
# second pass. If a previous run already changed package.json but stopped before
# committing it, retain that pending version rather than bumping it again.
effective_versions = dict(current_versions)
for package_repo, floor_version in manager_floor_versions.items():
    effective_versions[package_repo] = max_version(
        effective_versions[package_repo], floor_version
    )
release_versions = {}
for repo_path, pkg_path, start in targets:
    key = repo_key(repo_path)
    if not pkg_path.exists() or key not in affected_set:
        continue
    current = current_versions[key]
    committed = committed_package_version(repo_path, pkg_path)
    release_floor = manager_floor_versions.get(key, "0.0.0")
    if (
        committed
        and cmp(current, committed) > 0
        and cmp(current, release_floor) > 0
    ):
        release_versions[key] = current
    else:
        release_versions[key] = bump(
            max_version(
                start,
                current,
                committed or "0.0.0",
                manager_floor_versions.get(key, "0.0.0"),
            )
        )
    effective_versions[key] = release_versions[key]

for repo_path, pkg_path, _ in targets:
    key = repo_key(repo_path)
    if not pkg_path.exists() or key not in affected_set:
        continue
    new_version = release_versions[key]
    write_package_version(pkg_path, new_version)

    dist_package = pkg_path.parent / "dist" / "package.json"
    if is_tracked(repo_path, dist_package):
        write_package_version(dist_package, new_version)

    if pkg_path.name == "package.json" and pkg_path.parent.name == "solid-data-manager":
        version_js = pkg_path.parent / "src" / "version.js"
        set_exported_version(version_js, "appVersion", new_version, "Data Manager version module")
    if pkg_path.name == "package.json" and pkg_path.parent.name == "frontend":
        version_js = pkg_path.parent / "src" / "version.js"
        set_exported_version(version_js, "appVersion", new_version, "Catalog version module")
    if pkg_path.name == "package.json" and pkg_path.parent.name == "environmental-monitoring":
        version_ts = pkg_path.parent / "src" / "version.ts"
        set_exported_version(version_ts, "appVersion", new_version, "Environmental Monitoring version module")
        external_links = root / ".." / "solid-dataspace-manager" / "src" / "externalLinks.js"
        require_tracked_file(manager_path, external_links, "Manager external links module")
        content = external_links.read_text(encoding="utf-8")
        content = replace_exactly_once(
            content,
            r'(slug:\s*"environmental-monitoring",[\s\S]*?version:\s*")[^"]+(")',
            rf'\g<1>{new_version}\2',
            "Environmental Monitoring external-link version",
        )
        write_required_text(external_links, content, "Manager external links module")
    if pkg_path.name == "package.json" and pkg_path.parent.name == "solid-health-app":
        version_ts = pkg_path.parent / "src" / "version.ts"
        set_exported_version(version_ts, "appVersion", new_version, "Solid Health version module")
        external_links = root / ".." / "solid-dataspace-manager" / "src" / "externalLinks.js"
        require_tracked_file(manager_path, external_links, "Manager external links module")
        content = external_links.read_text(encoding="utf-8")
        content = replace_exactly_once(
            content,
            r'(slug:\s*"solid-health-app",[\s\S]*?version:\s*")[^"]+(")',
            rf'\g<1>{new_version}\2',
            "Solid Health external-link version",
        )
        write_required_text(external_links, content, "Manager external links module")
    if pkg_path.name == "package.json" and pkg_path.parent.name == "solid-tours":
        version_ts = pkg_path.parent / "src" / "version.ts"
        set_exported_version(version_ts, "appVersion", new_version, "City Tours version module")

    if pkg_path.name == "package.json" and pkg_path.parent.name == "solid-health-questionnaire":
        version_ts = pkg_path.parent / "src" / "version.ts"
        set_exported_version(
            version_ts,
            "healthQuestionnaireVersion",
            new_version,
            "Questionnaire version module",
        )

        citation_file = pkg_path.parent / "CITATION.cff"
        require_tracked_file(pkg_path.parent, citation_file, "Questionnaire citation file")
        citation = citation_file.read_text(encoding="utf-8")
        citation = replace_exactly_once(
            citation,
            r'(?m)^version:\s*.*$',
            f'version: {new_version}',
            "Questionnaire citation version",
        )
        citation = replace_exactly_once(
            citation,
            r'(?m)^date-released:\s*.*$',
            f'date-released: {datetime.date.today().isoformat()}',
            "Questionnaire citation release date",
        )
        write_required_text(citation_file, citation, "Questionnaire citation file")


    if pkg_path.name == "package.json" and pkg_path.parent.name == "solid-chatbot":
        frontend_pkg = pkg_path.parent / "frontend" / "package.json"
        write_package_version(frontend_pkg, new_version)
        version_js = pkg_path.parent / "frontend" / "src" / "version.js"
        set_exported_version(version_js, "appVersion", new_version, "Solid Chatbot version module")
        external_links = root / ".." / "solid-dataspace-manager" / "src" / "externalLinks.js"
        require_tracked_file(manager_path, external_links, "Manager external links module")
        content = external_links.read_text(encoding="utf-8")
        content = replace_exactly_once(
            content,
            r'(slug:\s*"solid-chatbot",[\s\S]*?version:\s*")[^"]+(")',
            rf'\g<1>{new_version}\2',
            "Solid Chatbot external-link version",
        )
        write_required_text(external_links, content, "Manager external links module")

catalog_version = effective_versions.get(semantic_catalog_repo)
data_manager_version = effective_versions.get(solid_data_manager_repo)
health_version = effective_versions.get(solid_health_repo)
tours_version = effective_versions.get(city_tours_repo)
questionnaire_version = effective_versions.get(solid_health_questionnaire_repo)
chatbot_version = effective_versions.get(solid_chatbot_repo)

if catalog_version and tours_pkg.exists() and city_tours_repo in affected_set:
    sync_dependency(
        tours_pkg,
        "@hoelk-f/semantic-data-catalog",
        catalog_version,
        catalog_pkg,
    )

if manager_pkg.exists() and manager_repo in affected_set:
    manager_effective_specs = [
        (
            "@hoelk-f/solid-data-manager",
            data_manager_version,
            data_manager_pkg,
            "SOLID_DATA_MANAGER_PACKAGE_VERSION",
        ),
        (
            "@hoelk-f/semantic-data-catalog",
            catalog_version,
            catalog_pkg,
            "SEMANTIC_DATA_CATALOG_PACKAGE_VERSION",
        ),
        (
            "@hoelk-f/solid-health-app",
            health_version,
            health_pkg,
            "SOLID_HEALTH_APP_PACKAGE_VERSION",
        ),
        (
            "@hoelk-f/city-tours",
            tours_version,
            tours_pkg,
            "CITY_TOURS_PACKAGE_VERSION",
        ),
        (
            "@hoelk-f/solid-health-questionnaire",
            questionnaire_version,
            questionnaire_pkg,
            "SOLID_HEALTH_QUESTIONNAIRE_PACKAGE_VERSION",
        ),
        (
            "@hoelk-f/solid-chatbot",
            chatbot_version,
            chatbot_pkg,
            "SOLID_CHATBOT_PACKAGE_VERSION",
        ),
    ]
    for package_name, package_version, metadata_path, docker_arg in manager_effective_specs:
        if (
            read_dependency(
                manager_pkg,
                package_name,
                allow_legacy_range=True,
            ) != package_version
            or not lock_dependency_matches(
                manager_pkg,
                package_name,
                package_version,
                allow_legacy_request=True,
            )
            or read_docker_arg(manager_dockerfile, docker_arg) != package_version
        ):
            sync_dependency(
                manager_pkg,
                package_name,
                package_version,
                metadata_path,
                allow_legacy_input=True,
            )
            set_docker_arg(manager_dockerfile, docker_arg, package_version)

versions_path = root / ".." / "solid-dataspace-manager" / "src" / "versions.js"
if manager_repo in affected_set:
    require_tracked_file(manager_path, versions_path, "Manager version module")
    app_version = release_versions[manager_repo]
    set_exported_version(versions_path, "appVersion", app_version, "Manager version module")

version_file = root / "VERSION"
root_key = str(root.resolve()).lower()
root_version_plan = None
if root_key in dirty_set:
    require_tracked_file(root, version_file, "root VERSION file")
    current_root_version = version_file.read_text(encoding="utf-8").strip()
    parse(current_root_version, f"{version_file} version")
    committed_root_version = committed_file_text(root, version_file)
    if committed_root_version is None:
        raise RuntimeError(f"Cannot read committed root version from {version_file}")
    parse(committed_root_version, f"{version_file} committed version")
    if committed_root_version and cmp(current_root_version, committed_root_version) > 0:
        new_root_version = current_root_version
    else:
        new_root_version = bump(
            max_version(
                "0.3.0",
                current_root_version,
                committed_root_version or "0.0.0",
            )
        )
    root_version_plan = {
        "repo": root_key,
        "current": current_root_version,
        "version": new_root_version,
        "source": str(version_file.resolve()),
    }
    write_required_text(version_file, new_root_version + "\n", "root VERSION file")

    citation_file = root / "CITATION.cff"
    require_tracked_file(root, citation_file, "root citation file")
    citation = citation_file.read_text(encoding="utf-8")
    citation = replace_exactly_once(
        citation,
        r'(?m)^version:\s*.*$',
        f'version: "{new_root_version}"',
        "root citation version",
    )
    write_required_text(citation_file, citation, "root citation file")

version_plan = []
for repo_path, pkg_path, _ in targets:
    key = repo_key(repo_path)
    if key not in affected_set or key not in current_versions:
        continue
    version_plan.append(
        {
            "repo": key,
            "current": current_versions[key],
            "version": release_versions[key],
            "source": str(pkg_path.resolve()),
        }
    )
if root_version_plan is not None:
    version_plan.append(root_version_plan)

print(
    json.dumps(
        {
            "affectedRepos": sorted(affected_set),
            "versions": sorted(version_plan, key=lambda item: item["repo"]),
            "changedFiles": sorted(changed_files),
            "skippedUntracked": sorted(skipped_untracked),
        }
    )
)
'@
  $escapedRoot = $root.Replace("\\", "\\\\")
  $script = $script.Replace("__ROOT__", $escapedRoot)
  $previousDirtyJson = $env:DIRTY_JSON
  $previousApplyChanges = $env:APPLY_CHANGES
  try {
    $env:DIRTY_JSON = ConvertTo-Json -InputObject @($dirtyRepos) -Compress
    $env:APPLY_CHANGES = if ($ApplyChanges) { "true" } else { "false" }
    $result = $script | python -
    Assert-LastExitCode "Updating package versions"
  } finally {
    $env:DIRTY_JSON = $previousDirtyJson
    $env:APPLY_CHANGES = $previousApplyChanges
  }
  if (-not $result) { throw "Version planner returned no result." }
  return (ConvertFrom-Json -InputObject ($result -join "`n"))
}

function Assert-ReleasePreflight([string[]]$RepoPaths) {
  Assert-MainBranches -RepoPaths $RepoPaths

  foreach ($repoPath in @($RepoPaths | Select-Object -Unique)) {
    Push-Location $repoPath
    try {
      $unmerged = @(git -c "safe.directory=$repoPath" diff --name-only --diff-filter=U)
      Assert-LastExitCode "Checking unmerged paths for $repoPath"
      if ($unmerged.Count -gt 0) {
        throw "Release aborted: $repoPath contains unmerged paths."
      }

      $gitDirectory = git -c "safe.directory=$repoPath" rev-parse --git-dir
      Assert-LastExitCode "Resolving git directory for $repoPath"
      if (-not [System.IO.Path]::IsPathRooted($gitDirectory)) {
        $gitDirectory = Join-Path $repoPath $gitDirectory
      }
      $gitDirectory = [System.IO.Path]::GetFullPath($gitDirectory)
      $blockedStatePaths = @(
        "MERGE_HEAD",
        "CHERRY_PICK_HEAD",
        "REVERT_HEAD",
        "BISECT_LOG",
        "rebase-apply",
        "rebase-merge",
        "index.lock"
      )
      foreach ($statePath in $blockedStatePaths) {
        if (Test-Path (Join-Path $gitDirectory $statePath)) {
          throw "Release aborted: $repoPath has an active or locked Git operation ($statePath)."
        }
      }
    } finally {
      Pop-Location
    }
  }
}

function Get-OriginMainStates(
  [string[]]$RepoPaths,
  [hashtable]$TrackedOrSelectedFilesByRepo
) {
  $states = New-Object System.Collections.Generic.List[object]
  foreach ($repoPath in @($RepoPaths | Select-Object -Unique)) {
    $key = Get-NormalizedPath $repoPath
    Push-Location $repoPath
    try {
      $originUrl = git -c "safe.directory=$repoPath" remote get-url origin
      Assert-LastExitCode "Reading origin remote for $repoPath"
      if ([string]::IsNullOrWhiteSpace($originUrl)) {
        throw "Release aborted: $repoPath has no usable origin remote."
      }

      $remoteLine = @(
        git -c "safe.directory=$repoPath" ls-remote --exit-code origin refs/heads/main
      )
      Assert-LastExitCode "Reading origin/main for $repoPath"
      if ($remoteLine.Count -ne 1 -or $remoteLine[0] -notmatch '^([0-9a-fA-F]{40})\s+') {
        throw "Release aborted: origin/main could not be resolved unambiguously for $repoPath."
      }
      $remoteCommit = $Matches[1].ToLowerInvariant()

      git -c "safe.directory=$repoPath" cat-file -e "$remoteCommit^{commit}" 2>$null
      if ($LASTEXITCODE -ne 0) {
        throw "Release aborted: the current origin/main commit is not available locally for $repoPath. Run 'git fetch origin main' and rerun the release plan."
      }

      $localCommit = (git -c "safe.directory=$repoPath" rev-parse HEAD).Trim().ToLowerInvariant()
      Assert-LastExitCode "Resolving local HEAD for $repoPath"
      $state = "Synchronized"
      $selectedCount = if ($TrackedOrSelectedFilesByRepo.ContainsKey($key)) {
        @($TrackedOrSelectedFilesByRepo[$key]).Count
      } else { 0 }
      $aheadCommitCount = 0
      if ($localCommit -ne $remoteCommit) {
        git -c "safe.directory=$repoPath" merge-base --is-ancestor $remoteCommit $localCommit
        $remoteIsAncestor = $LASTEXITCODE -eq 0
        if (-not $remoteIsAncestor -and $LASTEXITCODE -ne 1) {
          throw "Comparing local HEAD with origin/main failed for $repoPath."
        }

        if ($remoteIsAncestor) {
          $aheadCommitCount = Assert-LinearAheadRange `
            -RepoPath $repoPath `
            -BaseCommit $remoteCommit `
            -HeadCommit $localCommit
          if ($selectedCount -gt 0) {
            $state = "AheadWithReleaseChanges"
            Write-Host "$repoPath is $aheadCommitCount linear commit(s) ahead of origin/main; approved release changes will be committed on top."
          } else {
            $state = "AheadRecovery"
          }
        } else {
          git -c "safe.directory=$repoPath" merge-base --is-ancestor $localCommit $remoteCommit
          $localIsAncestor = $LASTEXITCODE -eq 0
          if (-not $localIsAncestor -and $LASTEXITCODE -ne 1) {
            throw "Comparing origin/main with local HEAD failed for $repoPath."
          }
          if ($localIsAncestor) {
            throw "Release aborted: $repoPath is behind origin/main. Pull/rebase main first."
          }
          throw "Release aborted: $repoPath has diverged from origin/main. Reconcile main first."
        }
      }

      $states.Add([PSCustomObject]@{
        RepoPath = $repoPath
        State = $state
        LocalCommit = $localCommit
        RemoteCommit = $remoteCommit
        AheadCommitCount = $aheadCommitCount
        HadSelectedChanges = ($selectedCount -gt 0)
      })
    } finally {
      Pop-Location
    }
  }
  return @($states | ForEach-Object { $_ })
}

function Get-NormalizedReleasePlanJson([object]$Plan) {
  $normalized = [ordered]@{
    affectedRepos = @($Plan.affectedRepos | ForEach-Object { [System.IO.Path]::GetFullPath($_).ToLowerInvariant() } | Sort-Object)
    versions = @(
      $Plan.versions |
        ForEach-Object {
          [ordered]@{
            repo = [System.IO.Path]::GetFullPath($_.repo).ToLowerInvariant()
            current = [string]$_.current
            version = [string]$_.version
            source = [System.IO.Path]::GetFullPath($_.source).ToLowerInvariant()
          }
        } |
        Sort-Object { $_.repo }
    )
    changedFiles = @($Plan.changedFiles | ForEach-Object { [System.IO.Path]::GetFullPath($_).ToLowerInvariant() } | Sort-Object)
    skippedUntracked = @($Plan.skippedUntracked | ForEach-Object { [System.IO.Path]::GetFullPath($_).ToLowerInvariant() } | Sort-Object)
  }
  return (ConvertTo-Json -InputObject $normalized -Depth 10 -Compress)
}

function Assert-ReleasePlansEquivalent(
  [object]$ExpectedPlan,
  [object]$ActualPlan
) {
  $expected = Get-NormalizedReleasePlanJson -Plan $ExpectedPlan
  $actual = Get-NormalizedReleasePlanJson -Plan $ActualPlan
  if ($actual -ne $expected) {
    throw "Release aborted: the applied version plan differs from the reviewed read-only plan. No commit or push was attempted."
  }
}

function Get-TrackedBuildChanges(
  [string]$RepoPath,
  [string]$RelativeBuildRoot
) {
  Push-Location $RepoPath
  try {
    $relativePaths = @(
      git -c "safe.directory=$RepoPath" -c core.safecrlf=false diff --name-only --no-renames HEAD -- $RelativeBuildRoot
    )
    Assert-LastExitCode "Reading build outputs for $RepoPath"
    return @(
      $relativePaths |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $RepoPath $_)) }
    )
  } finally {
    Pop-Location
  }
}

function Invoke-RequiredBuilds([string]$root, [string[]]$AffectedRepos) {
  $semanticCatalogPath = Resolve-Path (Join-Path $root "..\semantic-data-catalog") -ErrorAction Stop
  $solidDataManagerPath = Resolve-Path (Join-Path $root "..\solid-data-manager") -ErrorAction Stop
  $solidHealthPath = Resolve-Path (Join-Path $root "..\solid-health-app") -ErrorAction Stop
  $cityToursPath = Resolve-Path (Join-Path $root "..\solid-tours") -ErrorAction Stop
  $solidHealthQuestionnairePath = Resolve-Path (Join-Path $root "..\solid-health-questionnaire") -ErrorAction Stop
  $solidChatbotPath = Resolve-Path (Join-Path $root "..\solid-chatbot") -ErrorAction Stop
  $buildFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

  $semanticCatalogRepo = $null
  if ($semanticCatalogPath) {
    $semanticCatalogRepo = $semanticCatalogPath.Path.ToLowerInvariant()
  }
  $affectedNormalized = @(
    $AffectedRepos | ForEach-Object {
      $resolved = Resolve-Path $_ -ErrorAction SilentlyContinue
      if ($resolved) { $resolved.Path.ToLowerInvariant() }
    }
  )

  if ($semanticCatalogPath -and $affectedNormalized -contains $semanticCatalogRepo) {
    $frontendPath = Join-Path $semanticCatalogPath.Path "frontend"
    if (Test-Path (Join-Path $frontendPath "package.json")) {
      Write-Host "Building semantic-data-catalog embed dist"
      Push-Location $frontendPath
      try {
        npm run build:lib | Out-Host
        Assert-LastExitCode "Building semantic-data-catalog embed dist"
      } finally {
        Pop-Location
      }
      foreach ($file in @(Get-TrackedBuildChanges -RepoPath $semanticCatalogPath.Path -RelativeBuildRoot "frontend/dist")) {
        [void]$buildFiles.Add($file)
      }
    }
  }

  $solidDataManagerRepo = $solidDataManagerPath.Path.ToLowerInvariant()
  if ($affectedNormalized -contains $solidDataManagerRepo) {
    Write-Host "Building solid-data-manager embed dist"
    Push-Location $solidDataManagerPath.Path
    try {
      npm run build:lib | Out-Host
      Assert-LastExitCode "Building solid-data-manager embed dist"
    } finally {
      Pop-Location
    }
    foreach ($file in @(Get-TrackedBuildChanges -RepoPath $solidDataManagerPath.Path -RelativeBuildRoot "dist")) {
      [void]$buildFiles.Add($file)
    }
  }

  $solidHealthRepo = $solidHealthPath.Path.ToLowerInvariant()
  if ($affectedNormalized -contains $solidHealthRepo) {
    Write-Host "Building solid-health-app embed dist"
    Push-Location $solidHealthPath.Path
    try {
      npm run build:lib | Out-Host
      Assert-LastExitCode "Building solid-health-app embed dist"
    } finally {
      Pop-Location
    }
    foreach ($file in @(Get-TrackedBuildChanges -RepoPath $solidHealthPath.Path -RelativeBuildRoot "dist")) {
      [void]$buildFiles.Add($file)
    }
  }

  if ($cityToursPath) {
    $cityToursRepo = $cityToursPath.Path.ToLowerInvariant()
    if ($affectedNormalized -contains $cityToursRepo -and (Test-Path (Join-Path $cityToursPath.Path "package.json"))) {
      Write-Host "Building city-tours embed dist"
      Push-Location $cityToursPath.Path
      try {
        npm run build:lib | Out-Host
        Assert-LastExitCode "Building city-tours embed dist"
      } finally {
        Pop-Location
      }
      foreach ($file in @(Get-TrackedBuildChanges -RepoPath $cityToursPath.Path -RelativeBuildRoot "dist")) {
        [void]$buildFiles.Add($file)
      }
    }
  }

  if ($solidHealthQuestionnairePath) {
    $solidHealthQuestionnaireRepo = $solidHealthQuestionnairePath.Path.ToLowerInvariant()
    if ($affectedNormalized -contains $solidHealthQuestionnaireRepo -and (Test-Path (Join-Path $solidHealthQuestionnairePath.Path "package.json"))) {
      Write-Host "Building solid-health-questionnaire embed dist"
      Push-Location $solidHealthQuestionnairePath.Path
      try {
        npm run build:lib | Out-Host
        Assert-LastExitCode "Building solid-health-questionnaire embed dist"
      } finally {
        Pop-Location
      }
      foreach ($file in @(Get-TrackedBuildChanges -RepoPath $solidHealthQuestionnairePath.Path -RelativeBuildRoot "dist")) {
        [void]$buildFiles.Add($file)
      }
    }
  }

  $solidChatbotRepo = $solidChatbotPath.Path.ToLowerInvariant()
  if ($affectedNormalized -contains $solidChatbotRepo) {
    Write-Host "Building solid-chatbot embed dist"
    Push-Location $solidChatbotPath.Path
    try {
      npm run build:lib | Out-Host
      Assert-LastExitCode "Building solid-chatbot embed dist"
    } finally {
      Pop-Location
    }
    foreach ($file in @(Get-TrackedBuildChanges -RepoPath $solidChatbotPath.Path -RelativeBuildRoot "frontend/dist")) {
      [void]$buildFiles.Add($file)
    }
  }

  return @($buildFiles)
}

function Get-OwningRepoPath([string]$FilePath, [string[]]$RepoPaths) {
  $fullFilePath = [System.IO.Path]::GetFullPath($FilePath)
  $matches = @(
    foreach ($repoPath in $RepoPaths) {
      $fullRepoPath = [System.IO.Path]::GetFullPath($repoPath).TrimEnd("\", "/")
      $prefix = $fullRepoPath + [System.IO.Path]::DirectorySeparatorChar
      if (
        $fullFilePath.Equals($fullRepoPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullFilePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
      ) {
        $fullRepoPath
      }
    }
  )
  if ($matches.Count -eq 0) { return $null }
  return ($matches | Sort-Object Length -Descending | Select-Object -First 1)
}

function Add-FilesToReleaseMap(
  [hashtable]$ReleaseFilesByRepo,
  [string[]]$Files,
  [string[]]$RepoPaths
) {
  foreach ($file in @($Files)) {
    if ([string]::IsNullOrWhiteSpace($file)) { continue }
    $owner = Get-OwningRepoPath -FilePath $file -RepoPaths $RepoPaths
    if (-not $owner) {
      throw "Release file is outside every configured repository: $file"
    }
    $key = Get-NormalizedPath $owner
    if (-not $ReleaseFilesByRepo.ContainsKey($key)) {
      $ReleaseFilesByRepo[$key] = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    }
    [void]$ReleaseFilesByRepo[$key].Add([System.IO.Path]::GetFullPath($file))
  }
}

function Assert-OriginMainUnchanged([string]$RepoPath, [string]$ExpectedCommit) {
  $remoteLine = @(git -c "safe.directory=$RepoPath" -C $RepoPath ls-remote --exit-code origin refs/heads/main)
  Assert-LastExitCode "Rechecking origin/main for $RepoPath"
  if ($remoteLine.Count -ne 1 -or $remoteLine[0] -notmatch '^([0-9a-fA-F]{40})\s+') {
    throw "origin/main could not be resolved unambiguously for $RepoPath."
  }
  if ($Matches[1].ToLowerInvariant() -ne $ExpectedCommit.ToLowerInvariant()) {
    throw "Release aborted: origin/main advanced after preflight for $RepoPath. Rerun the release plan."
  }
}

function Invoke-OriginMainPush(
  [string]$RepoPath,
  [string]$ExpectedLocalCommit,
  [string]$ExpectedRemoteCommit
) {
  Assert-MainHeadState `
    -RepoPath $RepoPath `
    -ExpectedCommit $ExpectedLocalCommit `
    -Context "immediately before push"
  $lease = "--force-with-lease=refs/heads/main:$ExpectedRemoteCommit"
  $refspec = "${ExpectedLocalCommit}:refs/heads/main"
  git -c "safe.directory=$RepoPath" -C $RepoPath push $lease origin $refspec | Out-Host
  Assert-LastExitCode "Pushing $RepoPath to origin/main"
}

function Assert-PushDryRuns(
  [string[]]$RepoPaths,
  [object[]]$OriginStates
) {
  foreach ($repoPath in @($RepoPaths | Select-Object -Unique)) {
    $originState = $OriginStates | Where-Object { $_.RepoPath -eq $repoPath } | Select-Object -First 1
    if (-not $originState) {
      throw "No origin/main preflight state exists for push dry-run: $repoPath"
    }
    Write-Host "Checking push access (dry-run): $repoPath"
    $lease = "--force-with-lease=refs/heads/main:$($originState.RemoteCommit)"
    $refspec = "$($originState.LocalCommit):refs/heads/main"
    git -c "safe.directory=$repoPath" -C $repoPath push --dry-run $lease origin $refspec | Out-Host
    Assert-LastExitCode "Dry-running push to origin/main for $repoPath"
  }
}

function Invoke-GitReleaseCommit(
  [string]$RepoPath,
  [string]$Message,
  [string[]]$ReleaseFiles,
  [string]$ExpectedLocalCommit,
  [string]$ExpectedRemoteCommit,
  [hashtable]$ExpectedFileFingerprints,
  [switch]$PushExistingCommits,
  [switch]$RequireReleaseCommit
) {
  if (-not (Test-Path (Join-Path $repoPath ".git"))) {
    throw "Cannot publish repository without .git: $repoPath"
  }

  Assert-MainHeadState `
    -RepoPath $repoPath `
    -ExpectedCommit $ExpectedLocalCommit `
    -Context "after release preflight"
  Assert-OnlyApprovedRepoChanges `
    -RepoPath $repoPath `
    -ApprovedFiles $ReleaseFiles `
    -Context "after release files were prepared"
  Assert-RequiredRepoChangesPresent `
    -RepoPath $repoPath `
    -RequiredFiles $ReleaseFiles `
    -Context "after release files were prepared"
  Assert-RepoFileFingerprints `
    -RepoPath $repoPath `
    -Files $ReleaseFiles `
    -ExpectedFingerprints $ExpectedFileFingerprints `
    -Context "after release files were prepared"

  $repoRoot = [System.IO.Path]::GetFullPath($repoPath).TrimEnd("\", "/")
  $repoPrefix = $repoRoot + [System.IO.Path]::DirectorySeparatorChar
  $relativePaths = @(
    $ReleaseFiles |
      Select-Object -Unique |
      ForEach-Object {
        $fullPath = [System.IO.Path]::GetFullPath($_)
        if (-not $fullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
          throw "Refusing to stage a path outside $repoPath`: $fullPath"
        }
        ":(literal)$($fullPath.Substring($repoPrefix.Length).Replace("\", "/"))"
      }
  )
  if ($relativePaths.Count -eq 0) {
    if ($RequireReleaseCommit) {
      throw "Release aborted: approved initial changes in $repoPath did not produce release files for the required follow-up commit."
    }
    if ($PushExistingCommits) {
      Assert-OriginMainUnchanged -RepoPath $repoPath -ExpectedCommit $ExpectedRemoteCommit
      Write-Host "Existing local commit(s) are ready for recovery push: $repoPath"
    } else {
      Write-Host "No approved release files: $repoPath"
    }
    return
  }

  Push-Location $repoPath
  try {
    Assert-OriginMainUnchanged -RepoPath $repoPath -ExpectedCommit $ExpectedRemoteCommit
    $statusArguments = @("-c", "safe.directory=$repoPath", "status", "--porcelain=v1", "--") + $relativePaths
    $scopedStatus = @(& git @statusArguments)
    Assert-LastExitCode "Reading scoped changes for $repoPath"
    if ($scopedStatus.Count -eq 0) {
      if ($RequireReleaseCommit) {
        throw "Release aborted: approved initial changes in $repoPath disappeared before the required follow-up commit."
      }
      if ($PushExistingCommits) {
        Write-Host "Existing local commit(s) are ready for recovery push: $repoPath"
      } else {
        Write-Host "No release changes: $repoPath"
      }
      return
    }

    Write-Host "Updating: $repoPath"
    $addArguments = @("-c", "safe.directory=$repoPath", "add", "-A", "--") + $relativePaths
    & git @addArguments
    Assert-LastExitCode "Staging changes in $repoPath"
    Assert-OnlyApprovedRepoChanges `
      -RepoPath $repoPath `
      -ApprovedFiles $ReleaseFiles `
      -Context "while staging the release commit"

    # --only prevents an unrelated path that was staged concurrently from
    # leaking into this release commit. Every initial dirty path is already in
    # ReleaseFiles, so intentional feature changes are retained.
    $commitArguments = @("-c", "safe.directory=$repoPath", "commit", "--only", "-m", $Message, "--") + $relativePaths
    & git @commitArguments | Out-Host
    Assert-LastExitCode "Committing changes in $repoPath"

    $releaseCommit = Get-RepoHeadCommit -RepoPath $repoPath
    $firstParent = (git -c "safe.directory=$repoPath" rev-parse "$releaseCommit^").Trim().ToLowerInvariant()
    Assert-LastExitCode "Validating release commit parent for $repoPath"
    if ($firstParent -ne $ExpectedLocalCommit.ToLowerInvariant()) {
      throw "Release aborted: the release commit in $repoPath was not created directly on the preflight HEAD."
    }
    Assert-MainHeadState `
      -RepoPath $repoPath `
      -ExpectedCommit $releaseCommit `
      -Context "after creating the release commit"
  } finally {
    Pop-Location
  }
}

function Get-RequiredBuildLabels([string]$Root, [string[]]$AffectedRepos) {
  $labels = @()
  $buildRepos = @(
    @{ Path = Join-Path $Root "..\semantic-data-catalog"; Label = "semantic-data-catalog embed dist" },
    @{ Path = Join-Path $Root "..\solid-data-manager"; Label = "solid-data-manager embed dist" },
    @{ Path = Join-Path $Root "..\solid-health-app"; Label = "solid-health-app embed dist" },
    @{ Path = Join-Path $Root "..\solid-tours"; Label = "city-tours embed dist" },
    @{ Path = Join-Path $Root "..\solid-health-questionnaire"; Label = "solid-health-questionnaire embed dist" },
    @{ Path = Join-Path $Root "..\solid-chatbot"; Label = "solid-chatbot embed dist" }
  )
  $affectedKeys = @($AffectedRepos | ForEach-Object { Get-NormalizedPath $_ })
  foreach ($buildRepo in $buildRepos) {
    if ((Get-NormalizedPath $buildRepo.Path) -in $affectedKeys) {
      $labels += $buildRepo.Label
    }
  }
  return $labels
}

function Show-ReleasePlan(
  [object]$Plan,
  [string[]]$AffectedRepoPaths,
  [hashtable]$InitialFilesByRepo,
  [hashtable]$UntrackedFilesByRepo,
  [bool]$IncludeUntrackedFiles,
  [string[]]$RepoPaths,
  [string[]]$PublishOrder,
  [object[]]$OriginStates,
  [string]$Root
) {
  Write-Host "Release plan (read-only)"
  Write-Host ""
  foreach ($version in @($Plan.versions)) {
    Write-Host "  $(Split-Path $version.repo -Leaf): $($version.current) -> $($version.version)"
  }
  if (@($Plan.versions).Count -eq 0) {
    Write-Host "  No version changes."
  }

  $buildLabels = @(Get-RequiredBuildLabels -Root $Root -AffectedRepos $AffectedRepoPaths)
  Write-Host ""
  Write-Host "Builds:"
  if ($buildLabels.Count -eq 0) { Write-Host "  None" }
  foreach ($label in $buildLabels) { Write-Host "  $label" }

  Write-Host ""
  Write-Host "Files selected for release (initial snapshot + generated metadata):"
  foreach ($repoPath in $AffectedRepoPaths) {
    $key = Get-NormalizedPath $repoPath
    [object[]]$initialFiles = @()
    if ($InitialFilesByRepo.ContainsKey($key)) {
      $initialFiles = @($InitialFilesByRepo[$key])
    }
    $generatedFiles = @(
      @($Plan.changedFiles) | Where-Object {
        (Get-OwningRepoPath -FilePath $_ -RepoPaths $RepoPaths) -eq $repoPath
      }
    )
    $combinedFiles = @($initialFiles) + @($generatedFiles)
    Write-Host "  $(Split-Path $repoPath -Leaf):"
    foreach ($file in @($combinedFiles | Select-Object -Unique)) {
      Write-Host "    $file"
    }
    if (($initialFiles.Count + $generatedFiles.Count) -eq 0) { Write-Host "    None" }
  }

  if (@($Plan.skippedUntracked).Count -gt 0) {
    Write-Host ""
    Write-Host "Existing untracked generated files that will not be modified:"
    foreach ($file in @($Plan.skippedUntracked)) { Write-Host "  $file" }
  }

  $untrackedCount = 0
  foreach ($repoPath in $RepoPaths) {
    $key = Get-NormalizedPath $repoPath
    if (-not $UntrackedFilesByRepo.ContainsKey($key)) { continue }
    $files = @($UntrackedFilesByRepo[$key])
    if ($files.Count -eq 0) { continue }
    $untrackedCount += $files.Count
    Write-Host ""
    $disposition = if ($IncludeUntrackedFiles) { "INCLUDED by -IncludeUntracked" } else { "EXCLUDED" }
    Write-Host "Untracked files in $(Split-Path $repoPath -Leaf) ($disposition):"
    foreach ($file in $files) { Write-Host "  $file" }
  }
  if ($untrackedCount -gt 0 -and -not $IncludeUntrackedFiles) {
    Write-Host ""
    Write-Host "A real release will stop before writes. Review these files and rerun with -IncludeUntracked to include them explicitly."
  }

  Write-Host ""
  Write-Host "Publish order:"
  foreach ($repoPath in $PublishOrder) { Write-Host "  $(Split-Path $repoPath -Leaf)" }
  $aheadStates = @($OriginStates | Where-Object { $_.AheadCommitCount -gt 0 })
  if ($aheadStates.Count -gt 0) {
    Write-Host ""
    Write-Host "Existing local commits included in the release:"
    foreach ($state in $aheadStates) {
      Write-Host "  $(Split-Path $state.RepoPath -Leaf): $($state.AheadCommitCount) linear commit(s) ahead ($($state.State))"
    }
  }
  Write-Host ""
  Write-Host "The Manager remains last. Its GitHub workflow verifies and waits for all exact embed package versions."
}

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

$repos = Get-RepoPaths | Select-Object -Unique
$dirty = New-Object System.Collections.Generic.List[string]
$initialFilesByRepo = @{}
$observedFilesByRepo = @{}
$initialFingerprintsByRepo = @{}
$untrackedFilesByRepo = @{}
foreach ($repo in $repos) {
  if (-not (Test-Path (Join-Path $repo ".git"))) {
    throw "Configured repository has no .git directory: $repo"
  }
  $snapshot = Get-RepoChangeSnapshot -RepoPath $repo
  $trackedFiles = @($snapshot.TrackedFiles)
  $untrackedFiles = @($snapshot.UntrackedFiles)
  $repoKey = Get-NormalizedPath $repo
  $untrackedFilesByRepo[$repoKey] = $untrackedFiles
  $observedFilesByRepo[$repoKey] = @($trackedFiles) + @($untrackedFiles)
  $selectedFiles = @($trackedFiles)
  if ($IncludeUntracked) {
    $selectedFiles += $untrackedFiles
  }
  if ($selectedFiles.Count -gt 0) {
    $dirty.Add($repo)
    $initialFilesByRepo[$repoKey] = $selectedFiles
    $initialFingerprintsByRepo[$repoKey] = Get-RepoFileFingerprints `
      -RepoPath $repo `
      -Files $selectedFiles
  }
}

$plan = Update-PackageVersions -root $root -dirtyRepos $dirty
$repoByKey = @{}
foreach ($repo in $repos) { $repoByKey[(Get-NormalizedPath $repo)] = $repo }
$requiredTargetRepos = @(
  $root,
  (Join-Path $root "..\solid-dataspace-manager"),
  (Join-Path $root "..\solid-data-manager"),
  (Join-Path $root "..\solid-data-connection-sync-worker"),
  (Join-Path $root "..\environmental-monitoring"),
  (Join-Path $root "..\solid-health-app"),
  (Join-Path $root "..\solid-health-questionnaire"),
  (Join-Path $root "..\solid-tours"),
  (Join-Path $root "..\semantic-data-catalog"),
  (Join-Path $root "..\solid-chatbot")
)
foreach ($requiredRepo in $requiredTargetRepos) {
  $requiredKey = Get-NormalizedPath $requiredRepo
  if (-not $repoByKey.ContainsKey($requiredKey)) {
    throw "Required version target is not configured in repos.yaml: $requiredRepo"
  }
}
$affectedRepoPaths = @()
foreach ($affectedRepo in @($plan.affectedRepos)) {
  $affectedKey = Get-NormalizedPath $affectedRepo
  if (-not $repoByKey.ContainsKey($affectedKey)) {
    throw "Version planner returned an unconfigured repository: $affectedRepo"
  }
  $affectedRepoPaths += $repoByKey[$affectedKey]
}

$managerPath = Resolve-Path (Join-Path $root "..\solid-dataspace-manager") -ErrorAction Stop
# This is a read-only invariant check and therefore also runs for -WhatIf.
Assert-ManagerPublishGuard -ManagerPath $managerPath.Path
Assert-PackageReleaseWorkflows -Root $root

# Resolve the same complete publish scope for preview and execution. This uses
# ls-remote plus already-present commit objects and deliberately does not fetch
# or update any Git reference during -WhatIf.
Assert-ReleasePreflight -RepoPaths $repos
$originStates = @(
  Get-OriginMainStates `
    -RepoPaths $repos `
    -TrackedOrSelectedFilesByRepo $initialFilesByRepo
)
foreach ($repoPath in $repos) {
  $key = Get-NormalizedPath $repoPath
  $observedFiles = if ($observedFilesByRepo.ContainsKey($key)) {
    @($observedFilesByRepo[$key])
  } else { @() }
  Assert-OnlyApprovedRepoChanges `
    -RepoPath $repoPath `
    -ApprovedFiles $observedFiles `
    -Context "while preparing the release plan"
  if ($initialFilesByRepo.ContainsKey($key)) {
    Assert-RepoFileFingerprints `
      -RepoPath $repoPath `
      -Files @($initialFilesByRepo[$key]) `
      -ExpectedFingerprints $initialFingerprintsByRepo[$key] `
      -Context "while preparing the release plan"
  }
}
$recoveryRepoPaths = @(
  $originStates |
    Where-Object { $_.State -eq "AheadRecovery" } |
    ForEach-Object { $_.RepoPath }
)
$publishRepoPaths = @($affectedRepoPaths + $recoveryRepoPaths | Select-Object -Unique)
$publishOrder = @(
  $repos | Where-Object {
    $_ -in $publishRepoPaths -and $_ -ne $managerPath.Path
  }
)
if ($managerPath.Path -in $publishRepoPaths) {
  # Embedded repositories are committed and pushed first. The Manager's
  # docker-image workflow then waits for every exact package pin before build.
  $publishOrder += $managerPath.Path
}

Show-ReleasePlan `
  -Plan $plan `
  -AffectedRepoPaths $affectedRepoPaths `
  -InitialFilesByRepo $initialFilesByRepo `
  -UntrackedFilesByRepo $untrackedFilesByRepo `
  -IncludeUntrackedFiles ([bool]$IncludeUntracked) `
  -RepoPaths $repos `
  -PublishOrder $publishOrder `
  -OriginStates $originStates `
  -Root $root

if ($WhatIf) {
  Write-Host "WhatIf: no files were changed, no builds ran, and Git was not mutated."
  return
}

$untrackedReleaseFiles = @(
  foreach ($repoPath in $repos) {
    $key = Get-NormalizedPath $repoPath
    if ($untrackedFilesByRepo.ContainsKey($key)) {
      @($untrackedFilesByRepo[$key])
    }
  }
)
if (-not $IncludeUntracked -and $untrackedReleaseFiles.Count -gt 0) {
  throw "Release aborted before writes: $($untrackedReleaseFiles.Count) untracked file(s) exist. Review the WhatIf plan and rerun with -IncludeUntracked to include them explicitly."
}

if ($affectedRepoPaths.Count -eq 0 -and $recoveryRepoPaths.Count -eq 0) {
  Write-Host "Nothing to release."
  return
}

Assert-PushDryRuns -RepoPaths $publishOrder -OriginStates $originStates

# Revalidate every approved input and Git reference immediately before the
# first write. No pathname-only approval may hide changed file content.
foreach ($repoPath in $repos) {
  $key = Get-NormalizedPath $repoPath
  $approvedInitialFiles = if ($initialFilesByRepo.ContainsKey($key)) {
    @($initialFilesByRepo[$key])
  } else { @() }
  Assert-OnlyApprovedRepoChanges `
    -RepoPath $repoPath `
    -ApprovedFiles $approvedInitialFiles `
    -Context "immediately before applying the release plan"
  if ($initialFilesByRepo.ContainsKey($key)) {
    Assert-RequiredRepoChangesPresent `
      -RepoPath $repoPath `
      -RequiredFiles $approvedInitialFiles `
      -Context "immediately before applying the release plan"
    Assert-RepoFileFingerprints `
      -RepoPath $repoPath `
      -Files $approvedInitialFiles `
      -ExpectedFingerprints $initialFingerprintsByRepo[$key] `
      -Context "immediately before applying the release plan"
  }
  $originState = $originStates | Where-Object { $_.RepoPath -eq $repoPath } | Select-Object -First 1
  Assert-MainHeadState `
    -RepoPath $repoPath `
    -ExpectedCommit $originState.LocalCommit `
    -Context "immediately before applying the release plan"
  Assert-OriginMainUnchanged -RepoPath $repoPath -ExpectedCommit $originState.RemoteCommit
}

$appliedPlan = $plan
$buildFiles = @()
if ($affectedRepoPaths.Count -gt 0) {
  $appliedPlan = Update-PackageVersions -root $root -dirtyRepos $dirty -ApplyChanges
  Assert-ReleasePlansEquivalent -ExpectedPlan $plan -ActualPlan $appliedPlan
  $buildFiles = @(Invoke-RequiredBuilds -root $root -AffectedRepos $affectedRepoPaths)
}

$releaseFilesByRepo = @{}
foreach ($repoPath in $affectedRepoPaths) {
  $key = Get-NormalizedPath $repoPath
  if ($initialFilesByRepo.ContainsKey($key)) {
    Add-FilesToReleaseMap `
      -ReleaseFilesByRepo $releaseFilesByRepo `
      -Files @($initialFilesByRepo[$key]) `
      -RepoPaths $repos
  }
}
Add-FilesToReleaseMap -ReleaseFilesByRepo $releaseFilesByRepo -Files @($appliedPlan.changedFiles) -RepoPaths $repos
Add-FilesToReleaseMap -ReleaseFilesByRepo $releaseFilesByRepo -Files $buildFiles -RepoPaths $repos

$publishRepoKeys = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
foreach ($repoPath in $publishRepoPaths) {
  [void]$publishRepoKeys.Add((Get-NormalizedPath $repoPath))
}
foreach ($releaseRepoKey in @($releaseFilesByRepo.Keys)) {
  if (-not $publishRepoKeys.Contains($releaseRepoKey)) {
    throw "Release aborted: the applied plan produced files for a repository outside the reviewed publish scope: $releaseRepoKey"
  }
}

# A build or concurrent process may not introduce files outside the exact
# initial/planned/generated release set. Check every configured repository,
# including repositories that are not expected to be published.
foreach ($repoPath in $repos) {
  $key = Get-NormalizedPath $repoPath
  $approvedReleaseFiles = if ($releaseFilesByRepo.ContainsKey($key)) {
    @($releaseFilesByRepo[$key])
  } else { @() }
  Assert-OnlyApprovedRepoChanges `
    -RepoPath $repoPath `
    -ApprovedFiles $approvedReleaseFiles `
    -Context "after release builds"
  Assert-RequiredRepoChangesPresent `
    -RepoPath $repoPath `
    -RequiredFiles $approvedReleaseFiles `
    -Context "after release builds"
  if ($initialFilesByRepo.ContainsKey($key)) {
    Assert-RequiredRepoChangesPresent `
      -RepoPath $repoPath `
      -RequiredFiles @($initialFilesByRepo[$key]) `
      -Context "after release builds"
  }
}

$preparedFingerprintsByRepo = @{}
foreach ($repoPath in $publishOrder) {
  $key = Get-NormalizedPath $repoPath
  $releaseFiles = if ($releaseFilesByRepo.ContainsKey($key)) {
    @($releaseFilesByRepo[$key])
  } else { @() }
  $preparedFingerprintsByRepo[$key] = Get-RepoFileFingerprints `
    -RepoPath $repoPath `
    -Files $releaseFiles
}

$committedHeadsByRepo = @{}
foreach ($repo in $publishOrder) {
  $key = Get-NormalizedPath $repo
  $releaseFiles = if ($releaseFilesByRepo.ContainsKey($key)) { @($releaseFilesByRepo[$key]) } else { @() }
  $originState = $originStates | Where-Object { $_.RepoPath -eq $repo } | Select-Object -First 1
  if (-not $originState) {
    throw "No origin/main preflight state exists for $repo"
  }
  Invoke-GitReleaseCommit `
    -RepoPath $repo `
    -Message $CommitMessage `
    -ReleaseFiles $releaseFiles `
    -ExpectedLocalCommit $originState.LocalCommit `
    -ExpectedRemoteCommit $originState.RemoteCommit `
    -ExpectedFileFingerprints $preparedFingerprintsByRepo[$key] `
    -PushExistingCommits:($originState.State -eq "AheadRecovery") `
    -RequireReleaseCommit:([bool]$originState.HadSelectedChanges)
  $committedHeadsByRepo[$key] = Get-RepoHeadCommit -RepoPath $repo
}

# Commit every repository first. Only after all local commits succeeded do we
# start pushing, preserving Manager-last ordering and improving recoverability.
foreach ($repo in $publishOrder) {
  $key = Get-NormalizedPath $repo
  $originState = $originStates | Where-Object { $_.RepoPath -eq $repo } | Select-Object -First 1
  Assert-MainHeadState `
    -RepoPath $repo `
    -ExpectedCommit $committedHeadsByRepo[$key] `
    -Context "before push"
  Assert-OnlyApprovedRepoChanges `
    -RepoPath $repo `
    -ApprovedFiles @() `
    -Context "before push"
  [void](Assert-LinearAheadRange `
    -RepoPath $repo `
    -BaseCommit $originState.RemoteCommit `
    -HeadCommit $committedHeadsByRepo[$key])
  Assert-OriginMainUnchanged -RepoPath $repo -ExpectedCommit $originState.RemoteCommit
  Invoke-OriginMainPush `
    -RepoPath $repo `
    -ExpectedLocalCommit $committedHeadsByRepo[$key] `
    -ExpectedRemoteCommit $originState.RemoteCommit
}
