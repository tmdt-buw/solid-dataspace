"""Publish committed branches to the Dataspace mirrors without joining histories.

Python 3.9+, Git and (for the TMDT Actions check) GitHub CLI. No third-party
Python packages. All fetches and mirror commits live in temporary bare repos;
the working checkouts, branches, tags and remote configuration stay untouched.
"""

import argparse
from contextlib import ExitStack
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]


class SyncError(RuntimeError):
    pass


def run(command, *, input=None):
    result = subprocess.run(command, input=input, capture_output=True, text=True,
                            encoding="utf-8", errors="replace",
                            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"}, timeout=180)
    if result.returncode:
        raise SyncError(result.stderr.strip() or result.stdout.strip() or
                        f"Command failed (exit {result.returncode})")
    return result.stdout.strip()


def git(repo, *args, input=None):
    return run(["git", "-c", f"safe.directory={repo}", "-C", str(repo), *args], input=input)


def repository_id(url):
    """Accept HTTPS and SSH spellings of the same target, never credentials."""
    if url.startswith("git@"):
        match = re.fullmatch(r"git@([^:]+):(.+)", url)
        if not match:
            raise SyncError("Invalid SSH repository URL")
        host, path = match.groups()
    else:
        parsed = urlsplit(url)
        if parsed.scheme not in ("https", "ssh") or parsed.password or parsed.query or parsed.fragment:
            raise SyncError("Only credential-free HTTPS/SSH repository URLs are allowed")
        if parsed.username and not (parsed.scheme == "ssh" and parsed.username == "git"):
            raise SyncError("Repository URLs must not contain credentials")
        if not parsed.hostname or parsed.port:
            raise SyncError("Unexpected repository host/port")
        host, path = parsed.hostname, parsed.path.lstrip("/")
    path = path.rstrip("/")
    if path.endswith(".git"):
        path = path[:-4]
    if any(part in ("", ".", "..") for part in path.split("/")):
        raise SyncError("Invalid repository path")
    return host.lower() + "/" + path


def project_paths(workspace):
    # Read only the repos block of the existing manifest, including Windows paths.
    paths = {"solid-dataspace": workspace.resolve()}
    in_repos = False
    key = None
    declared = set()
    for line in (workspace / "repos.yaml").read_text(encoding="utf-8").splitlines():
        if line == "repos:":
            in_repos = True
        elif line and not line[0].isspace() and not line.startswith("#"):
            in_repos = False
        elif in_repos:
            match = re.fullmatch(r"  ([\w-]+):", line)
            if match:
                key = match[1]
                if key in declared or key == "solid-dataspace":
                    raise SyncError(f"Duplicate repository in repos.yaml: {key}")
                declared.add(key)
            elif re.match(r"    path:", line):
                value = line.split(":", 1)[1].strip().strip("\"'")
                if not key or key in paths:
                    raise SyncError("Invalid or duplicate repository path in repos.yaml")
                paths[key] = (workspace / value.replace("\\", "/")).resolve()
    if not declared or declared != set(paths) - {"solid-dataspace"}:
        raise SyncError("Every repository in repos.yaml needs exactly one path")
    if len(set(paths.values())) != len(paths):
        raise SyncError("Repository paths must be distinct")
    return paths


def load_projects(workspace):
    paths = project_paths(workspace)
    targets = json.loads((ROOT / "push-targets.json").read_text(encoding="utf-8"))
    if set(paths) != set(targets):
        raise SyncError("repos.yaml and push-targets.json must cover the same repositories, including solid-dataspace")
    for name, urls in targets.items():
        if set(urls) != {"origin", "gitlab", "tmdt"}:
            raise SyncError(f"{name}: origin, gitlab and tmdt targets are required")
        prefixes = {"origin": "github.com/hoelk-f/", "tmdt": "github.com/tmdt-buw/",
                    "gitlab": "git.uni-wuppertal.de/tmdt/projects/dataspaces/gesundes-tal/"}
        for remote, url in urls.items():
            if not repository_id(url).startswith(prefixes[remote]):
                raise SyncError(f"{name}: target is outside the approved {remote} namespace")
        if name == "plasma" and repository_id(urls["tmdt"]) != "github.com/tmdt-buw/plasma-dataspace":
            raise SyncError("PLASMA must target tmdt-buw/plasma-dataspace, never the upstream repository")
    return [(name, path, targets[name]) for name, path in paths.items()]


def validate_remotes(repo, urls, selected):
    # Check fetch AND every push URL. A hidden pushurl must not redirect a release.
    for remote in dict.fromkeys(["origin", *selected]):
        for args in [("remote", "get-url", "--all", remote),
                     ("remote", "get-url", "--push", "--all", remote)]:
            actual = git(repo, *args).splitlines()
            if not actual or any(repository_id(url) != repository_id(urls[remote]) for url in actual):
                raise SyncError(f"{repo.name}: {remote} points somewhere other than push-targets.json; review its configuration")


def check_actions_disabled(url):
    name = repository_id(url).removeprefix("github.com/")
    result = json.loads(run(["gh", "api", f"repos/{name}/actions/permissions"]))
    if result.get("enabled") is not False:
        raise SyncError(f"{name}: Actions must remain disabled on the mirror")


def remote_tip(repo, url, branch):
    lines = git(repo, "ls-remote", "--refs", url, f"refs/heads/{branch}").splitlines()
    if len(lines) != 1:
        raise SyncError(f"Target branch {branch} is missing; review initial publication first")
    return lines[0].split()[0]


def fetch_tip(repo, url, branch, remote):
    git(repo, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head", url,
        f"refs/heads/{branch}:refs/sync/{remote}")
    return git(repo, "rev-parse", f"refs/sync/{remote}")


def is_ancestor(repo, ancestor, child):
    try:
        git(repo, "merge-base", "--is-ancestor", ancestor, child)
        return True
    except SyncError:
        return False


def tree(repo, commit):
    return git(repo, "rev-parse", commit + "^{tree}")


def validate_mirror_base(repo, parent, source):
    """Reject edits on the mirror or rollback to a stale original branch."""
    parent_tree = tree(repo, parent)
    if parent_tree == tree(repo, source):
        return
    message = git(repo, "show", "-s", "--format=%B", parent)
    match = re.search(r"^Source commit: ([a-f0-9]{40,64})$", message, re.MULTILINE)
    if match:
        previous = match[1]
        if is_ancestor(repo, previous, source) and tree(repo, previous) == parent_tree:
            return
    else:
        # Bootstrap an existing sanitized copy only when its entire current tree
        # matches a known source ancestor. Never merge that ancestor as a parent.
        ancestors = git(repo, "log", "-2000", "--format=%T", source).splitlines()
        if parent_tree in ancestors:
            return
    raise SyncError("TMDT has independent changes or the source is stale; review before synchronizing")


def prepare(name, path, urls, selected, branch, stack, dry_run):
    if Path(git(path, "rev-parse", "--show-toplevel")).resolve() != path.resolve():
        raise SyncError(f"{name}: configured path is not a repository root")
    git(path, "check-ref-format", f"refs/heads/{branch}")
    validate_remotes(path, urls, selected)
    source = git(path, "rev-parse", "--verify", f"refs/heads/{branch}^{{commit}}")
    if git(path, "status", "--porcelain"):
        if not dry_run:
            raise SyncError(f"{name}: uncommitted changes; publish from a reviewed, clean release checkout")
        print(f"NOTE {name}: uncommitted changes are excluded from this preview", flush=True)

    staging = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix="dataspace-push-")))
    git(staging, "init", "--bare", "--quiet")
    # Read the local objects via an alternate; never fetch into the real checkout.
    objects = Path(git(path, "rev-parse", "--git-path", "objects"))
    if not objects.is_absolute():
        objects = path / objects
    (staging / "objects" / "info" / "alternates").write_text(objects.resolve().as_posix() + "\n", encoding="utf-8")
    git(staging, "update-ref", "refs/sync/source", source)
    if "tmdt" in selected:
        check_actions_disabled(urls["tmdt"])
    before = {}
    for remote in dict.fromkeys(["origin", *selected]):
        before[remote] = fetch_tip(staging, urls[remote], branch, remote)
    if "origin" in selected:
        if not is_ancestor(staging, before["origin"], source):
            raise SyncError(f"{name}: source does not fast-forward origin/{branch}")
    elif before["origin"] != source:
        raise SyncError(f"{name}: local {branch} differs from published origin/{branch}; release first")
    if "gitlab" in selected and not is_ancestor(staging, before["gitlab"], source):
        raise SyncError(f"{name}: GitLab contains changes not present in the source")
    if "tmdt" in selected:
        validate_mirror_base(staging, before["tmdt"], source)
    return {"name": name, "repo": staging, "urls": urls, "source": source,
            "before": before, "tree": tree(staging, source)}


