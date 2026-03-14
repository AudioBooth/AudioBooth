# Contributing to AudioBooth

## Prerequisites

- Xcode 26+ (latest stable)
- An Apple ID (free account works)

## Building as a Contributor

Simulator builds work out of the box with no extra setup.

For **device builds**, the project is signed with the maintainer's Apple Developer account. You'll need a local signing configuration to build and run on a physical device.

### 1. Add your Apple ID to Xcode

Open the project in Xcode and go to **Settings → Accounts** (⌘,). Add your Apple ID if it's not already there. Select the account, then make sure there is a Team with your name listed in the Team section. If there is no team there, you may have to click the "Download Manual Profiles" button to generate the team.

### 2. Create your Local.xcconfig

Run the setup script from the project root:

```bash
scripts/setup_contributor
```

This will detect your available signing identities, let you pick one, and generate `Local.xcconfig` automatically.

Alternatively, you can set it up manually:

```bash
cp AudioBooth/Local.xcconfig.example AudioBooth/Local.xcconfig
```

Then edit `Local.xcconfig` and update:

- **`DEVELOPMENT_TEAM`**: your personal Team ID (visible in Xcode → Settings → Accounts)
- **`AB_BUNDLE_ID_BASE`**: use your GitHub username, e.g. `com.github.audiobooth-octocat`

The file is gitignored, so your local settings will never be committed.

This configuration automatically:
- Uses contributor-specific entitlements files (no iCloud, NFC, or CarPlay required, works with free Apple Developer accounts)
- Disables iCloud sync at compile time via the `CONTRIBUTOR_BUILD` flag
- All core functionality (playback, server connection, downloads, library browsing) works normally

### 3. Build

Simulator builds should work at this point.

For **device builds** on a free account, you'll also need to remove the **In-App Purchase** capability in Xcode (AudioBooth target → Signing & Capabilities → click × on In-App Purchase). This is because the app links StoreKit via RevenueCat, and free accounts can't provision with that capability. Revert this before committing with `git checkout -- AudioBooth/AudioBooth.xcodeproj`.

> **Note:** If you are a paying Apple Developer and want iCloud sync, remove the entitlements overrides (`AB_APP_ENTITLEMENTS`, `AB_WATCH_ENTITLEMENTS`, `AB_WIDGET_ENTITLEMENTS`) and the `SWIFT_ACTIVE_COMPILATION_CONDITIONS` line from your `Local.xcconfig` to use the full entitlements.

## Code Style

All Swift code should pass `swift-format`. Run:

```bash
# Run from the project root
xcrun swift-format format --in-place --recursive --parallel .
```

## Branch Naming

- `feature/<name>` for new features
- `fix/<name>` for bug fixes
