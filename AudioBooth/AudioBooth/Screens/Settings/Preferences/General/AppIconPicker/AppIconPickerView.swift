import Combine
import SwiftUI

struct AppIconPickerView: View {
  @ObservedObject private var model: Model = AppIconPickerViewModel.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("App Icon")
          .font(.subheadline)
          .fontWeight(.medium)
        Spacer()
        Text("Light · Dark variants")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Row(model: model)
    }
    .onAppear(perform: model.onAppear)
  }
}

extension AppIconPickerView {
  struct Row: View {
    @ObservedObject var model: Model

    var body: some View {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 16) {
            ForEach(Model.AppIcon.allCases) { icon in
              iconButton(icon)
            }
          }
          .padding(.vertical, 4)
          .padding(.horizontal, 16)
        }
        .onAppear {
          DispatchQueue.main.async {
            proxy.scrollTo(model.currentIcon.id, anchor: .center)
          }
        }
        .onChange(of: model.currentIcon) { _, newValue in
          withAnimation {
            proxy.scrollTo(newValue.id, anchor: .center)
          }
        }
      }
      .padding(.horizontal, -16)
    }

    @ViewBuilder
    private func iconButton(_ icon: Model.AppIcon) -> some View {
      Button {
        model.setAlternateAppIcon(icon: icon)
      } label: {
        VStack(spacing: 8) {
          HStack(spacing: 6) {
            iconImage(icon, scheme: .light)
            iconImage(icon, scheme: .dark)
          }
          .padding(4)
          .overlay(
            RoundedRectangle(cornerRadius: 14)
              .stroke(model.currentIcon == icon ? Color.accentColor : .clear, lineWidth: 2)
          )

          Text(icon.displayName)
            .font(.caption)
            .foregroundStyle(.primary)
        }
      }
      .buttonStyle(.plain)
      .disabled(model.isChanging)
      .id(icon.id)
    }

    @ViewBuilder
    private func iconImage(_ icon: Model.AppIcon, scheme: ColorScheme) -> some View {
      Image(icon.previewImageName)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 52, height: 52)
        .cornerRadius(11)
        .colorScheme(scheme)
    }
  }
}

extension AppIconPickerView {
  @Observable
  class Model: ObservableObject {
    var currentIcon: AppIcon
    var isChanging: Bool

    func onAppear() {}
    func setAlternateAppIcon(icon: AppIcon) {}

    init(currentIcon: AppIcon = .default, isChanging: Bool = false) {
      self.currentIcon = currentIcon
      self.isChanging = isChanging
    }
  }
}

extension AppIconPickerView.Model {
  enum AppIcon: String, CaseIterable, Identifiable {
    case `default` = "AppIcon"
    case blue = "AppIcon-Blue"
    case purple = "AppIcon-Purple"
    case green = "AppIcon-Green"
    case dark = "AppIcon-Dark"
    case red = "AppIcon-Red"
    case yellow = "AppIcon-Yellow"
    case teal = "AppIcon-Teal"
    case pink = "AppIcon-Pink"

    var id: String { self.rawValue }

    var previewImageName: String { "IconPreviews/" + self.rawValue }

    var displayName: LocalizedStringKey {
      switch self {
      case .default: "Default"
      case .blue: "Blue"
      case .purple: "Purple"
      case .green: "Green"
      case .dark: "Dark"
      case .red: "Red"
      case .yellow: "Yellow"
      case .teal: "Teal"
      case .pink: "Pink"
      }
    }
  }
}

#Preview {
  ScrollView {
    AppIconPickerView()
      .padding()
      .background(Color.Sepia.Background.card)
      .padding()
      .background(Color.Sepia.Background.page)
  }
}
