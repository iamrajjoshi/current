#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: scripts/update-homebrew-cask.sh <version> <zip-path>}"
ZIP_PATH="${2:?Usage: scripts/update-homebrew-cask.sh <version> <zip-path>}"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Zip not found: $ZIP_PATH"
  exit 1
fi

if [[ -z "${HOMEBREW_TAP_TOKEN:-}" && "${DRY_RUN:-}" != "1" ]]; then
  echo "HOMEBREW_TAP_TOKEN must be set with write access to iamrajjoshi/homebrew-tap"
  exit 1
fi

SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

git clone https://github.com/iamrajjoshi/homebrew-tap.git "$TEMP_DIR"
if [[ "${DRY_RUN:-}" != "1" ]]; then
  git -C "$TEMP_DIR" remote set-url origin "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/iamrajjoshi/homebrew-tap.git"
fi

mkdir -p "$TEMP_DIR/Casks"
cat > "$TEMP_DIR/Casks/current.rb" <<EOF
cask "current" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/iamrajjoshi/current/releases/download/v#{version}/Current-#{version}.zip"
  name "Current"
  desc "Native macOS apps for daily notes in a single stream"
  homepage "https://github.com/iamrajjoshi/current"

  depends_on macos: ">= :sonoma"

  app "Current.app"
end
EOF

git -C "$TEMP_DIR" add Casks/current.rb
git -C "$TEMP_DIR" diff --cached -- Casks/current.rb

if git -C "$TEMP_DIR" diff --cached --quiet -- Casks/current.rb; then
  echo "Homebrew cask already up to date for v${VERSION}"
  exit 0
fi

if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "Dry run complete; skipping Homebrew tap commit and push"
  exit 0
fi

git -C "$TEMP_DIR" config user.name "github-actions[bot]"
git -C "$TEMP_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$TEMP_DIR" commit -m ":wrench: chore[homebrew]: update current to ${VERSION}"
git -C "$TEMP_DIR" push origin main

echo "Homebrew cask updated to v${VERSION}"
