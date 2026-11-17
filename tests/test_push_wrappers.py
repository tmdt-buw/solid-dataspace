"""Exercise the PowerShell entry points without making any network calls."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PWSH = os.environ.get("PWSH") or shutil.which("pwsh")


@unittest.skipUnless(PWSH and os.name != "nt", "PowerShell and POSIX test runtime required")
class WrapperTests(unittest.TestCase):
    def invoke(self, script, *args, code=0):
        with tempfile.TemporaryDirectory(prefix="dataspace-push-wrapper-") as directory:
            base = Path(directory)
            runtime = base / "python3"
            runtime.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "if sys.argv[1:] == ['--version']:\n"
                " print('Python 3.11.0'); sys.exit(0)\n"
                "with open(os.environ['WRAPPER_ARGUMENTS'], 'w') as output:\n"
                " json.dump(sys.argv[1:], output)\n"
                "sys.exit(int(os.environ['WRAPPER_EXIT']))\n"
            )
            runtime.chmod(0o755)
            recorded = base / "arguments.json"
            result = subprocess.run(
                [PWSH, "-NoProfile", "-File", str(ROOT / script), *args],
                capture_output=True, text=True, timeout=30,
                env={**os.environ, "PATH": str(base) + os.pathsep + os.environ["PATH"],
                     "WRAPPER_ARGUMENTS": str(recorded), "WRAPPER_EXIT": str(code)},
            )
            self.assertTrue(recorded.exists(), result.stdout + result.stderr)
            return result.returncode, json.loads(recorded.read_text())

    def test_default_target_sets(self):
        for script, targets in [
            ("git-push-main.ps1", ["origin", "gitlab", "tmdt"]),
            ("gitlab-update.ps1", ["gitlab", "tmdt"]),
            ("tmdt-update.ps1", ["tmdt"]),
        ]:
            with self.subTest(script=script):
                code, args = self.invoke(script)
                self.assertEqual(code, 0)
                self.assertEqual(args[args.index("--targets") + 1:], targets)

    def test_preview_branch_workspace_and_legacy_tmdt_selector(self):
        code, args = self.invoke("git-push-main.ps1", "-Remote", "tmdt", "-WhatIf",
                                 "-Branch", "release", "-WorkspaceRoot", "/tmp/release with spaces")
        self.assertEqual(code, 0)
        self.assertEqual(args[args.index("--workspace") + 1], "/tmp/release with spaces")
        self.assertEqual(args[args.index("--branch") + 1], "release")
        self.assertEqual(args[args.index("--targets") + 1:], ["tmdt", "--dry-run"])

    def test_failure_status_reaches_caller(self):
        code, _ = self.invoke("gitlab-update.ps1", code=17)
        self.assertEqual(code, 17)


if __name__ == "__main__":
    unittest.main()
