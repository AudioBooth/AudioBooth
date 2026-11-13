# AudioBooth

![Xcode](https://img.shields.io/badge/Xcode-26.0-blue?logo=Xcode&logoColor=white)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-red?logo=Swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17.0+-green?logo=apple&logoColor=white)
![watchOS](https://img.shields.io/badge/watchOS-10+-green?style=flat&logo=apple&logoColor=white)

[![AudioBooth App](https://raw.githubusercontent.com/AudioBooth/AudioBooth/refs/heads/main/images/AudioBooth.png)](https://apps.apple.com/us/app/id6753017503?platform=iphone)

Your personal audiobook companion for Audiobookshelf.

AudioBooth is a streamlined iOS client designed exclusively for Audiobookshelf users who value simplicity and performance. Built with a focus on essential audiobook listening features, AudioBooth delivers a clean, distraction-free experience for your self-hosted audiobook library.

## Features

- **Pure Audiobookshelf Integration** - Connect seamlessly to your personal Audiobookshelf server
- **Focused Audiobook Experience** - Purpose-built interface optimized for audiobook listening
- **Essential Playback Controls** - Variable speed, sleep timer, and chapter navigation
- **Progress Synchronization** - Keep your listening progress in sync across devices
- **Offline Downloads** - Download audiobooks for listening without an internet connection
- **Library Browsing** - Explore your books, authors, series, and collections
- **Background Playback** - Continue listening while using other apps
- **Lock Screen Controls** - Standard media controls on your lock screen
- **Chromecast Support** - Stream audiobooks directly to Chromecast, Google Home, and Nest speakers ([setup guide](docs/CHROMECAST.md))
- **Apple Watch Support** - Control playback and browse your library from your wrist
- **Clean, Native Design** - Intuitive interface that feels at home on iOS

AudioBooth focuses on what matters most: enjoying your audiobooks. No unnecessary features, no bloat - just a reliable, efficient way to access your Audiobookshelf library on your iPhone, iPad, and Apple Watch.

## Requirements

- iOS 17.0 or later
- watchOS 10.0 or later
- An existing [Audiobookshelf](https://audiobookshelf.org) server

**Note:** AudioBooth requires an existing Audiobookshelf server to function. The app does not include any media content.

## Installation

### App Store

Download AudioBooth from the App Store: [https://apps.apple.com/us/app/id6753017503](https://apps.apple.com/us/app/id6753017503?platform=iphone)

### Building from Source

1. Clone the repository:
```
git clone https://github.com/AudioBooth/AudioBooth.git
cd AudioBooth
```
2. Open the project in Xcode 26
3. Build and run the project on your device or simulator


## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

**Note:** This project is in active early development. The main branch may be rebased and force-pushed to keep the git history clean. Apologies for any inconvenience this may cause!

### Getting Started

1. Fork the repository
2. Clone your fork and install pre-commit hooks:
```
git clone https://github.com/AudioBooth/AudioBooth.git
cd AudioBooth
pre-commit install
```
3. Create your feature branch (`git checkout -b feature/amazing-feature`)
4. Make your changes following the project guidelines
5. Commit your changes (`git commit -m 'Add some amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Guidelines

- Follow the View/Model/ViewModel architecture pattern
- Use Swift 6.2 with modern concurrency (async/await)
- Keep changes simple and focused
- Test on iPhone, iPad, and Apple Watch when applicable

## Privacy

AudioBooth takes your privacy seriously. See [PRIVACY.md](PRIVACY.md) for details on data handling and privacy practices.

## License

This project is licensed under the Mozilla Public License Version 2.0 - see the [LICENSE](LICENSE) file for details.

## Disclaimer

AudioBooth is an independent client application and is not affiliated with the Audiobookshelf project.

## Support

If you encounter any issues or have questions:

- Open an issue on [GitHub](https://github.com/AudioBooth/AudioBooth/issues)
- Visit the [Audiobookshelf documentation](https://www.audiobookshelf.org/docs) for server-related questions

## Dependencies

- [Google Cast iOS SDK](https://github.com/googlecast/google-cast-ios-sdk) - Chromecast device discovery and media streaming
- [SimpleKeychain](https://github.com/auth0/SimpleKeychain) - Secure credential storage
- [KSCrash](https://github.com/kstenerud/KSCrash) - Local crash reporting and diagnostics
- [Nuke](https://github.com/kean/Nuke) - Efficient image loading and caching
- [Pulse](https://github.com/kean/Pulse) - Network logger and debugging tool
- [Readium Swift Toolkit](https://github.com/readium/swift-toolkit) - EPUB and PDF ebook reader
- [RevenueCat](https://www.revenuecat.com) - In-app purchase support
- [RichText](https://github.com/NuPlay/RichText) - RichText HTML rendering

## Acknowledgments

- [Audiobookshelf](https://github.com/advplyr/audiobookshelf) - For creating an amazing self-hosted audiobook server
