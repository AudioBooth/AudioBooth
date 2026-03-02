import SwiftUI

struct EbookReaderPreferencesView: View {
  @ObservedObject var preferences: EbookReaderPreferences
  var onEditZones: (() -> Void)?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Typography") {
          Picker("Font Family", selection: $preferences.fontFamily) {
            ForEach(EbookReaderPreferences.FontFamily.allCases) { family in
              Text(family.rawValue).tag(family)
            }
          }

          Stepper(value: $preferences.fontSize, in: 0.1...5.0, step: 0.1) {
            HStack {
              Text("Font Size")
              Spacer()
              Text(preferences.fontSize.formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(.secondary)
            }
          }

          Stepper(value: $preferences.fontWeight, in: 0.0...2.5, step: 0.1) {
            HStack {
              Text("Font Weight")
              Spacer()
              Text(preferences.fontWeight.formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(.secondary)
            }
          }

          Toggle("Text Normalization", isOn: $preferences.textNormalization)
        }

        Section("Layout") {
          Toggle("Scroll Mode", isOn: $preferences.scroll)
          if preferences.scroll {
            Stepper(value: $preferences.autoScrollSpeed, in: 0.0...8.0, step: 0.5) {
              HStack {
                Text("Auto Scroll")
                Spacer()
                Text(
                  preferences.autoScrollSpeed == 0
                    ? "Off" : "\(preferences.autoScrollSpeed, format: .number.precision(.fractionLength(1)))×"
                )
                .foregroundStyle(.secondary)
              }
            }
          }
          Toggle("Tap to Navigate", isOn: $preferences.tapToNavigate)

          if preferences.tapToNavigate, let onEditZones {
            Button {
              onEditZones()
            } label: {
              HStack {
                Text("Tap Zones")
                  .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                  .foregroundStyle(.secondary)
                  .font(.caption)
              }
            }
          }

          Picker("Page Margins", selection: $preferences.pageMargins) {
            ForEach(EbookReaderPreferences.PageMargins.allCases) { margins in
              Text(margins.rawValue).tag(margins)
            }
          }
        }

        Section("Appearance") {
          Picker("Theme", selection: $preferences.theme) {
            ForEach(EbookReaderPreferences.Theme.allCases) { theme in
              Text(theme.rawValue).tag(theme)
            }
          }
        }

        Section("Advanced Typography") {
          Toggle("Publisher Styles", isOn: $preferences.publisherStyles)

          if !preferences.publisherStyles {
            Stepper(value: $preferences.lineHeight, in: 1.0...2.0, step: 0.1) {
              HStack {
                Text("Line Height")
                Spacer()
                Text(String(format: "%.1f", preferences.lineHeight))
                  .foregroundStyle(.secondary)
              }
            }

            Stepper(value: $preferences.paragraphIndent, in: 0.0...2.0, step: 0.2) {
              HStack {
                Text("Paragraph Indent")
                Spacer()
                Text(preferences.paragraphIndent.formatted(.percent.precision(.fractionLength(0))))
                  .foregroundStyle(.secondary)
              }
            }

            Stepper(value: $preferences.paragraphSpacing, in: 0.0...2.0, step: 0.1) {
              HStack {
                Text("Paragraph Spacing")
                Spacer()
                Text(preferences.paragraphSpacing.formatted(.percent.precision(.fractionLength(0))))
                  .foregroundStyle(.secondary)
              }
            }

            Stepper(value: $preferences.wordSpacing, in: 0.0...1.0, step: 0.1) {
              HStack {
                Text("Word Spacing")
                Spacer()
                Text(preferences.wordSpacing.formatted(.percent.precision(.fractionLength(0))))
                  .foregroundStyle(.secondary)
              }
            }

            Stepper(value: $preferences.letterSpacing, in: 0.0...1.0, step: 0.1) {
              HStack {
                Text("Letter Spacing")
                Spacer()
                Text(preferences.letterSpacing.formatted(.percent.precision(.fractionLength(0))))
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .navigationTitle("Reader Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close", systemImage: "xmark") {
            dismiss()
          }
          .tint(.primary)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}
