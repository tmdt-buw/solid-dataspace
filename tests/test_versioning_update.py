"""Release-history regressions. Run: python -B -m unittest discover -s tests -v

The script embeds its planner in PowerShell. Load its actual Python functions
without executing the release entry point. All Git writes target temporary
repositories; these tests never contact a registry or a remote service.
"""

import ast
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "versioning-update.ps1"
PLANNER = re.search(r"(?ms)^  \$script = @'\n(.*?)\n'@", SCRIPT.read_text(encoding="utf-8")).group(1)
FUNCTIONS = {}
MODULE = ast.parse(PLANNER)
exec(compile(ast.Module(body=[
    node for node in MODULE.body
    if isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef))
], type_ignores=[]), str(SCRIPT), "exec"), FUNCTIONS)


class ReleaseHistoryTests(unittest.TestCase):
    def setUp(self):
        self.sandbox = pathlib.Path(tempfile.mkdtemp(prefix="solid-release-test-")).resolve()
        self.repo = self.sandbox / "app"
        self.repo.mkdir()
        self.git("init", "--initial-branch=main")
        self.write_package("0.1.0")
        (self.repo / "ui.js").write_text("original\n", encoding="utf-8")
        self.commit("released version")
        self.release_commit = self.git("rev-parse", "HEAD").strip()

    def tearDown(self):
        # Only remove the fixture directory we created inside the OS temp root.
        temp_root = pathlib.Path(tempfile.gettempdir()).resolve()
        if self.sandbox.parent != temp_root or not self.sandbox.name.startswith("solid-release-test-"):
            raise RuntimeError("Unexpected temporary repository path")
        # Git may mark object files read-only on Windows.
        def writable_retry(function, path, _error):
            pathlib.Path(path).chmod(0o700)
            function(path)
        shutil.rmtree(self.sandbox, onerror=writable_retry)

    def git(self, *args):
        return subprocess.run([
            "git", "-c", f"safe.directory={self.repo}",
            "-c", "user.name=Release Test", "-c", "user.email=release-test@example.invalid",
            "-c", "commit.gpgSign=false", "-c", f"core.hooksPath={self.sandbox / 'no-hooks'}",
            "-C", str(self.repo), *args,
        ], check=True, capture_output=True, text=True, encoding="utf-8").stdout

    def write_package(self, version, **extra):
        (self.repo / "package.json").write_text(
            json.dumps({"name": "test-app", "version": version, **extra}, indent=2) + "\n",
            encoding="utf-8",
        )

    def commit(self, message):
        self.git("add", "--all")
        self.git("commit", "--message", message)

    def change_ui(self):
        (self.repo / "ui.js").write_text("improved\n", encoding="utf-8")
        self.commit("UI improvements")

    def changes(self, filename="package.json"):
        return FUNCTIONS["committed_release_changes"](self.repo, self.repo / filename)

    def test_released_tree_needs_no_version_bump(self):
        self.assertIsNone(self.changes())

    def test_clean_worktree_with_new_commits_needs_release(self):
        self.change_ui()
        self.assertEqual(self.git("status", "--porcelain"), "")
        result = self.changes()
        self.assertEqual(result["versionCommit"], self.release_commit)
        self.assertEqual(result["files"], ["ui.js"])

    def test_already_pushed_unversioned_changes_still_need_release(self):
        remote = self.sandbox / "origin.git"
        self.git("init", "--bare", str(remote))
        self.git("remote", "add", "origin", str(remote))
        self.change_ui()
        self.git("push", "--set-upstream", "origin", "main")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", "origin/main"))
        self.assertEqual(self.changes()["files"], ["ui.js"])

    def test_dependency_edit_does_not_hide_unchanged_version(self):
        self.change_ui()
        self.write_package("0.1.0", dependencies={"example": "1.2.3"})
        self.commit("dependency edit without a version bump")
        self.assertEqual(self.changes()["versionCommit"], self.release_commit)
        self.assertEqual(self.changes()["files"], ["package.json", "ui.js"])

    def test_prepared_release_commit_is_safe_to_resume(self):
        self.change_ui()
        self.write_package("0.1.1")
        self.commit("prepare release")
        self.assertIsNone(self.changes())

    def test_changes_after_prepared_release_need_a_new_version(self):
        self.write_package("0.1.1")
        self.commit("prepare release")
        prepared = self.git("rev-parse", "HEAD").strip()
        self.change_ui()
        self.assertEqual(self.changes()["versionCommit"], prepared)

    def test_fully_reverted_changes_need_no_release(self):
        self.change_ui()
        self.git("revert", "--no-edit", "HEAD")
        self.assertIsNone(self.changes())

    def test_uncommitted_files_are_left_to_the_worktree_planner(self):
        (self.repo / "ui.js").write_text("not committed\n", encoding="utf-8")
        (self.repo / "new.js").write_text("untracked\n", encoding="utf-8")
        self.assertIsNone(self.changes())

    def test_merge_without_version_bump_requires_release(self):
        self.git("switch", "--create", "feature")
        self.change_ui()
        self.git("switch", "main")
        self.git("merge", "--no-ff", "feature", "--message", "merge UI")
        self.assertEqual(self.changes()["versionCommit"], self.release_commit)

    def test_merge_with_version_bump_covers_the_merged_changes(self):
        self.git("switch", "--create", "feature")
        self.change_ui()
        self.write_package("0.1.1")
        self.commit("prepare release")
        self.git("switch", "main")
        self.git("merge", "--no-ff", "feature", "--message", "merge release")
        self.assertIsNone(self.changes())

    def test_plain_version_file_is_supported(self):
        (self.repo / "VERSION").write_text("0.3.0\n", encoding="utf-8")
        self.commit("root release")
        self.assertIsNone(self.changes("VERSION"))
        self.change_ui()
        self.assertEqual(self.changes("VERSION")["files"], ["ui.js"])

    def test_filenames_are_not_git_quoted_or_trimmed(self):
        name = " Überarbeitete Oberfläche.js"
        (self.repo / name).write_text("UI\n", encoding="utf-8")
        self.commit("add named file")
        self.assertEqual(self.changes()["files"], [name])

    def test_inspection_does_not_change_files_index_or_refs(self):
        self.change_ui()
        def snapshot():
            return {p.relative_to(self.repo): p.read_bytes() for p in self.repo.rglob("*") if p.is_file()}
        before = snapshot()
        self.changes()
        self.assertEqual(snapshot(), before)

    def test_shallow_history_is_rejected_instead_of_guessing(self):
        self.change_ui()
        clone = self.sandbox / "shallow"
        self.git("clone", "--depth=1", self.repo.as_uri(), str(clone))
        with self.assertRaisesRegex(RuntimeError, "shallow repository"):
            FUNCTIONS["committed_release_changes"](clone, clone / "package.json")


