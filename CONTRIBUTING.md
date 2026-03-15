# Contributing to AudioBooth

## Prerequisites

- Xcode 26+ (latest stable)
- An Apple ID (free account works for simulator builds)

## Building as a Contributor

Simulator builds work out of the box with no extra setup.

For **device builds**, you'll need a local signing configuration.

### 1. Add your Apple ID to Xcode

Open the project in Xcode and go to **Settings → Accounts** (⌘,). Add your Apple ID if it's not already there. Select the account, then make sure there is a Team with your name listed in the Team section. If there is no team there, you may have to click the "Download Manual Profiles" button to generate the team.

### 2. Create your Local.xcconfig

```bash
cp AudioBooth/Local.xcconfig.example AudioBooth/Local.xcconfig
```

Edit `Local.xcconfig` and update:

- **`DEVELOPMENT_TEAM`**: your personal Team ID (visible in Xcode → Settings → Accounts)
- **`ORG_IDENTIFIER`**: something unique to you, e.g. `com.yourname`

The file is gitignored, so your local settings will never be committed.

### 3. Build

Simulator builds should work at this point.

For device builds on a free account, you'll need to temporarily remove some capabilities that free accounts can't provision. In Xcode, go to each target's Signing & Capabilities tab and remove:

**AudioBooth target:**
- In-App Purchase
- NFC Tag Reading
- iCloud (Key-value storage)

**AudioBooth Watch App target:**
- Access Wi-Fi Information

## Code Style

All Swift code should pass `swift-format`. Run:

```bash
xcrun swift-format format --in-place --recursive --parallel .
```

## Branch Naming

- `feature/<name>` for new features
- `fix/<name>` for bug fixes
