import Combine
import RevenueCat
import StoreKit
import SwiftUI

struct TipJarView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var model: Model

  var body: some View {
    if !model.tips.isEmpty {
      Section {
        VStack(alignment: .leading, spacing: 16) {
          header

          ForEach(model.subscriptionTips) { tip in
            subscriptionCard(tip)
              .allowsHitTesting(model.isPurchasing == nil)
              .opacity([nil, tip.id].contains(model.isPurchasing) ? 1.0 : 0.4)
          }

          if !model.oneTimeTips.isEmpty {
            Divider()

            Text("ONE-TIME TIP")
              .font(.caption2)
              .fontWeight(.semibold)
              .foregroundStyle(.secondary)

            HStack(spacing: 10) {
              ForEach(model.oneTimeTips) { tip in
                oneTimeCard(tip)
                  .allowsHitTesting(model.isPurchasing == nil)
                  .opacity([nil, tip.id].contains(model.isPurchasing) ? 1.0 : 0.4)
              }
            }

            Text("Tip to thank and support the developer.")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }

          if model.isSandbox {
            HStack(spacing: 4) {
              Text("TestFlight:")
                .foregroundStyle(.red)
                .fontWeight(.semibold)
              Text("Test purchases only.")
                .foregroundStyle(.secondary)
              Link(destination: URL(string: "https://apps.apple.com/us/app/id6753017503")!) {
                HStack(spacing: 2) {
                  Text("Open App Store")
                  Image(systemName: "arrow.up.forward")
                    .font(.caption2)
                }
                .foregroundStyle(.pink)
              }
              Spacer(minLength: 0)
            }
            .font(.caption)
          }

          if model.lastPurchaseSuccess {
            HStack(spacing: 8) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
              Text("Thank you for your support!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .transition(.scale.combined(with: .opacity))
          }
        }
        .padding(16)
        .listRowInsets(EdgeInsets())
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Sponsor")
      }
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .animation(.easeInOut(duration: 0.3), value: model.lastPurchaseSuccess)
    }
  }

  @ViewBuilder
  private var header: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.pink.opacity(0.15))
        .frame(width: 44, height: 44)
        .overlay(
          Image(systemName: "heart")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.pink)
        )

      VStack(alignment: .leading, spacing: 2) {
        Text("Help sustain AudioBooth")
          .font(.headline)
          .foregroundStyle(.primary)
        Text("Indie app. Powered by supporters.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private func subscriptionCard(_ tip: Model.Tip) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("SUPPORTER")
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text(tip.price)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(.pink)
          Text(verbatim: "/mo")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 0)

      Button(action: { model.onTipSelected(tip) }) {
        Text("Subscribe")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.white)
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .background(
            Capsule().fill(.pink)
          )
      }
      .buttonStyle(.plain)
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(.pink.opacity(0.08))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.pink.opacity(0.25), lineWidth: 1)
    )
  }

  @ViewBuilder
  private func oneTimeCard(_ tip: Model.Tip) -> some View {
    Button(action: { model.onTipSelected(tip) }) {
      VStack(spacing: 4) {
        Text(tip.title)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(tip.price)
          .font(.title3)
          .fontWeight(.bold)
          .foregroundStyle(.primary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.gray.opacity(0.08))
      )
    }
    .buttonStyle(.plain)
  }
}

extension TipJarView {
  @Observable
  class Model: ObservableObject {
    struct Tip: Identifiable {
      let id: String
      let title: String
      let price: String
    }

    var tips: [Tip]
    var isPurchasing: String?
    var lastPurchaseSuccess: Bool
    var isSandbox: Bool

    var subscriptionTips: [Tip] {
      tips.filter { $0.id.hasPrefix("$rc_") }
    }

    var oneTimeTips: [Tip] {
      tips.filter { !$0.id.hasPrefix("$rc_") }
    }

    func onTipSelected(_ tip: Tip) {}

    init(
      tips: [Tip] = [],
      isPurchasing: String? = nil,
      lastPurchaseSuccess: Bool = false,
      isSandbox: Bool = false
    ) {
      self.tips = tips
      self.isPurchasing = isPurchasing
      self.lastPurchaseSuccess = lastPurchaseSuccess
      self.isSandbox = isSandbox
    }
  }
}

extension TipJarView.Model {
  static var mock = TipJarView.Model(
    tips: [
      Tip(
        id: "coffee",
        title: "Buy Me a Coffee ☕",
        price: "$2.99"
      ),
      Tip(
        id: "lunch",
        title: "Buy Me Lunch 🍕",
        price: "$4.99"
      ),
      Tip(
        id: "dinner",
        title: "Buy Me Dinner 🍱",
        price: "$9.99"
      ),
    ]
  )
}

#Preview("TipJar") {
  TipJarView(model: .mock)
    .padding()
}