class ReleasePlannerTests(unittest.TestCase):
    git = ReleaseHistoryTests.git
    commit = ReleaseHistoryTests.commit
    tearDown = ReleaseHistoryTests.tearDown
    embedded = {
        "solid-data-manager": ("@hoelk-f/solid-data-manager", "SOLID_DATA_MANAGER_PACKAGE_VERSION"),
        "semantic-data-catalog": ("@hoelk-f/semantic-data-catalog", "SEMANTIC_DATA_CATALOG_PACKAGE_VERSION"),
        "solid-health-app": ("@hoelk-f/solid-health-app", "SOLID_HEALTH_APP_PACKAGE_VERSION"),
        "solid-tours": ("@hoelk-f/city-tours", "CITY_TOURS_PACKAGE_VERSION"),
        "solid-health-questionnaire": ("@hoelk-f/solid-health-questionnaire", "SOLID_HEALTH_QUESTIONNAIRE_PACKAGE_VERSION"),
        "solid-chatbot": ("@hoelk-f/solid-chatbot", "SOLID_CHATBOT_PACKAGE_VERSION"),
    }

    def setUp(self):
        self.sandbox = pathlib.Path(tempfile.mkdtemp(prefix="solid-release-test-")).resolve()
        self.root = self.sandbox / "solid-dataspace"
        names = ["solid-dataspace", "solid-dataspace-manager", "environmental-monitoring",
                 "solid-data-connection-sync-worker", *self.embedded]
        for name in names:
            self.repo = self.sandbox / name
            self.repo.mkdir()
            self.git("init", "--initial-branch=main")
            if name == "solid-dataspace":
                (self.repo / "VERSION").write_text("1.0.0\n", encoding="utf-8")
                (self.repo / "CITATION.cff").write_text("version: 1.0.0\n", encoding="utf-8")
            else:
                dependencies = {}
                if name == "solid-dataspace-manager":
                    dependencies = {package: "1.0.0" for package, _ in self.embedded.values()}
                elif name == "solid-tours":
                    dependencies = {"@hoelk-f/semantic-data-catalog": "1.0.0"}
                package_name = self.embedded.get(name, (name, ""))[0]
                self.make_package(self.repo / "frontend" if name == "semantic-data-catalog" else self.repo,
                                  package_name, dependencies)
                if name == "solid-chatbot":
                    self.make_package(self.repo / "frontend", package_name, {})
                for base in [self.repo, self.repo / "frontend"]:
                    (base / "src").mkdir(parents=True, exist_ok=True)
                    (base / "src/version.js").write_text('export const appVersion = "1.0.0";\n', encoding="utf-8")
                    (base / "src/version.ts").write_text(
                        'export const appVersion = "1.0.0";\nexport const healthQuestionnaireVersion = "1.0.0";\n',
                        encoding="utf-8",
                    )
                if name == "solid-health-questionnaire":
                    (self.repo / "CITATION.cff").write_text("version: 1.0.0\ndate-released: 2026-01-01\n", encoding="utf-8")
                if name == "solid-dataspace-manager":
                    (self.repo / "Dockerfile").write_text(
                        "\n".join(f"ARG {arg}=1.0.0" for _, arg in self.embedded.values()) + "\n", encoding="utf-8",
                    )
                    (self.repo / "src/versions.js").write_text('export const appVersion = "1.0.0";\n', encoding="utf-8")
                    (self.repo / "src/externalLinks.js").write_text(
                        'const links = [{slug: "environmental-monitoring", version: "1.0.0"}, '
                        '{slug: "solid-health-app", version: "1.0.0"}, '
                        '{slug: "solid-chatbot", version: "1.0.0"}];\n', encoding="utf-8",
                    )
            self.commit("prepared release")

    def make_package(self, directory, name, dependencies):
        directory.mkdir(parents=True, exist_ok=True)
        package = {"name": name, "version": "1.0.0", "dependencies": dependencies}
        (directory / "package.json").write_text(json.dumps(package, indent=2) + "\n", encoding="utf-8")
        lock = {"name": name, "version": "1.0.0", "lockfileVersion": 3, "packages": {
            "": package,
            **{f"node_modules/{dep}": {"version": version, "integrity": "old-release-integrity"}
               for dep, version in dependencies.items()},
        }}
        (directory / "package-lock.json").write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")

    def plan(self, apply=False):
        result = subprocess.run(
            [sys.executable, "-B", "-"], input=PLANNER.replace("__ROOT__", str(self.root)),
            env={**os.environ, "APPLY_CHANGES": str(apply).lower(), "DIRTY_JSON": "[]"},
            text=True, encoding="utf-8", capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def add_source_commit(self, name):
        self.repo = self.sandbox / name
        (self.repo / "ui.js").write_text("UI changes\n", encoding="utf-8")
        self.commit("UI improvements")

    def commit_plan(self, plan):
        for name in [pathlib.Path(row["repo"]).name for row in plan["versions"]]:
            self.repo = self.sandbox / name
            self.commit("prepare release versions")

    def test_committed_catalog_changes_update_consumers_and_resume_once(self):
        self.assertEqual(self.plan()["versions"], [])
        self.add_source_commit("semantic-data-catalog")
        preview = self.plan()
        self.assertEqual(
            {pathlib.Path(row["repo"]).name for row in preview["versions"]},
            {"semantic-data-catalog", "solid-tours", "solid-dataspace-manager"},
        )
        self.assertEqual(preview, self.plan(apply=True))
        for consumer in ["solid-tours", "solid-dataspace-manager"]:
            package = json.loads((self.sandbox / consumer / "package.json").read_text(encoding="utf-8"))
            lock = json.loads((self.sandbox / consumer / "package-lock.json").read_text(encoding="utf-8"))
            name = "@hoelk-f/semantic-data-catalog"
            self.assertEqual(package["dependencies"][name], "1.0.1")
            self.assertEqual(lock["packages"][""]["dependencies"][name], "1.0.1")
            self.assertEqual(lock["packages"][f"node_modules/{name}"]["version"], "1.0.1")
            self.assertNotIn("integrity", lock["packages"][f"node_modules/{name}"])
        self.commit_plan(preview)
        self.assertEqual(self.plan()["versions"], [])

    def test_all_clean_ui_commits_receive_one_coordinated_release(self):
        changed = ["solid-dataspace-manager", "environmental-monitoring", *self.embedded]
        for name in changed:
            self.add_source_commit(name)
        preview = self.plan()
        self.assertEqual({pathlib.Path(row["repo"]).name for row in preview["versions"]}, set(changed))
        self.assertTrue(all(row["version"] == "1.0.1" for row in preview["versions"]))
        self.assertEqual(preview, self.plan(apply=True))
        docker = (self.sandbox / "solid-dataspace-manager/Dockerfile").read_text(encoding="utf-8")
        for _, arg in self.embedded.values():
            self.assertIn(f"ARG {arg}=1.0.1", docker)
        self.commit_plan(preview)
        self.assertEqual(self.plan()["versions"], [])


if __name__ == "__main__":
    unittest.main()
