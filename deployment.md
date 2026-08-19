# Deployment

This document is for maintainers building and publishing Liddddd. End-user
installation and usage instructions live in [README.md](README.md).

## Prerequisites

- macOS with Xcode and its Command Line Tools
- Swift 6 or later
- A Developer ID Application certificate for public binary releases
- Apple notarization credentials for Gatekeeper-compatible distribution

## Validate the source

Run all checks from the repository root:

```bash
swift format lint --recursive --strict Sources Tests Package.swift scripts/generate-app-icon.swift
swift test --disable-sandbox
plutil -lint Resources/*.plist
zsh -n scripts/*.sh Resources/manage-local-helper.sh
```

GitHub Actions runs the same formatting, test, resource, script, app-bundle,
and ad-hoc code-signing checks for pushes and pull requests.

## Local development build

```bash
scripts/build-app.sh
```

The app is written to `build/Liddddd.app`. Without `CODESIGN_IDENTITY`, the
script creates an ad-hoc build intended only for local development. It enables
identifier-only XPC authentication and includes a fixed-path legacy helper
installer so the app can be tested without an Apple Developer certificate.
Never redistribute this build.

## Developer ID release build

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  scripts/build-release.sh
```

The release build:

- signs the app and embedded helper with the supplied identity;
- enables the hardened runtime and secure timestamps;
- excludes development-only helper installation resources;
- verifies the final app bundle;
- verifies that the identity is an installed Developer ID Application
  certificate; and
- creates `build/Liddddd-<version>-notarization.zip` for Apple notarization.

Store notarization credentials in the macOS Keychain. Do not put an app-specific
password in a script, environment file, shell history, or the repository:

```bash
xcrun notarytool store-credentials Liddddd-notary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID"
```

After the secure password prompt succeeds, build the complete release:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="Liddddd-notary" \
  scripts/notarize-release.sh
```

The notarization script submits the app archive, staples the accepted ticket to
the app, creates a drag-to-Applications DMG, submits and staples the DMG, runs
code-signing and Gatekeeper assessments, and creates a SHA-256 checksum.

## Certificate-owner handoff

Keep the Developer ID private key, Apple ID credentials, and app-specific
password on the certificate owner's Mac. Do not send an unsigned app for blind
signing or exchange a `.p12` file. Instead, give the certificate owner the exact
Git commit to review and build:

```bash
git clone https://github.com/peer-problem/liddddd.git
cd liddddd
git checkout --detach COMMIT_SHA
git status --short

xcrun notarytool store-credentials Liddddd-notary \
  --apple-id "CERTIFICATE_OWNER_APPLE_ID" \
  --team-id "CERTIFICATE_OWNER_TEAM_ID"

CODESIGN_IDENTITY="Developer ID Application: Certificate Owner (TEAMID)" \
  NOTARY_PROFILE="Liddddd-notary" \
  scripts/notarize-release.sh
```

The certificate owner should return only these public release artifacts:

- `build/Liddddd-<version>.dmg`
- `build/Liddddd-<version>.dmg.sha256`

Before publishing artifacts received from another Mac, verify them locally:

```bash
shasum -a 256 -c Liddddd-<version>.dmg.sha256
hdiutil verify Liddddd-<version>.dmg
xcrun stapler validate Liddddd-<version>.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=2 Liddddd-<version>.dmg
```

## Release checklist

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
2. Update `LidddddConstants.helperVersion` when the helper changes. Increment
   `protocolVersion` only for an incompatible app/helper protocol change.
3. Run the full source validation commands.
4. Create the Developer ID release build.
5. Confirm the bundle contains no `manage-local-helper.sh` or legacy helper
   plist.
6. Run `scripts/notarize-release.sh` to notarize, staple, and package the app.
7. Verify code signing and Gatekeeper assessment on the final app.
8. Upload the final DMG and SHA-256 checksum to GitHub Releases.
9. Test installation, helper approval, start, automatic stop, manual stop, and
   helper removal on a separate Mac or clean user account.

Do not treat a successful build or notarization as proof of real lid-close,
battery-limit, or temperature-cutoff behavior. Record those hardware checks
separately for each release.
