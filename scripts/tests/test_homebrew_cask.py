"""Exercise Homebrew retries using a local tap and intercepted Git commands."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "update-homebrew-cask.sh"
FAKE_CLI = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
event = {"command": command, "args": args}
if command == "git" and args[:1] == ["-C"]:
    cask = Path(args[1]) / "Casks/current.rb"
    event["cask"] = cask.read_text() if cask.exists() else None
with open(os.environ["FAKE_TAP_LOG"], "a") as log:
    log.write(json.dumps(event) + "\n")
if command == "shasum":
    sys.exit(subprocess.call([os.environ["REAL_SHASUM"], *args]))
if args[:1] == ["clone"] and args[1] == "https://github.com/iamrajjoshi/homebrew-tap.git":
    sys.exit(subprocess.call([os.environ["REAL_GIT"], "clone", os.environ["FAKE_TAP_REPO"], args[2]]))
if args[:1] == ["-C"] and args[2] in ("add", "diff"):
    sys.exit(subprocess.call([os.environ["REAL_GIT"], *args]))
sys.exit("Unexpected Git operation in dry run: " + repr(args))
'''


class HomebrewCaskTests(unittest.TestCase):
    def setUp(self):
        self.git = shutil.which("git")
        self.shasum = shutil.which("shasum")
        if not self.git or not self.shasum:
            self.skipTest("Requires Git and shasum")
        self.temp = tempfile.TemporaryDirectory(prefix="Current cask tests ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in ("git", "shasum"):
            path = self.bin / command
            path.write_text(FAKE_CLI)
            path.chmod(0o755)
        self.repo = self.root / "tap"
        subprocess.run([self.git, "init", "--quiet", str(self.repo)], check=True)
        self.cask = self.repo / "Casks/current.rb"
        self.cask.parent.mkdir()
        self.archive = self.root / "Current.zip"
        self.archive.write_bytes(b"isolated release fixture\n")
        self.log = self.root / "calls.jsonl"

    def seed_cask(self, version="0.3.0", source=None):
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.cask.write_text(source if source is not None else f'''cask "current" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/iamrajjoshi/current/releases/download/v#{{version}}/Current-#{{version}}.zip"
  name "Current"
  desc "Daily Markdown notes organized in streams"
  homepage "https://github.com/iamrajjoshi/current"

  depends_on macos: ">= :sonoma"

  app "Current.app"
end
''')
        subprocess.run([self.git, "-C", str(self.repo), "add", "."], check=True)
        subprocess.run([self.git, "-C", str(self.repo), "-c", "user.name=Fixture",
                        "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false",
                        "commit", "--quiet", "-m", "Fixture cask"], check=True)

    def run_script(self, version):
        self.log.unlink(missing_ok=True)
        env = dict(os.environ, PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                   DRY_RUN="1", REAL_GIT=self.git, REAL_SHASUM=self.shasum,
                   FAKE_TAP_REPO=str(self.repo), FAKE_TAP_LOG=str(self.log))
        env.pop("HOMEBREW_TAP_TOKEN", None)
        result = subprocess.run(["/bin/bash", str(SCRIPT), version, str(self.archive)],
                                env=env, capture_output=True, text=True, timeout=15)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        for call in calls:
            if call["command"] == "git":
                self.assertNotIn("push", call["args"])
                self.assertNotIn("commit", call["args"])
                self.assertNotIn("remote", call["args"])
        return result, calls

    def test_newer_version_updates_cask_with_numeric_ordering(self):
        self.seed_cask("0.9.9")
        result, calls = self.run_script("0.10.0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        staged = next(call["cask"] for call in calls if call["args"][2:3] == ["add"])
        self.assertIn('version "0.10.0"', staged)
        self.assertIn(hashlib.sha256(self.archive.read_bytes()).hexdigest(), staged)
        self.assertIn('desc "Daily Markdown notes organized in streams"', staged)
        self.assertIn("Dry run complete", result.stdout)
        self.assertIn('version "0.9.9"', self.cask.read_text())

    def test_same_version_is_idempotent(self):
        self.seed_cask()
        result, calls = self.run_script("0.3.0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("already up to date for v0.3.0", result.stdout)
        staged = next(call["cask"] for call in calls if call["args"][2:3] == ["add"])
        self.assertEqual(staged, self.cask.read_text())

    def test_obsolete_version_skips_before_writing_or_staging(self):
        self.seed_cask("0.4.0")
        before = self.cask.read_bytes()
        for version in ("0.3.0", "0.3.999"):
            with self.subTest(version=version):
                result, calls = self.run_script(version)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"Skipping obsolete v{version}; Homebrew cask is already v0.4.0", result.stdout)
                self.assertEqual([call["args"][0] for call in calls if call["command"] == "git"], ["clone"])
                self.assertEqual(self.cask.read_bytes(), before)

    def test_malformed_input_is_rejected_before_external_commands(self):
        for version in ("0.3", "v0.3.0", "0.3.0-beta", "0.3.0\n", "$(touch unwanted)"):
            with self.subTest(version=version):
                result, calls = self.run_script(version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("numeric x.y.z format", result.stderr)
                self.assertEqual(calls, [])

    def test_malformed_existing_version_fails_before_write(self):
        self.seed_cask(source='cask "current" do\n  version :latest\nend\n')
        result, calls = self.run_script("0.3.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cannot parse current Homebrew cask version", result.stderr)
        self.assertEqual([call["args"][0] for call in calls if call["command"] == "git"], ["clone"])


if __name__ == "__main__":
    unittest.main()
