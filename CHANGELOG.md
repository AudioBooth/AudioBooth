# Changelog
 
All notable changes to AudioBooth will be documented in this file.
 
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Apple Watch podcasts - Podcast episodes now show in Continue Listening on the watch, you can browse a podcast's episodes, and send an episode to your watch from its context menu on iPhone
- System volume slider - New player preference to show the device volume slider under the playback controls
- Author and narrator sorting - Book lists for an author or narrator can now be sorted
- Audio bitrate - Book details now show the audio bitrate in the metadata section

### Changed
- Mini player on large screens - On wide screens, the mini player now shows time remaining, speed, skip, sleep timer, and queue controls
- Finished episodes - Playing a finished podcast episode now starts it from the beginning
- Player background - Improved cover color extraction for richer player and home episode card backgrounds
- iPhone Duo - Polished layouts for book details, the player, and the listening stats card
- Home episode cards - Refreshed design with more readable text, and cards in Continue Listening now follow the Continue section size preference
- Playback with volume at 0 - Starting playback with the volume at 0 now raises the volume, and pauses if it stays muted
- Next chapter on last chapter - The next chapter button now moves to the next item when Smart Continue is on (thanks @nyxaria)
- Auto sleep timer - Now starts automatically when the time window begins while you're already listening
- Apple Watch complications - The rectangular complication now shows the cover, chapter title, and time remaining, with a refreshed circular complication
- Read Along - Tapping Read Along in the ebook reader now starts the audiobook if it isn't playing, and narrated EPUBs open faster
- Continue Reading - Narrated EPUBs now show in Continue Reading instead of Continue Listening
- Book details actions - The Play button now always appears first for narrated EPUBs
- Downloads sorting - Sort downloads by date downloaded, title, or duration in ascending or descending order, also used by CarPlay and Assistive Access
- Catch Up - No longer runs while the app is in the background, and the ebook is prepared faster
- Auto-download - Now also downloads podcast episodes as you play them
- Remove after unused - Now also applies to podcast episodes

### Fixed
- Pinned playlist auto-download - Fixed podcast episodes in a pinned playlist not downloading automatically
- Narrated EPUB animations - Fixed the narration download progress animation on book details, and the Read Along button now animates while the narration plays
- Podcast playback - Fixed episodes not playing when their duration is missing, a UI freeze when streaming, Continue Listening in podcast libraries, Now Playing metadata, the Home episode card not showing pause, and Play All playing finished episodes (thanks @Creationsss)
- Sleep timer Live Activity - Fixed the Live Activity pausing with playback even when the timer is set to keep running while paused

## [1.13.0]

### Added
- EPUB 3 narration - EPUBs with built-in narration (Media Overlays) can now be downloaded to listen like an audiobook, with the full player, chapters, and progress sync. Read Along highlights the narrated sentence in the reader, and turning pages while paused moves the narration to your page
- Assistive Access support - AudioBooth now works in Assistive Access mode, with a simplified list of your downloaded books and an easy to use player
- Assisted Player - New player preference that shows a simplified player with only large play and skip buttons
- Ebook reader progress header - New reader preference to show a header with the chapter title, chapter progress or page count, and overall book progress
- Read Along sentence highlight - New reader preference to turn off highlighting of the narrated sentence
- Bookmarks sorting - Sort bookmarks by time or date added, in ascending or descending order, and your choice is remembered
- CarPlay Library tab - Browse books, series, collections, and playlists from a new Library tab in CarPlay
- Apple Watch improvements - Send a book to your watch directly from the book details page on iPhone, and hand off playback from the watch player to your iPhone
- Ebook reader Play from Here - Select a passage in the ebook to start the audiobook from that spot, with Catch Up now offered directly in the reader's player
- Dynamic progress bar color - New player preference to tint the progress bar with the book cover color
- Podcast library improvements - Home sections now show episode cards for the latest episodes, and the latest episodes page adds swipe actions to queue or mark as finished, a context menu, and a play button on each episode

