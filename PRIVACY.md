# Privacy Policy for AudioBooth

**Last Updated: September 2, 2026**

## Overview

AudioBooth is a client application for self-hosted [audiobookshelf](https://www.audiobookshelf.org) servers. This privacy policy explains how the app handles your data.

**Note:** AudioBooth is an independent third-party client and is not affiliated with or endorsed by the audiobookshelf project.

## Developer Information

AudioBooth is developed and maintained by [@jeremygrenier](https://github.com/jeremygrenier).

## Data Collection and Usage

### Information You Provide

**Server Connection Details:**
- Your audiobookshelf server URL
- Authentication credentials (username/password or OAuth tokens)
- Selected library preferences

This information is:
- Stored securely on your device using Apple's Keychain
- Never transmitted to any third party
- Only used to connect to YOUR self-hosted audiobookshelf server

**Downloaded Content:**
- Audiobook files you choose to download are stored locally on your device
- This data remains on your device and is not transmitted elsewhere
- You can delete this data at any time through the app's settings

**Read Along (iOS 26 and later):**
- When you turn on Read Along, the app transcribes the audiobook you are listening to in order to find the matching passage in the ebook
- Transcription uses Apple's on-device speech models; the audio and the resulting text never leave your device and are never sent to the developer or any third party
- Nothing is written to disk: the transcript is held in memory only while Read Along is running and is discarded when you turn it off or close the reader
- Turning on Read Along may download an Apple speech model for your book's language, which is handled by the operating system

### Information Automatically Collected

**In-App Purchases (RevenueCat):**
- When you make an optional tip/donation through the app, RevenueCat processes the transaction
- RevenueCat may collect: transaction data, device identifiers, and purchase history
- This data is used solely for purchase processing and restoration
- RevenueCat's Privacy Policy: https://www.revenuecat.com/privacy

**Apple Watch Sync:**
- If you use the Apple Watch companion app, playback state and authentication data is synced between your iPhone and Apple Watch
- This sync occurs only between your devices via iCloud and is not accessible to the developer

### Information NOT Collected

AudioBooth does NOT collect, store, or transmit:
- Usage analytics
- Crash reports
- Browsing history
- Listening history
- Personal information beyond what's necessary for server authentication
- Location data
- Contact information
- Any data from your audiobookshelf server

## Data Storage

All data is stored locally on your device:
- **Keychain:** Server URL and authentication credentials
- **Local Storage:** Downloaded audiobook files, playback progress, and app preferences
- **Watch Sync:** Authentication and playback state (synced via Apple's WatchConnectivity framework)

## Data Sharing

AudioBooth does NOT share your data with third parties, except:
- **Your audiobookshelf Server:** The app communicates directly with the server URL you provide to stream and download audiobooks
- **RevenueCat:** Only if you choose to make a purchase through the tip jar feature

## Third-Party Services

**RevenueCat (In-App Purchases):**
- Used for processing optional tips/donations
- Privacy Policy: https://www.revenuecat.com/privacy
- Terms of Service: https://www.revenuecat.com/terms

**Your audiobookshelf Server:**
- AudioBooth connects to YOUR self-hosted server
- Any data processing is subject to your own server's policies
- The developer has no access to or control over your server

## Data Security

- Server credentials are stored securely using Apple's Keychain Services
- All communication with your audiobookshelf server follows the security protocol you've configured (HTTP/HTTPS)
- Downloaded files are stored in the app's sandboxed container, protected by iOS security

## Your Rights

You have the right to:
- **Access:** View all data stored by the app in Settings
- **Delete:** Clear all stored data through "Clear Storage" in Settings
- **Control:** Choose what to download and what data to store

## Children's Privacy

AudioBooth does not knowingly collect information from children under 13. The app is designed for general audiences and does not contain age-inappropriate content.

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be reflected by updating the "Last Updated" date at the top of this policy.

## Contact

For questions about this privacy policy or data practices, please contact:

**Email:** audiobooth@proton.me

---

**Summary:**
AudioBooth is a privacy-focused client app. Your data stays on your device and your self-hosted server. We don't collect analytics, track usage, or share your information with third parties (except RevenueCat for optional purchases).