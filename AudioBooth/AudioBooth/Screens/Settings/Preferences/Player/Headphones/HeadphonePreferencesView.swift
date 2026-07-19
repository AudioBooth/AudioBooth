import Models
import SwiftUI

struct HeadphonePreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        HeadphoneHeaderCard()
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
      }

      Section {
        NavigationLink {
          HeadphoneActionPickerView(
            title: "Previous Action",
            gesture: .previous,
            selection: $preferences.headphonePreviousAction
          )
        } label: {
          PreferenceRow(
            systemImage: "backward.end",
            tint: .teal,
            title: Text("Previous Action"),
            subtitle: Text(preferences.headphonePreviousAction.displayText)
          )
        }
        .listRowBackground(theme.colors.background.card)

        NavigationLink {
          HeadphoneActionPickerView(
            title: "Next Action",
            gesture: .next,
            selection: $preferences.headphoneNextAction
          )
        } label: {
          PreferenceRow(
            systemImage: "forward.end",
            tint: .teal,
            title: Text("Next Action"),
            subtitle: Text(preferences.headphoneNextAction.displayText)
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Configure the headphone actions")
      } footer: {
        Text(
          "Overrides the next and previous gestures on your headphones. Bookmarks are saved at the current position."
        )
        .font(.caption)
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Headphone Controls")
  }
}

private struct HeadphoneHeaderCard: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "headphones")
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(0.85))
        )

      Text("Control with your headphones")
        .font(.title3)
        .fontWeight(.bold)

      Text("Bookmark or control playback using the next and previous gestures on your headphones.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }
}

private struct HeadphoneActionPickerView: View {
  @Environment(\.appTheme) var theme
  @Environment(\.dismiss) private var dismiss

  let title: LocalizedStringKey
  let gesture: HeadphoneGesture
  @Binding var selection: HeadphoneAction

  var body: some View {
    Form {
      Section {
        ForEach(HeadphoneAction.allCases) { action in
          Button {
            selection = action
            Haptics.selection()
            dismiss()
          } label: {
            HStack(spacing: 12) {
              PreferenceRow(
                systemImage: action.systemImage,
                tint: .teal,
                title: Text(action.displayText),
                subtitle: action == .default ? Text(defaultSubtitle) : Text?.none
              )
              Spacer(minLength: 0)
              if action == selection {
                Image(systemName: "checkmark")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(Color.accentColor)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .listRowBackground(theme.colors.background.card)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var defaultSubtitle: LocalizedStringResource {
    switch gesture {
    case .next: "Skip forward or next chapter"
    case .previous: "Skip back or previous chapter"
    }
  }
}

#Preview {
  NavigationStack {
    HeadphonePreferencesView()
  }
}
