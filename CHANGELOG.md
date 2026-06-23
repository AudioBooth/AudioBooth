# Changelog
 
All notable changes to AudioBooth will be documented in this file.
 
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Siri support - Use Siri to play a downloaded book or resume your current book
- Multi-select batch actions - Select multiple library books to add them to playlists and collections in a single action
- Share downloaded books - Share a downloaded ebook or audiobook from the book details menu (thanks @antdon)
- Podcast auto-queue - New per-podcast setting to automatically add newly published episodes to the queue, with an optional storage preference to download them automatically

## [1.10.0]

### Added
- Alarm support - Set an alarm to interrupt playback at a specific time or after a duration (thanks @DonQuinleone)
- Repeat support - Repeat the current book, episode, or chapter during playback
- Card preferences page - New dedicated preferences page to customize card appearance
- Cover flow for continue section - New cover flow display for the continue section
- Mix with other audio - New audio player preference to mix playback with other audio sources
- Ebook reader volume navigation - New preference to navigate ebook pages using the volume buttons
- Lock screen and player preferences - Added more preferences to customize the lock screen and player experience
- Haptic feedback - Add haptic feedback throughout the app for improved tactile interaction
- Watch app custom header - Add custom header to the watch app for a more refined look
- Book subtitle preference - Add preference to display book subtitles in the library
- Ebook reader auto theme - Add auto mode to ebook reader theme that follows system appearance
- Watch app sections - Add more sections on the watch app for quicker access to your library
- CarPlay library selection - Choose which library to browse directly from CarPlay
- Playlist and collection downloads - Download all support for playlists and collections in a single action

### Changed
- Stats page revamp - Revamped stats page with a refreshed design and improved insights
- Book downloads - Audiobook and ebook are now fetched together in a single download action, with accurate state and progress reflecting what's on disk
- Preferences revamp - Revamped preferences with an adjusted page color palette for a refreshed look
- Smart rewind pause threshold - Pause threshold is now dynamic for more accurate smart rewind behavior
- Alternate URL verification - Improved alternate URL verification for more reliable fallback
- Auth token refresh - Improved authentication token refresh to better handle rate limits

### Fixed
- Offline page filter - Fixed filter behavior on the offline page

## [1.9.0]
 
### Added
- Stats widgets - New widgets to display your listening statistics on your home screen
- Series progress management - Reset all progress or mark as read directly from the series details page (thanks @octopotato)
- Smart continue playback - Automatically play the next episode, book in series, or playlist/collection item when playback ends
- Pinned playlist preferences - Auto-download uncompleted books and auto-remove completed books from your pinned playlist
- Series page sort by - Sort series by name, number of books, date added, and more
- CarPlay podcast support - Browse and play podcasts and episodes directly from CarPlay
- Latest podcast episodes tab - Quickly access the latest podcast episodes in a dedicated tab
- Equalizer support - Customize your audio with equalizer settings in the audio player for enhanced sound quality
- Apple Watch complications - Add AudioBooth complications to your watch face for quick access to playback controls and information
 
### Changed
- Watch playback speed control - Control playback speed directly from the local Apple Watch player
- Speed and volume presets edition - Edit and customize your playback speed and volume presets
- Ebook sub chapters - Navigate ebook chapters with sub chapter support for more precise navigation
- CarPlay home for iOS 26 - Enhanced CarPlay home screen experience optimized for iOS 26
- Download progress display - Downloading info now shows both percentage and size progress for better tracking
- Metadata display - Book and episode metadata sections now include file size information
- Book details layout - Authors and narrators now display in separated sections for better clarity and organization
- Alternative URL fallback - Automatically fallback to alternative URL on connectivity issues for improved reliability
- Unified playback speed - Playback speed is now unified across CarPlay and the app for a consistent experience
- Completed book listen again - Enhanced listen again functionality for completed books with better user experience
 
### Fixed
- Playback codec mismatch - Fixed playback failure when file codec doesn't match extension (thanks @Creationsss)
- Ebook remote progress - Fixed ebook remote progress sync issue
- Library filters - Fixed excessive page refreshing when applying filters
