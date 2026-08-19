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
- creates `build/Liddddd-<version>.zip`; and
- creates a matching `.sha256` checksum file.

The script does not submit the build to Apple. Notarize the ZIP, staple the
accepted ticket to `build/Liddddd.app`, then recreate the final ZIP and checksum
before attaching them to a GitHub Release.

## Release checklist

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
2. Update `LidddddConstants.helperVersion` when the helper changes. Increment
   `protocolVersion` only for an incompatible app/helper protocol change.
3. Run the full source validation commands.
4. Create the Developer ID release build.
5. Confirm the bundle contains no `manage-local-helper.sh` or legacy helper
   plist.
6. Notarize, staple, and repackage the app.
7. Verify code signing and Gatekeeper assessment on the final app.
8. Upload the final ZIP and SHA-256 checksum to GitHub Releases.
9. Test installation, helper approval, start, automatic stop, manual stop, and
   helper removal on a separate Mac or clean user account.

Do not treat a successful build or notarization as proof of real lid-close,
battery-limit, or temperature-cutoff behavior. Record those hardware checks
separately for each release.
