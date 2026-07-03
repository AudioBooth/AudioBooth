import Foundation
import Logging
import RevenueCat
import SwiftUI

final class TipJarViewModel: TipJarView.Model {
  private var packages: [Package] = []

  init() {
    super.init(isSandbox: [.debug, .testFlight].contains(UIApplication.buildType))

    loadOfferings()
    loadSubscriptionStatus()
  }

  override func onTipSelected(_ tip: Tip) {
    guard let package = packages.first(where: { $0.identifier == tip.id }) else {
      return
    }
    purchaseTip(package)
  }

  private func loadSubscriptionStatus() {
    Task {
      do {
        let customerInfo = try await Purchases.shared.customerInfo()
        hasActiveSubscription = !customerInfo.activeSubscriptions.isEmpty
      } catch {
        AppLogger.viewModel.error(
          "Failed to fetch customer info: \(error.localizedDescription)"
        )
      }
    }
  }

  private func loadOfferings() {
    Task {
      do {
        let offerings = try await Purchases.shared.offerings()

        guard let currentOffering = offerings.current else {
          AppLogger.viewModel.warning("No current offering available")
          return
        }

        packages = currentOffering.availablePackages.sorted { lhs, rhs in
          return lhs.storeProduct.price < rhs.storeProduct.price
        }

        tips = packages.map { package in
          var title = package.storeProduct.localizedTitle
          let price = package.localizedPriceString

          switch package.identifier {
          case "tip_small":
            title = String(localized: "Coffee")
          case "tip_medium":
            title = String(localized: "Lunch")
          case "tip_large":
            title = String(localized: "Dinner")
          default:
            break
          }

          return Tip(
            id: package.identifier,
            title: title,
            price: price
          )
        }
      } catch {
        AppLogger.viewModel.error(
          "Failed to fetch offerings: \(error.localizedDescription)"
        )
      }
    }
  }

  private func purchaseTip(_ package: Package) {
    isPurchasing = package.identifier
    lastPurchaseSuccess = false

    Task {
      do {
        let result = try await Purchases.shared.purchase(package: package)

        if !result.userCancelled {
          lastPurchaseSuccess = true
          hasActiveSubscription = !result.customerInfo.activeSubscriptions.isEmpty

          Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            lastPurchaseSuccess = false
          }
        }
      } catch {
        AppLogger.viewModel.error(
          "Failed to purchase tip: \(error.localizedDescription)"
        )
      }

      isPurchasing = nil
    }
  }
}
