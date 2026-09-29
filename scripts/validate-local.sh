#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_args=(--package-path "$repo_root/CurrentPackage")
if [[ -n "${CURRENT_BUILD_CONFIGURATION:-}" ]]; then
  swift_args+=(-c "$CURRENT_BUILD_CONFIGURATION")
fi
if [[ -n "${CURRENT_BUILD_PATH:-}" ]]; then
  swift_args+=(--scratch-path "$CURRENT_BUILD_PATH")
fi

# Some CLT distributions ship Swift Testing outside SwiftPM's search paths.
# Keep this environment workaround out of the app's package/link settings.
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
  clt_support=/Library/Developer/CommandLineTools/Library/Developer
  if [[ -d "$clt_support/Frameworks/Testing.framework" ]]; then
    swift_args+=(-Xswiftc -F -Xswiftc "$clt_support/Frameworks"
      -Xlinker -rpath -Xlinker "$clt_support/Frameworks"
      -Xlinker -rpath -Xlinker "$clt_support/usr/lib")
  fi
fi

case "${1:-all}" in
  all)
    swift test "${swift_args[@]}"
    swift run "${swift_args[@]}" CurrentFeatureChecks
    ;;
  test)
    shift
    swift test "${swift_args[@]}" "$@"
    ;;
  checks)
    swift run "${swift_args[@]}" CurrentFeatureChecks
    ;;
  probe)
    shift
    restoration_only=false
    probe_output=""
    expects_output=false
    for argument in "$@"; do
      if $expects_output; then
        probe_output="$argument"
        expects_output=false
      elif [[ "$argument" == --output ]]; then
        expects_output=true
      elif [[ "$argument" == --restoration-only ]]; then
        restoration_only=true
      fi
    done
    if ! $restoration_only; then
      swift run "${swift_args[@]}" CurrentUIProbe "$@"
    else
      if $expects_output; then
        echo 'Missing value for --output' >&2
        exit 2
      fi
      swift build "${swift_args[@]}" --product CurrentUIProbe
      probe_bin_dir="$(swift build "${swift_args[@]}" --show-bin-path)"
      probe_bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/current-restoration-probe.XXXXXX")"
      trap 'rm -rf -- "$probe_bundle_root"' EXIT
      probe_bundle="$probe_bundle_root/Current Restoration Probe.app"
      mkdir -p "$probe_bundle/Contents/MacOS"
      cp "$probe_bin_dir/CurrentUIProbe" "$probe_bundle/Contents/MacOS/CurrentUIProbe"
      cat > "$probe_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CurrentUIProbe</string>
  <key>CFBundleIdentifier</key><string>com.current.restoration.probe</string>
  <key>CFBundleName</key><string>Current Restoration Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
      if [[ -z "$probe_output" ]]; then
        probe_output="$(mktemp -d "${TMPDIR:-/tmp}/current-restoration-results.XXXXXX")"
      fi
      mkdir -p "$probe_output"
      probe_output="$(cd "$probe_output" && pwd)"
      # Do not let a previous passing report mask a failed launch or crash.
      rm -f -- "$probe_output/restoration.json"
      # LaunchServices activation is required for native first-responder checks.
      # Restoration-only returns after its checks, even with regular-app --hold.
      /usr/bin/open --new --wait-apps --stdout "$probe_output/probe.stdout.log" \
        --stderr "$probe_output/probe.stderr.log" "$probe_bundle" \
        --args --hold "$@" --output "$probe_output"
      cat "$probe_output/probe.stdout.log"
      if [[ -s "$probe_output/probe.stderr.log" ]]; then
        cat "$probe_output/probe.stderr.log" >&2
      fi
      completed="$(/usr/bin/plutil -extract completed raw -o - "$probe_output/restoration.json" 2>/dev/null || true)"
      if [[ "$completed" != true ]]; then
        echo "Restoration probe failed or produced no completed report: $probe_output" >&2
        exit 1
      fi
    fi
    ;;
  *)
    echo 'Usage: scripts/validate-local.sh [all|test [SwiftPM options]|checks|probe [probe options]]' >&2
    exit 2
    ;;
esac
