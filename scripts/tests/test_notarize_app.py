"""Local release-script tests; Apple services/signatures are fake, lipo also gets a real fixture."""

import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "notarize-app.sh"
TICKET = "Contents/_CodeSignature/notary-ticket"
FAKE_CLI = r'''#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import plistlib
import sys
import zipfile

command = Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ["FAKE_NOTARY_SCENARIO"]
event = {"command": command, "args": args}
if command == "xcrun" and args[:2] == ["notarytool", "submit"]:
    submission = Path(args[2])
    event["sha256"] = hashlib.sha256(submission.read_bytes()).hexdigest()
    with zipfile.ZipFile(submission) as archive:
        event["had_ticket"] = "Current.app/Contents/_CodeSignature/notary-ticket" in archive.namelist()
with open(os.environ["FAKE_NOTARY_LOG"], "a") as log:
    log.write(json.dumps(event) + "\n")

if command == "codesign":
    if "--verify" in args:
        sys.exit(0)
    if "--entitlements" in args:
        sys.stdout.buffer.write(plistlib.dumps({"com.apple.security.get-task-allow": scenario == "debug"}))
        sys.exit(0)
    if args[:2] == ["--display", "--verbose=4"]:
        if scenario == "adhoc":
            print("Signature=adhoc\nTeamIdentifier=not set", file=sys.stderr)
        else:
            team = "OTHERTEAM" if scenario == "wrong_team" else "TESTTEAMID"
            print("Authority=Developer ID Application: Test Fixture (TESTTEAMID)", file=sys.stderr)
            print(f"TeamIdentifier={team}\nTimestamp=Sep 29, 2026\nCodeDirectory flags=0x10000(runtime)", file=sys.stderr)
        sys.exit(0)
elif command == "xcrun":
    if args[:1] == ["lipo"]:
        if len(args) != 5 or args[2:] != ["-verify_arch", "arm64", "x86_64"] or not Path(args[1]).is_file():
            sys.exit("Expected lipo <binary> -verify_arch arm64 x86_64")
        real_lipo = os.environ.get("FAKE_NOTARY_REAL_LIPO")
        if real_lipo:
            os.execv(real_lipo, [real_lipo, *args[1:]])
        sys.exit(1 if scenario == "architecture" else 0)
    if args[:2] == ["notarytool", "submit"]:
        print(json.dumps({"id": "fixture-submission"}))
        sys.exit(0)
    if args[:2] == ["notarytool", "wait"]:
        status = {"rejected": "Invalid", "timeout": "In Progress"}.get(scenario, "Accepted")
        print(json.dumps({"id": "fixture-submission", "status": status}))
        sys.exit(124 if scenario == "timeout" else 0)
    if args[:2] == ["notarytool", "log"]:
        Path(args[-1]).write_text(json.dumps({"id": "fixture-submission", "scenario": scenario}))
        sys.exit(0)
    if args[0] == "stapler":
        ticket = Path(args[-1]) / "Contents/_CodeSignature/notary-ticket"
        if args[1] == "staple":
            ticket.parent.mkdir(parents=True, exist_ok=True)
            ticket.write_bytes(b"test ticket added after notarization\n")
            sys.exit(0)
        if args[1] == "validate":
            sys.exit(0 if ticket.is_file() else 1)
elif command == "spctl":
    ticket = Path(args[-1]) / "Contents/_CodeSignature/notary-ticket"
    sys.exit(1 if scenario == "gatekeeper" or not ticket.is_file() else 0)
sys.exit("Unexpected fake CLI invocation: " + command + " " + repr(args))
'''


