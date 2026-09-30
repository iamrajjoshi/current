# Releases and upgrades

The next planned version is **0.3.0**. Its signed-release workflow is prepared; it has not yet produced a validated, published signed release. The existing **0.2.0** release is unsigned. At preparation time, no valid local signing identity was available and only `HOMEBREW_TAP_TOKEN` was configured in GitHub. The Apple credentials below are still required.

Releases are manual. Pull requests and pushes to `main` run CI without creating app releases. CI can also be dispatched on a development branch. The release workflow publishes the selected branch's commit; it does not merge that branch.

## One-time setup

Use an Apple Developer Program account with a **Developer ID Application** certificate and its private key. Export both together as a password-protected `.p12` from Keychain Access. A downloaded `.cer` alone does not contain the private key. Apple Development, Mac Distribution, and Developer ID Installer certificates are not substitutes for this app signature. See [Apple's Developer ID certificate guidance](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

Add these repository Actions secrets in **iamrajjoshi/current → Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded `.p12` containing the Developer ID Application certificate and private key. |
| `APPLE_CERTIFICATE_PASSWORD` | The `.p12` export password. |
| `APPLE_TEAM_ID` | The Apple developer team identifier matching the certificate. |
| `APPLE_ID` | Apple account email authorized for that team. |
| `APPLE_APP_SPECIFIC_PASSWORD` | An app-specific password for notarization, not the account's normal password. |
| `HOMEBREW_TAP_TOKEN` | Existing fine-grained token for `iamrajjoshi/homebrew-tap`, with Contents read/write access. |

Keep certificates and keys outside the repository. Never paste their contents or passwords into chat, command arguments, or issue comments. For a local certificate, pipe the encoded data directly to GitHub CLI:

```sh
base64 -i "/path/to/DeveloperID.p12" | gh secret set APPLE_CERTIFICATE_P12_BASE64 --repo iamrajjoshi/current
```

Enter the remaining values through GitHub Settings or the interactive prompt from `gh secret set SECRET_NAME --repo iamrajjoshi/current`. The runner uses a temporary keychain and removes signing material after the job. See [GitHub's certificate setup guidance](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

## Run a release

First push the intended source and workflow changes to the selected branch. Version input must have exactly three numeric components, such as `0.3.0`; prerelease suffixes are not accepted as the app's marketing version. Apple specifies that format for [CFBundleShortVersionString](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring).

The existing `Release` workflow is registered on the default branch; [GitHub's manual-dispatch instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) allow selecting another branch with `--ref`. For the current development branch:

```sh
gh workflow run release.yml --repo iamrajjoshi/current --ref raj--inkpad--stream-workspace -f version=0.3.0
gh run list --repo iamrajjoshi/current --workflow release.yml --branch raj--inkpad--stream-workspace --limit 5
gh run watch RUN_ID --repo iamrajjoshi/current --exit-status
```

Replace `RUN_ID` with the run returned by the listing. Confirm its commit SHA before treating the release as the requested build.

The workflow runs package tests and feature checks, builds with manual Developer ID signing, hardened runtime and a secure timestamp, then invokes `scripts/notarize-app.sh`. The release gates verify the signature, bundle/version/team, required architectures, and absence of an enabled `get-task-allow` entitlement.

The distribution build sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` so Xcode does not add its debugger entitlement. A custom `build` does not perform the entitlement cleanup of archive/export; see [Apple's notarization troubleshooting guidance](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

Apple notarization must return `Accepted`. The app receives and validates its stapled ticket, then is packaged again. The final ZIP is extracted and checked for signature, ticket, and Gatekeeper acceptance before publication; its final bytes determine the checksum. A ZIP itself cannot be stapled. See [Apple's custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) and [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Only after those gates succeed does the release job publish the versioned ZIP and checksum. The separate Homebrew job downloads the published asset, verifies its checksum, and updates the cask. A prepared workflow, successful compilation, or submitted notarization request alone is not a completed signed release.

## Failure and retry

For certificate, entitlement, or `Invalid` notarization failures, inspect the workflow output and notarization diagnostics, fix the cause, and rerun. Do not bypass the checks or publish an unsigned replacement.

A network failure during GitHub publication can leave a draft release. Preflight detects both drafts and published versions before building. Inspect any existing draft and its assets before resolving that failed attempt, or choose a new version. The workflow never deletes a draft or overwrites an existing version automatically.

If notarization times out, no release tag is published by that attempt. Preserve the submission ID in `submission.json` and inspect `status.json` and `log.json` when available. A timeout does not mean Apple rejected the upload. With matching credentials stored in a local notarytool profile, its status can be checked without uploading again:

```sh
xcrun notarytool info SUBMISSION_ID --keychain-profile PROFILE_NAME
xcrun notarytool wait SUBMISSION_ID --keychain-profile PROFILE_NAME --timeout 30m
```

The workflow does not automatically resume an old submission. After investigating, rerun the release job if needed; that run must still pass every publication gate. An older request becoming accepted does not publish or validate a newly built ZIP.

If the app release succeeded but the Homebrew job failed, rerun only failed jobs:

```sh
gh run rerun RUN_ID --repo iamrajjoshi/current --failed
```

This reuses the existing release asset and checksum without rebuilding or re-signing it. If the tap already contains a newer version, an obsolete retry skips the update. Do not delete the release or replace its asset merely to retry the tap update. GitHub reruns retain the original commit and ref; see [rerunning workflows and jobs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).

## Local workflow checks

```sh
python3 -B -m unittest discover -s scripts/tests -p 'test_*.py'
shellcheck scripts/notarize-app.sh scripts/update-homebrew-cask.sh
actionlint .github/workflows/release.yml .github/workflows/ci.yml
```

The tests use temporary app/tap fixtures and simulate Apple's signing and notarization responses. They check failure handling, final archive bytes, checksums, and retry behavior. They do not establish actual Developer ID validity or Apple acceptance; the real release job must still pass those checks.

## Upgrade an installed app

After both release and Homebrew jobs succeed, quit Current normally so pending notes and workspace state are saved, then run:

```sh
brew update
brew upgrade --cask iamrajjoshi/tap/current
```

For a first installation, use `brew install --cask iamrajjoshi/tap/current`. Direct-download users can replace `Current.app` with the app from the new GitHub Release after quitting it. Notes remain outside the app bundle in the configured library directory; neither upgrade path should remove that directory. Do not use a cask `zap` entry for note data. Open Current again and confirm the installed version and restored workspace.

Homebrew and direct downloads are the upgrade paths documented here. This workflow does not add an in-app automatic updater.
