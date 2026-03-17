import Combine
import RevenueCat
import StoreKit
import SwiftUI

struct TipJarView: View {
  @ObservedObject var model: Model

  var body: some View {
    if !model.tips.isEmpty {
      Section {
        VStack(spacing: 12) {
          ForEach(model.subscriptionTips) { tip in
            Button(action: { model.onTipSelected(tip) }) {
              HStack(spacing: 12) {
                Image(systemName: "heart")
                  .font(.system(size: 28))
                  .foregroundStyle(.pink)

                Text(tip.description)
                  .font(.footnote)
                  .foregroundStyle(.primary)
                  .frame(maxWidth: .infinity, alignment: .leading)

                Text(tip.price)
                  .font(.headline)
                  .fontWeight(.semibold)
                  .foregroundStyle(.primary)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 20)
              .padding(.horizontal, 20)
              .background(
                RoundedRectangle(cornerRadius: 20)
                  .fill(.pink.opacity(0.05))
              )
              .overlay(
                RoundedRectangle(cornerRadius: 20)
                  .strokeBorder(
                    .pink.opacity(0.3),
                    lineWidth: 2
                  )
              )
            }
            .buttonStyle(.plain)
            .allowsHitTesting(model.isPurchasing == nil)
            .opacity([nil, tip.id].contains(model.isPurchasing) ? 1.0 : 0.4)
          }

          if !model.oneTimeTips.isEmpty {
            HStack(spacing: 12) {
              ForEach(model.oneTimeTips) { tip in
                Button(action: { model.onTipSelected(tip) }) {
                  VStack(spacing: 8) {
                    Text(tip.title)
                      .font(.callout)
                      .allowsTightening(true)
                      .foregroundStyle(.primary)
                      .multilineTextAlignment(.center)
                      .fixedSize(horizontal: false, vertical: true)

                    Text(tip.price)
                      .font(.title2)
                      .fontWeight(.bold)
                      .foregroundStyle(.primary)

                    Text(tip.description)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .multilineTextAlignment(.center)
                  }
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
                  .padding(.vertical, 20)
                  .padding(.horizontal, 8)
                  .background(
                    RoundedRectangle(cornerRadius: 22)
                      .fill(Color(.systemBackground))
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 22)
                      .strokeBorder(Color(.systemGray5), lineWidth: 2)
                  )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(model.isPurchasing == nil)
                .opacity([nil, tip.id].contains(model.isPurchasing) ? 1.0 : 0.4)
              }
            }
          }

          if model.lastPurchaseSuccess {
            HStack(spacing: 8) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
              Text("Thank you for your support!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .transition(.scale.combined(with: .opacity))
          }
        }
      } header: {
        Text("Sponsor")
          .padding(.horizontal)
      } footer: {
        if model.isSandbox {
          Group {
            Text("TestFlight Notice: ").foregroundStyle(.red).bold()
              + Text(
                "These are test purchases only. Want to support development? Download from the App Store to leave a real tip. [Open App Store](https://apps.apple.com/us/app/id6753017503)"
              )
          }
          .font(.footnote)
        }
      }
      .dynamicTypeSize(...DynamicTypeSize.accessibility1)
      .animation(.easeInOut(duration: 0.3), value: model.lastPurchaseSuccess)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
  }
}

extension TipJarView {
  @Observable
  class Model: ObservableObject {
    struct Tip: Identifiable {
      let id: String
      let title: String
      let description: String
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
        description: "A small way to say thanks!",
        price: "$2.99"
      ),
      Tip(
        id: "lunch",
        title: "Buy Me Lunch 🍕",
        description: "Your support means a lot!",
        price: "$4.99"
      ),
      Tip(
        id: "dinner",
        title: "Buy Me Dinner 🍱",
        description: "You're amazing! Thank you!",
        price: "$9.99"
      ),
    ]
  )
}

#Preview("TipJar") {
  TipJarView(model: .mock)
    .padding()
}