@unittest.skipUnless(sys.platform == "darwin", "Uses the macOS ditto/plutil archive path")
class NotarizeAppTests(unittest.TestCase):
    def setUp(self):
        for command in ("ditto", "plutil", "shasum"):
            if not shutil.which(command):
                self.skipTest(f"Required local tool is unavailable: {command}")
        self.temp = tempfile.TemporaryDirectory(prefix="Current notary tests ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("codesign", "xcrun", "spctl"):
            path = self.bin / name
            path.write_text(FAKE_CLI)
            path.chmod(0o755)

    def fixture(self, name, version="0.3.0"):
        root = self.root / name
        app = root / "Current.app"
        executable = app / "Contents/MacOS/Current"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b"fixture executable bytes\n")
        executable.chmod(0o755)
        with (app / "Contents/Info.plist").open("wb") as info:
            plistlib.dump({"CFBundleIdentifier": "com.raj.current",
                          "CFBundleExecutable": "Current",
                          "CFBundleShortVersionString": version}, info)
        return app, root / "dist", root / "calls.jsonl"

    def run_script(self, fixture, scenario="accepted", real_lipo=None):
        app, dist, log = fixture
        env = dict(os.environ, PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                   APPLE_TEAM_ID="TESTTEAMID", APPLE_ID="fixture@example.invalid",
                   APPLE_APP_SPECIFIC_PASSWORD="fake-test-password",
                   FAKE_NOTARY_SCENARIO=scenario, FAKE_NOTARY_LOG=str(log))
        if real_lipo is not None:
            env["FAKE_NOTARY_REAL_LIPO"] = real_lipo
        result = subprocess.run(["/bin/bash", str(SCRIPT), str(app), "0.3.0", str(dist)],
                                env=env, capture_output=True, text=True, timeout=30)
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result, calls

    def assert_unpublished(self, dist):
        self.assertFalse((dist / "Current-0.3.0.zip").exists())
        self.assertFalse((dist / "Current-0.3.0.zip.sha256").exists())

    def test_accepted_submission_publishes_repacked_stapled_bytes_and_checksum(self):
        fixture = self.fixture("accepted")
        app, dist, _ = fixture
        result, calls = self.run_script(fixture)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        archive = dist / "Current-0.3.0.zip"
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        checksum = (dist / "Current-0.3.0.zip.sha256").read_text().split()
        self.assertEqual(checksum, [digest, archive.name])
        with zipfile.ZipFile(archive) as packaged:
            self.assertEqual(packaged.read(f"Current.app/{TICKET}"), (app / TICKET).read_bytes())
            self.assertEqual(packaged.read("Current.app/Contents/MacOS/Current"), b"fixture executable bytes\n")
        submission = next(call for call in calls if call["args"][:2] == ["notarytool", "submit"])
        self.assertFalse(submission["had_ticket"])
        self.assertNotEqual(submission["sha256"], digest)
        gatekeeper = next(call for call in calls if call["command"] == "spctl")
        self.assertNotEqual(gatekeeper["args"][-1], str(app))
        self.assertTrue(gatekeeper["args"][-1].endswith("/extracted/Current.app"))
        verified = [call["args"][-1] for call in calls if call["command"] == "codesign" and "--verify" in call["args"]]
        stapled = [call["args"][-1] for call in calls if call["args"][:2] == ["stapler", "validate"]]
        self.assertIn(gatekeeper["args"][-1], verified)
        self.assertIn(gatekeeper["args"][-1], stapled)

    def test_real_lipo_verifies_universal_macho_and_rejects_wrong_order_and_thin_binary(self):
        tool_env = dict(os.environ)
        clt = Path("/Library/Developer/CommandLineTools")
        if clt.is_dir():
            tool_env["DEVELOPER_DIR"] = str(clt)

        def xcrun(*args):
            return subprocess.check_output(["/usr/bin/xcrun", *args], env=tool_env,
                                           text=True, stderr=subprocess.PIPE).strip()

        clang = xcrun("--find", "clang")
        lipo = xcrun("--find", "lipo")
        sdk = xcrun("--sdk", "macosx", "--show-sdk-path")
        fixture = self.fixture("real universal")
        executable = fixture[0] / "Contents/MacOS/Current"
        source = self.root / "fixture.c"
        source.write_text("int main(void) { return 0; }\n")
        compile_result = subprocess.run(
            [clang, "-isysroot", sdk, "-arch", "arm64", "-arch", "x86_64",
             str(source), "-o", str(executable)],
            env=tool_env, capture_output=True, text=True, timeout=30)
        self.assertEqual(compile_result.returncode, 0, compile_result.stdout + compile_result.stderr)

        # lipo treats every token after -verify_arch as an architecture, including
        # a trailing binary path. The permissive mock previously hid this failure.
        wrong_order = subprocess.run(
            [lipo, "-verify_arch", "arm64", "x86_64", str(executable)],
            capture_output=True, text=True, timeout=10)
        self.assertNotEqual(wrong_order.returncode, 0)

        result, calls = self.run_script(fixture, real_lipo=lipo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lipo_calls = [call for call in calls if call["args"][:1] == ["lipo"]]
        self.assertEqual(len(lipo_calls), 2)
        self.assertEqual(lipo_calls[0]["args"][1], str(executable))
        self.assertTrue(lipo_calls[1]["args"][1].endswith("/extracted/Current.app/Contents/MacOS/Current"))
        with zipfile.ZipFile(fixture[1] / "Current-0.3.0.zip") as packaged:
            self.assertEqual(packaged.read("Current.app/Contents/MacOS/Current"), executable.read_bytes())

        thin_fixture = self.fixture("real thin")
        thin_executable = thin_fixture[0] / "Contents/MacOS/Current"
        subprocess.run([lipo, str(executable), "-thin", "arm64", "-output", str(thin_executable)],
                       capture_output=True, text=True, check=True, timeout=10)
        result, calls = self.run_script(thin_fixture, real_lipo=lipo)
        self.assertNotEqual(result.returncode, 0)
        self.assert_unpublished(thin_fixture[1])
        self.assertFalse(any(call["args"][:1] == ["notarytool"] for call in calls))

    def test_rejected_or_timed_out_notarization_keeps_reports_without_publishing(self):
        for scenario in ("rejected", "timeout"):
            with self.subTest(scenario=scenario):
                fixture = self.fixture(scenario)
                result, calls = self.run_script(fixture, scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assert_unpublished(fixture[1])
                for report in ("submission.json", "status.json", "log.json"):
                    self.assertTrue((fixture[1] / "notarization" / report).is_file())
                self.assertFalse(any(call["args"][:2] == ["stapler", "staple"] for call in calls))

    def test_invalid_app_is_rejected_before_any_notary_submission(self):
        for scenario in ("wrong_team", "adhoc", "bad_version", "debug", "architecture"):
            with self.subTest(scenario=scenario):
                fixture = self.fixture(scenario, version="0.2.0" if scenario == "bad_version" else "0.3.0")
                result, calls = self.run_script(fixture, scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assert_unpublished(fixture[1])
                self.assertFalse(any(call["args"][:1] == ["notarytool"] for call in calls))

    def test_gatekeeper_failure_blocks_publication_of_an_accepted_stapled_app(self):
        fixture = self.fixture("gatekeeper")
        result, calls = self.run_script(fixture, "gatekeeper")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((fixture[0] / TICKET).is_file())
        self.assertTrue(any(call["command"] == "spctl" for call in calls))
        self.assert_unpublished(fixture[1])

    def test_optimized_python_keeps_metadata_and_entitlement_validation(self):
        with patch.dict(os.environ, {"PYTHONOPTIMIZE": "1"}):
            for scenario in ("bad_version", "debug"):
                with self.subTest(scenario=scenario):
                    fixture = self.fixture(scenario, version="0.2.0" if scenario == "bad_version" else "0.3.0")
                    result, calls = self.run_script(fixture, scenario)
                    self.assertNotEqual(result.returncode, 0)
                    self.assert_unpublished(fixture[1])
                    self.assertFalse(any(call["args"][:1] == ["notarytool"] for call in calls))

    def test_existing_archive_or_checksum_is_never_overwritten(self):
        for suffix in (".zip", ".zip.sha256"):
            with self.subTest(suffix=suffix):
                fixture = self.fixture(suffix)
                fixture[1].mkdir()
                existing = fixture[1] / f"Current-0.3.0{suffix}"
                existing.write_bytes(b"existing release artifact\n")
                result, calls = self.run_script(fixture)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(existing.read_bytes(), b"existing release artifact\n")
                self.assertEqual(calls, [])
                self.assertEqual(list(fixture[1].glob("Current-*")), [existing])


if __name__ == "__main__":
    unittest.main()
