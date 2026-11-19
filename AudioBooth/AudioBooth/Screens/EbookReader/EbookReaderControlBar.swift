import Combine
import SwiftUI

struct EbookReaderControlBar: View {
  @ObservedObject var model: EbookReaderView.Model
  var onShowSettings: () -> Void

  @ObservedObject private var playerManager = PlayerManager.shared

  private let regularBarFitHeight: CGFloat = 37

  var body: some View {
    ViewThatFits(in: .vertical) {
      bar(isCompact: false)
        .frame(height: regularBarFitHeight)
      bar(isCompact: true)
    }
  }

  private func bar(isCompact: Bool) -> some View {
    HStack(alignment: .bottom, spacing: 0) {
      if model.chapters != nil {
        Button(action: { model.onTableOfContentsTapped() }) {
          item(Text("Contents"), isCompact: isCompact) {
            Image(systemName: "list.bullet")
          }
        }
        .frame(maxWidth: .infinity)
      }

      if model.supportsSettings {
        Button(action: {
          model.onSettingsTapped()
          onShowSettings()
        }) {
          item(Text("Settings"), isCompact: isCompact) {
            Image(systemName: "textformat.size")
          }
        }
        .frame(maxWidth: .infinity)
      }

      Button(action: { model.onProgressTapped() }) {
        item(Text(progressCaption), isCompact: isCompact) {
          Text(progressLabel)
            .font(.system(size: 16, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: 60)
        }
      }
      .frame(maxWidth: .infinity)

      if model.supportsReadAlong {
        Button(action: { model.onReadAlongTapped() }) {
          item(Text("Read Along"), isCompact: isCompact) {
            readAlongIcon
          }
        }
        .frame(maxWidth: .infinity)
        .tint(isReadAlongActive ? .accentColor : .primary)
      }

      if playerManager.current != nil || model.hasAudiobook {
        Button(action: model.onNowPlayingTapped) {
          item(Text("Now Playing"), isCompact: isCompact) {
            Image(systemName: "playpause.circle")
          }
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func item(_ title: Text, isCompact: Bool, @ViewBuilder icon: () -> some View) -> some View {
    VStack(spacing: isCompact ? 2 : 6) {
      icon()
        .font(.system(size: isCompact ? 17 : 20))
        .frame(height: 20)
      title
        .font(.caption2)
    }
  }

  private var progressLabel: String {
    if let page = displayedPage {
      return page.current.formatted()
    }
    return model.progress.formatted(.percent.precision(.fractionLength(0)))
  }

  private var progressCaption: String {
    if let page = displayedPage {
      return String(localized: "of \(page.total)")
    }
    return String(localized: "Progress")
  }

  private var displayedPage: (current: Int, total: Int)? {
    model.preferences.progressDisplay == .page ? model.page : nil
  }

  private var isReadAlongActive: Bool {
    if model.isFollowingMediaOverlay {
      return playerManager.isPlaying
    }
    return model.readAlong?.status.isActive == true
  }

  @ViewBuilder
  private var readAlongIcon: some View {
    if model.isFollowingMediaOverlay {
      Image(systemName: "waveform")
        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: playerManager.isPlaying)
    } else {
      readAlongStatusIcon
    }
  }

  @ViewBuilder
  private var readAlongStatusIcon: some View {
    switch model.readAlong?.status {
    case .preparing:
      ProgressView()
        .controlSize(.small)
    case .locating:
      Image(systemName: "waveform.badge.magnifyingglass")
    case .following:
      Image(systemName: "waveform")
        .symbolEffect(.variableColor.iterative, options: .repeating)
    case .failed:
      Image(systemName: "waveform.badge.exclamationmark")
    case .off, .none:
      Image(systemName: "waveform")
    }
  }
}