def sync_target(plan, remote, branch, dry_run):
    repo, source, before = plan["repo"], plan["source"], plan["before"][remote]
    url = plan["urls"][remote]
    unchanged = (tree(repo, before) == plan["tree"]) if remote == "tmdt" else before == source
    print(f"{plan['name']} -> {remote}/{branch}: " +
          ("up to date" if unchanged else "would update" if dry_run else "updating"), flush=True)
    if dry_run:
        return
    if remote_tip(repo, url, branch) != before:
        raise SyncError(f"{remote}/{branch} changed during preflight; retry after review")
    if unchanged:
        return
    if remote == "tmdt":
        check_actions_disabled(url)
        message = (f"Synchronize Dataspace: {plan['name']}\n\n"
                   f"Source: {plan['urls']['origin']}\nSource commit: {source}\n")
        # A single mirror parent is essential: source history can contain secrets
        # removed from the public mirror. Reuse ONLY the reviewed source tree.
        new = git(repo, "-c", "user.name=Dataspace Mirror", "-c",
                  "user.email=dataspace-mirror@users.noreply.github.com",
                  "-c", "commit.gpgSign=false", "commit-tree", plan["tree"], "-p", before,
                  input=message)
    else:
        new = source
    # Explicit URL and refspec, no force, no tags, no mirror push. Disable
    # followTags even when enabled globally. Concurrent changes reject the push.
    git(repo, "-c", "push.followTags=false", "push", url, f"{new}:refs/heads/{branch}")
    if remote_tip(repo, url, branch) != new:
        raise SyncError(f"Could not verify {remote}/{branch} after pushing")


