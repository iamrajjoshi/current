#!/usr/bin/env bash
set -euo pipefail

app_path="${1:?Usage: scripts/notarize-app.sh <Current.app> <x.y.z> <output-directory>}"
release_version="${2:?Missing version}"
dist_dir="${3:?Missing output directory}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD}"

if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must contain three numbers, for example 0.3.0" >&2
  exit 1
fi
[[ -d "$app_path" ]]
mkdir -p "$dist_dir/notarization"
dist_dir="$(cd "$dist_dir" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
archive_name="Current-$release_version.zip"
archive_path="$dist_dir/$archive_name"
if [[ -e "$archive_path" || -e "$archive_path.sha256" ]]; then
  echo "Output already exists; use a fresh directory to avoid replacing a release" >&2
  exit 1
fi

verify_app() {
  local candidate="$1"
  codesign --verify --deep --strict --verbose=2 "$candidate"
  codesign --display --verbose=4 "$candidate" 2> "$work_dir/signature.txt"
  grep -q '^Authority=Developer ID Application:' "$work_dir/signature.txt" || { echo "Expected a Developer ID Application signature" >&2; return 1; }
  grep -Fxq "TeamIdentifier=$APPLE_TEAM_ID" "$work_dir/signature.txt" || { echo "Signing team does not match APPLE_TEAM_ID" >&2; return 1; }
  grep -q '^Timestamp=' "$work_dir/signature.txt" || { echo "Signature has no secure timestamp" >&2; return 1; }
  grep -q 'flags=.*runtime' "$work_dir/signature.txt" || { echo "Hardened runtime is not enabled" >&2; return 1; }
  xcrun lipo "$candidate/Contents/MacOS/Current" -verify_arch arm64 x86_64
  codesign --display --entitlements - --xml "$candidate" > "$work_dir/entitlements.plist"
  python3 - "$candidate/Contents/Info.plist" "$work_dir/entitlements.plist" "$release_version" <<'PY'
import pathlib
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
if info.get("CFBundleIdentifier") != "com.raj.current":
    sys.exit("Unexpected bundle identifier")
if info.get("CFBundleShortVersionString") != sys.argv[3]:
    sys.exit("Unexpected app version")
if info.get("CFBundleExecutable") != "Current":
    sys.exit("Unexpected executable")
entitlements = pathlib.Path(sys.argv[2]).read_bytes()
if entitlements and plistlib.loads(entitlements).get("com.apple.security.get-task-allow"):
    sys.exit("Debug entitlement is not allowed")
PY
}

# Verify Xcode's signatures before sending anything to the notary service.
verify_app "$app_path"
ditto -c -k --keepParent "$app_path" "$work_dir/submission.zip"
notary_auth=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
submission="$dist_dir/notarization/submission.json"
xcrun notarytool submit "$work_dir/submission.zip" "${notary_auth[@]}" \
  --output-format json > "$submission"
submission_id="$(plutil -extract id raw -o - "$submission")"
echo "Notarization submission: $submission_id"
wait_status=0
xcrun notarytool wait "$submission_id" "${notary_auth[@]}" --timeout 45m \
  --output-format json > "$dist_dir/notarization/status.json" || wait_status=$?
# Preserve the report on rejection. A timed-out submission may not have a log yet.
xcrun notarytool log "$submission_id" "${notary_auth[@]}" \
  "$dist_dir/notarization/log.json" || true
if [[ "$wait_status" != 0 ]]; then
  echo "Notarization did not complete. Check submission $submission_id before retrying." >&2
  exit "$wait_status"
fi
status="$(plutil -extract status raw -o - "$dist_dir/notarization/status.json")"
if [[ "$status" != Accepted ]]; then
  echo "Notarization failed: $status (submission $submission_id)" >&2
  exit 1
fi

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
# Stapling changes the bundle. Package again, then validate the delivered bytes.
ditto -c -k --keepParent "$app_path" "$work_dir/$archive_name"
ditto -x -k "$work_dir/$archive_name" "$work_dir/extracted"
verify_app "$work_dir/extracted/Current.app"
xcrun stapler validate "$work_dir/extracted/Current.app"
spctl --assess --type execute --verbose=2 "$work_dir/extracted/Current.app"
mv "$work_dir/$archive_name" "$archive_path"
(
  cd "$dist_dir"
  shasum -a 256 "$archive_name" > "$archive_name.sha256"
)
echo "Verified signed and notarized archive: $archive_path"