### Changed
- Now Playing artwork - Cover art now scales properly to the size requested by the lock screen, Control Center, and connected devices
- Equalizer - Added a 6 kHz band, and you can now save your own custom presets (long press a custom preset to delete it)
- Sleep timer extend - Pressing play or pause from headphones or the lock screen, or turning up the volume while the timer is fading out, now extends the sleep timer
- Auto download books - Books added to the queue now download automatically
- CarPlay improvements - Author images now display, downloads follow your offline sort order, and time left reflects the currently playing book
- Download storage check - Downloads now check available device storage and stop with a message when there isn't enough space
- Maximum storage options - Added 100 GB, 200 GB, and 500 GB download storage limits
- Ebook reader preferences sync - Volume navigation, auto scroll speed, progress header, and Read Along preferences now sync with iCloud
- Player cover on iPad - The cover art in the player can now display larger on iPad
- Session device info - Listening sessions now report the device model to the server
- Book player improvements - The player now opens full screen with a zoom transition from the mini player, with refreshed controls, a time bubble while scrubbing, and fine scrubbing (drag down for half-speed or quarter-speed precision)
- iPhone Duo - Layouts now adapt around the hinge on book details, podcast details, the player, library pages, and the ebook reader
- Progress sync - The currently playing item now refreshes its progress from the server when you return to the app

### Fixed
- Listening activity heatmap - Fixed overlapping month labels on the stats page and widget
- Player sheets - Fixed incorrect sheet heights in the player
- Sleep timer extend - Fixed playing or shaking after the extend window expired not resetting the sleep timer alert
- Book and podcast details - Fixed a cover layout glitch in landscape
- Screen backgrounds - Fixed backgrounds not extending behind the safe areas on several screens
- Ebook current chapter - Fixed the current chapter not being detected correctly in the reader
- Playback recovery - Fixed repeated recovery attempts after the system audio services reset
- Watch player - Fixed a duration error caused by progress being reported while paused
- Continue Listening - Fixed removing the currently playing book from Continue Listening
- Smart rewind - Fixed smart rewind when streaming
- Mark as finished - Fixed an issue where marking a book as finished could fail during playback
- Home page - Fixed home sections not updating correctly after switching libraries
- Watch app covers - Fixed covers not displaying correctly on the watch app

## [1.12.0]

### Added
- Catch Up - When you've read further in the ebook than you've listened, the player offers to skip the audiobook to where you stopped reading. Everything runs on device and requires iOS 26, with both the ebook and audiobook downloaded
- Page Match - Point the camera at a page of your printed book, or pick a photo of one you took earlier, to jump to that spot in the audiobook. Everything runs on device and requires iOS 26 (thanks @andrespinones)
- Read Along - Follow the ebook while the audiobook plays, with the narrated sentence highlighted and the page turning itself. Transcription happens entirely on device and requires iOS 26
- Total counts - Show total item counts on the library, authors, series, and collections pages
- Sleep timer Focus intent - Activate the auto sleep timer using a Focus (thanks @fivezeroes)
- Sleep timer pause behavior - Configurable sleep timer behavior when playback is paused (thanks @fivezeroes)

### Changed
- Downloads revamp - Full revamp of how downloads are handled, with improved multi-track and background downloads, the ability to resume failed downloads, and better overall stability
- Podcast episode download indicator - Improved visibility of the download indicator
- Adaptive sheets - Now scroll to support large font sizes
- Mac Catalyst sheets - Added a close button to adaptive sheets (thanks @kornelko2)
- Player - Now closes when a finished book has nothing to play next (thanks @kornelko2)
- Multitrack audio - Improved audio player handling of multitrack books

### Fixed
- Multi-file downloads - Fixed background downloads for books with multiple files (thanks @cbzehner)
- Series card covers - Fixed a layout issue with series card covers
- Series, genre, and tag lists - Fixed list content being hidden behind the mini player (thanks @kornelko2)
- Authors list - Fixed authors with zero books appearing in the list (thanks @kornelko2)
- Collection page - Fixed various issues on the collection page
- Media progress - Fixed media progress edge cases

## [1.11.0]

### Added
- Keep next items offline - New storage preference to automatically download what's next in started series and podcasts, with a configurable number of items
- Volume leveling - New equalizer option that evens out loud and quiet passages, with low, medium, and high strength
- Siri support - Use Siri to play a downloaded book or resume your current book
- Multi-select batch actions - Select multiple library books to add them to playlists and collections in a single action
- Share downloaded books - Share a downloaded ebook or audiobook from the book details menu (thanks @antdon)
- Podcast auto-queue - New per-podcast setting to automatically add newly published episodes to the queue, with an optional storage preference to download them automatically

### Changed
- Tip jar for sponsors - Tip jar section now collapses when you have an active sponsor subscription

### Fixed
- Podcast playback - Various improvements and fixes around podcast playback and episode management (thanks @Creationsss)
- Podcast library search - Fixed search failing in podcast libraries, now showing matching podcasts and episodes

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
