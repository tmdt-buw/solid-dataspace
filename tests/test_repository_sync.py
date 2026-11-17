"""Mirror regressions using disposable local Git repositories, never live remotes."""

from contextlib import ExitStack
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("sync_repositories", ROOT / "scripts/sync_repositories.py")
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class MirrorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dataspace-mirror-tests-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.env = patch.dict(os.environ, {
            "GIT_CONFIG_GLOBAL": str(self.base / "empty.gitconfig"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Mirror Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Mirror Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.source = self.base / "source"
        self.source.mkdir()
        SYNC.git(self.source, "init", "-q", "--initial-branch=main")
        (self.source / "historical-secret.txt").write_text("synthetic old credential")
        self.secret = self.commit(self.source, "unsafe historical commit")
        (self.source / "historical-secret.txt").unlink()
        (self.source / "app.txt").write_text("version 1")
        self.previous = self.commit(self.source, "safe source version")
        self.mirror = self.base / "mirror.git"
        SYNC.git(self.base, "init", "-q", "--bare", str(self.mirror))
        # The public mirror starts with a completely separate, clean history.
        self.mirror_work = self.base / "mirror-work"
        self.mirror_work.mkdir()
        SYNC.git(self.mirror_work, "init", "-q", "--initial-branch=main")
        (self.mirror_work / "app.txt").write_text("version 1")
        self.parent = self.commit(self.mirror_work, "sanitized mirror root")
        SYNC.git(self.mirror_work, "push", str(self.mirror), "main")
        (self.source / "app.txt").write_text("version 2")
        self.current = self.commit(self.source, "new release")
        self.stage = self.base / "stage.git"
        SYNC.git(self.base, "init", "-q", "--bare", str(self.stage))
        (self.stage / "objects/info/alternates").write_text(str(self.source / ".git/objects") + "\n")
        self.plan = self.plan_for(self.stage)

    def commit(self, repo, message):
        SYNC.git(repo, "add", "-A")
        SYNC.git(repo, "commit", "-qm", message)
        return SYNC.git(repo, "rev-parse", "HEAD")

    def plan_for(self, stage):
        parent = SYNC.fetch_tip(stage, str(self.mirror), "main", "tmdt")
        return {"name": "app", "repo": stage, "source": self.current,
                "tree": SYNC.tree(stage, self.current), "before": {"tmdt": parent},
                "urls": {"tmdt": str(self.mirror), "origin": "https://github.com/hoelk-f/app.git"}}

    def push(self, plan=None, dry_run=False):
        with patch.object(SYNC, "check_actions_disabled"):
            SYNC.sync_target(plan or self.plan, "tmdt", "main", dry_run)

    def tip(self):
        return SYNC.remote_tip(self.source, str(self.mirror), "main")

    def test_snapshot_has_only_mirror_parent_and_never_reconnects_secret_history(self):
        SYNC.validate_mirror_base(self.stage, self.parent, self.current)
        self.push()
        new = self.tip()
        SYNC.fetch_tip(self.stage, str(self.mirror), "main", "tmdt")
        self.assertEqual(SYNC.git(self.stage, "show", "-s", "--format=%P", new), self.parent)
        self.assertEqual(SYNC.tree(self.stage, new), SYNC.tree(self.source, self.current))
        self.assertFalse(SYNC.is_ancestor(self.stage, self.secret, new))
        self.assertIn("Source commit: " + self.current, SYNC.git(self.stage, "show", "-s", "--format=%B", new))
        missing = subprocess.run(["git", "-C", str(self.mirror), "cat-file", "-e", self.secret], capture_output=True)
        self.assertNotEqual(missing.returncode, 0)

    def test_second_run_does_not_create_another_commit(self):
        self.push()
        first = self.tip()
        self.push(self.plan_for(self.stage))
        self.assertEqual(self.tip(), first)

    def test_dry_run_changes_no_heads_or_commits(self):
        before = SYNC.git(self.stage, "count-objects", "-v")
        source_refs = SYNC.git(self.source, "show-ref")
        self.push(dry_run=True)
        self.assertEqual(self.tip(), self.parent)
        self.assertEqual(SYNC.git(self.stage, "count-objects", "-v"), before)
        self.assertEqual(SYNC.git(self.source, "show-ref"), source_refs)

    def test_remote_advance_after_preflight_is_rejected(self):
        (self.mirror_work / "app.txt").write_text("independent edit")
        changed = self.commit(self.mirror_work, "mirror edit")
        SYNC.git(self.mirror_work, "push", str(self.mirror), "main")
        with self.assertRaisesRegex(SYNC.SyncError, "changed during preflight"):
            self.push()
        self.assertEqual(self.tip(), changed)

    def test_independent_mirror_edits_are_not_overwritten(self):
        (self.mirror_work / "app.txt").write_text("independent edit")
        changed = self.commit(self.mirror_work, "mirror edit")
        SYNC.git(self.mirror_work, "push", str(self.mirror), "main")
        plan = self.plan_for(self.stage)
        with self.assertRaisesRegex(SYNC.SyncError, "independent changes"):
            SYNC.validate_mirror_base(self.stage, plan["before"]["tmdt"], self.current)
        self.assertEqual(self.tip(), changed)

    def test_stale_source_cannot_roll_back_mirror(self):
        self.push()
        plan = self.plan_for(self.stage)
        with self.assertRaisesRegex(SYNC.SyncError, "source is stale"):
            SYNC.validate_mirror_base(self.stage, plan["before"]["tmdt"], self.previous)

    def test_a_following_release_preserves_mirror_history(self):
        self.push()
        prior = self.tip()
        (self.source / "app.txt").write_text("version 3")
        self.current = self.commit(self.source, "another release")
        plan = self.plan_for(self.stage)
        SYNC.validate_mirror_base(self.stage, prior, self.current)
        self.push(plan)
        self.assertEqual(SYNC.git(self.stage, "show", "-s", "--format=%P", self.tip()), prior)

    def test_tags_are_not_pushed_even_with_global_follow_tags(self):
        SYNC.git(self.stage, "config", "push.followTags", "true")
        SYNC.git(self.stage, "tag", "-a", "secret-history", self.secret, "-m", "historical tag")
        self.push()
        self.assertEqual(SYNC.git(self.stage, "ls-remote", "--tags", str(self.mirror)), "")

    @unittest.skipIf(os.name == "nt", "POSIX receive hook")
    def test_failed_push_is_reported_and_retry_is_safe(self):
        hook = self.mirror / "hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        with self.assertRaises(SYNC.SyncError):
            self.push()
        self.assertEqual(self.tip(), self.parent)
        hook.unlink()
        self.push()
        self.assertNotEqual(self.tip(), self.parent)

    def test_prepare_requires_published_clean_source_for_mirror_only(self):
        origin = self.base / "origin.git"
        SYNC.git(self.base, "init", "-q", "--bare", str(origin))
        SYNC.git(self.source, "push", str(origin), self.current + ":refs/heads/main")
        urls = {"origin": str(origin), "tmdt": str(self.mirror)}
        with patch.object(SYNC, "validate_remotes"), patch.object(SYNC, "check_actions_disabled"), ExitStack() as stack:
            plan = SYNC.prepare("app", self.source, urls, ["tmdt"], "main", stack, False)
            self.assertEqual(plan["source"], self.current)
            (self.source / "app.txt").write_text("uncommitted")
            with self.assertRaisesRegex(SYNC.SyncError, "uncommitted changes"):
                SYNC.prepare("app", self.source, urls, ["tmdt"], "main", stack, False)
            self.commit(self.source, "not released")
            with self.assertRaisesRegex(SYNC.SyncError, "release first"):
                SYNC.prepare("app", self.source, urls, ["tmdt"], "main", stack, False)

    def test_non_main_branch_is_respected(self):
        SYNC.git(self.mirror_work, "push", str(self.mirror), "main:refs/heads/release")
        with patch.object(SYNC, "check_actions_disabled"):
            SYNC.sync_target(self.plan, "tmdt", "release", False)
        self.assertEqual(self.tip(), self.parent)
        self.assertNotEqual(SYNC.remote_tip(self.source, str(self.mirror), "release"), self.parent)

    def test_gitlab_pushes_source_commit_and_retains_history(self):
        gitlab = self.base / "gitlab.git"
        SYNC.git(self.base, "init", "-q", "--bare", str(gitlab))
        SYNC.git(self.source, "push", str(gitlab), self.previous + ":refs/heads/main")
        plan = {**self.plan, "before": {"gitlab": self.previous}, "urls": {"gitlab": str(gitlab)}}
        SYNC.sync_target(plan, "gitlab", "main", False)
        self.assertEqual(SYNC.remote_tip(self.source, str(gitlab), "main"), self.current)


class ConfigurationTests(unittest.TestCase):
    def test_all_ten_targets_and_plasma_mapping(self):
        projects = SYNC.load_projects(ROOT)
        self.assertEqual(len(projects), 10)
        urls = {name: targets for name, _, targets in projects}
        self.assertEqual(urls["plasma"]["tmdt"], "https://github.com/tmdt-buw/plasma-dataspace.git")
        self.assertTrue(urls["environmental-monitoring"]["tmdt"].endswith("/urban-data-explorer.git"))
        self.assertTrue(urls["city-tours"]["tmdt"].endswith("/solid-city-tours.git"))

    def test_ssh_and_https_are_equivalent_but_upstream_is_not(self):
        expected = SYNC.repository_id("https://github.com/tmdt-buw/plasma-dataspace.git")
        self.assertEqual(expected, SYNC.repository_id("git@github.com:tmdt-buw/plasma-dataspace.git"))
        self.assertEqual(expected, SYNC.repository_id("ssh://git@github.com/tmdt-buw/plasma-dataspace"))
        self.assertNotEqual(expected, SYNC.repository_id("https://github.com/tmdt-buw/plasma.git"))
        with self.assertRaises(SYNC.SyncError):
            SYNC.repository_id("https://token@github.com/tmdt-buw/plasma-dataspace.git")

    def test_hidden_push_url_to_upstream_is_rejected(self):
        urls = {"origin": "https://github.com/hoelk-f/plasma.git",
                "tmdt": "https://github.com/tmdt-buw/plasma-dataspace.git"}
        values = [urls["origin"], urls["origin"], urls["tmdt"], "https://github.com/tmdt-buw/plasma.git"]
        with patch.object(SYNC, "git", side_effect=values), self.assertRaisesRegex(SYNC.SyncError, "points somewhere"):
            SYNC.validate_remotes(Path("plasma"), urls, ["tmdt"])

    def test_actions_enabled_blocks_publication(self):
        with patch.object(SYNC, "run", return_value=json.dumps({"enabled": True})), self.assertRaisesRegex(SYNC.SyncError, "disabled"):
            SYNC.check_actions_disabled("https://github.com/tmdt-buw/plasma-dataspace.git")

    def test_one_bad_repository_prevents_all_pushes(self):
        projects = [(str(i), Path(str(i)), {}) for i in range(10)]
        results = [{"name": str(i)} if i != 4 else SYNC.SyncError("wrong target") for i in range(10)]
        with patch.object(SYNC, "load_projects", return_value=projects), \
             patch.object(SYNC, "prepare", side_effect=results) as prepare, \
             patch.object(SYNC, "sync_target") as push:
            with self.assertRaisesRegex(SYNC.SyncError, "nothing pushed"):
                SYNC.synchronize(ROOT, ["gitlab", "tmdt"])
            self.assertEqual(prepare.call_count, 10)
            push.assert_not_called()

    def test_gitlab_failure_does_not_push_tmdt_for_that_repo_and_exits_with_error(self):
        projects = [("app", Path("app"), {})]
        with patch.object(SYNC, "load_projects", return_value=projects), \
             patch.object(SYNC, "prepare", return_value={"name": "app"}), \
             patch.object(SYNC, "sync_target", side_effect=SYNC.SyncError("network failure")) as push:
            with self.assertRaisesRegex(SYNC.SyncError, "Some repositories failed"):
                SYNC.synchronize(ROOT, ["gitlab", "tmdt"])
            self.assertEqual(push.call_count, 1)
            self.assertEqual(push.call_args.args[1], "gitlab")


if __name__ == "__main__":
    unittest.main()