def synchronize(workspace, targets, branch="main", dry_run=False):
    selected = [remote for remote in ("origin", "gitlab", "tmdt") if remote in targets]
    projects = load_projects(workspace)
    with ExitStack() as stack:
        plans, failures = [], []
        # Validate all ten before the first push. If a target is wrong, no repo
        # is published. A later network failure is resumable and exits nonzero.
        for name, path, urls in projects:
            try:
                print(f"Checking {name}", flush=True)
                plans.append(prepare(name, path, urls, selected, branch, stack, dry_run))
            except (SyncError, OSError, ValueError, subprocess.TimeoutExpired) as error:
                failures.append(f"{name}: {error}")
        if failures:
            raise SyncError("Preflight failed; nothing pushed:\n" + "\n".join(failures))
        for plan in plans:
            for remote in selected:
                try:
                    sync_target(plan, remote, branch, dry_run)
                except (SyncError, OSError, ValueError, subprocess.TimeoutExpired) as error:
                    failures.append(f"{plan['name']} -> {remote}: {error}")
                    break  # Do not mirror a repository whose earlier push failed.
        if failures:
            raise SyncError("Some repositories failed; rerun safely after review:\n" + "\n".join(failures))
    print(f"{'Preview complete' if dry_run else 'Synchronized'}: {len(projects)} repositories, "
          f"{len(selected)} targets each. No tags or upstream repositories pushed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, default=ROOT)
    parser.add_argument("--branch", default="main")
    parser.add_argument("--targets", nargs="+", choices=("origin", "gitlab", "tmdt"),
                        default=["gitlab", "tmdt"])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        synchronize(args.workspace.resolve(), args.targets, args.branch, args.dry_run)
    except (SyncError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
