<p align="center">
  <img src="Artwork/liddddd-appicon.png" alt="Liddddd app icon" width="160">
</p>

<h1 align="center">Liddddd</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/UI-AppKit-000000?logo=apple&logoColor=white" alt="AppKit">
  <img src="https://img.shields.io/badge/Build-SwiftPM-F05138?logo=swift&logoColor=white" alt="Swift Package Manager">
</p>

Keep your Mac awake with its lid
closed. Super light & super useful.

## Features

- 15-minute to 8-hour sessions
- 10%, 20%, or 30% battery stop limits
- 90°C chip-temperature cutoff with macOS thermal-state fallback
- Automatic restoration of normal Mac sleep
- Detection of sleep settings changed by another app or command
- No analytics, accounts, network requests, or stored personal data

## Requirements

- Apple silicon Mac
- macOS 15 or later
- Administrator approval to install the sleep-control helper

## Remove

Before deleting the app, choose **Advanced → Remove Sleep Control…** to remove
the privileged helper and its saved session state. You can then quit Liddddd
and move `Liddddd.app` to the Trash.

## Privacy and security

Liddddd works entirely on your Mac. It does not use analytics, accounts, or
network services. Please report security issues privately as described in
[SECURITY.md](SECURITY.md).

## License

Liddddd is available under the [MIT License](LICENSE).
