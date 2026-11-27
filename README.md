# Kurinji iOS app — GitHub build project

This project packages the supplied Kurinji SwiftUI source and resources for XcodeGen and GitHub Actions.

## Included from the supplied ZIP

- `Sources/`: KurinjiApp.swift, DB.swift, Views1.swift, Views2.swift, Views3.swift
- `Resources/Assets.xcassets/`: original image assets
- `Resources/inventory.db`: supplied SQLite database, retained as requested
- `project.yml`: XcodeGen project definition
- `.github/workflows/ios-build.yml`: macOS CI build and optional signed Ad Hoc IPA export

## IMPORTANT — private business data

The included SQLite database contains existing business records (products, sales, customers, suppliers, billing and ledger rows). Keep this GitHub repository **Private**. Do not publish this repository publicly. The database is copied into the app bundle and copied to the app's Documents directory on first launch. Subsequent inventory changes are stored locally on that iPhone.

## Build simulator app on GitHub

1. Create a **Private** GitHub repository named `KurinjiApp`.
2. Upload all files in this folder to the repository root, preserving `.github/workflows/ios-build.yml`.
3. Open the repository's **Actions** tab.
4. Run **Kurinji iOS build** (or push to `main`).
5. Download the `Kurinji-iOS-Simulator-app` artifact to inspect the CI build output. This `.app` is for the iOS Simulator and is **not installable on a physical iPhone**.

## Signed iPhone IPA

The workflow's `signed-ipa` job requires a valid Apple Distribution certificate exported as a password-protected `.p12`, and an Ad Hoc provisioning profile that includes the target iPhone's UDID and the bundle ID `com.kurinji.inventory`.

Add these GitHub repository Actions secrets:

- `IOS_DISTRIBUTION_CERT_P12_BASE64`: base64 encoding of the `.p12` certificate file
- `IOS_DISTRIBUTION_CERT_PASSWORD`: password used when exporting the `.p12`
- `IOS_ADHOC_PROFILE_BASE64`: base64 encoding of the Ad Hoc `.mobileprovision` file
- `APPLE_TEAM_ID`: 10-character Apple Developer Team ID

Then run the workflow manually from **Actions → Kurinji iOS build → Run workflow**. If signing is configured correctly, download `Kurinji-iPhone-AdHoc-IPA` from the workflow artifacts.

### Create base64 values on Windows PowerShell

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\distribution.p12")) | Set-Clipboard
```
Paste that value into the `IOS_DISTRIBUTION_CERT_P12_BASE64` secret. Repeat for the `.mobileprovision` file and save it as `IOS_ADHOC_PROFILE_BASE64`.

Never paste certificates, private keys, passwords, or provisioning profiles into chat or commit them to GitHub.

## Install on iPhone 15

An Ad Hoc IPA can be installed only on devices registered in the provisioning profile. Use an Apple-supported installation/distribution method such as Apple Configurator or an appropriate device-management/install service. A free Apple ID does not provide an Ad Hoc distribution certificate/profile; a paid Apple Developer Program membership is normally required for this distribution route. TestFlight is another distribution option, but it uses App Store Connect distribution rather than Ad Hoc.

## Login noted in the supplied README

The supplied README lists `admin` / `Kurinji@123`. Change this default before real business use. The source currently compares a fixed SHA-256 password hash in `Sources/KurinjiApp.swift`.

## Build requirements and caveats

- Xcode/macOS is required; the workflow uses a GitHub-hosted macOS runner.
- Deployment target is iOS 17.0.
- This is a local, single-device SQLite app. GitHub does not sync live inventory between devices.
- The source archive was not compiled in this environment. The first GitHub Actions run is the compile check; resolve any compiler diagnostics shown there before relying on the IPA.
