import API
import CoreImage.CIFilterBuiltins
import Foundation
import Models
import SwiftUI
import UIKit

final class ConnectionSharingPageViewModel: ConnectionSharingPage.Model {
  private let server: Server

  init(server: Server) {
    self.server = server
    super.init()
  }

  override func onAppear() {
    regenerateConnectionURL()
  }

  override func onIncludeCredentialsChanged(_ newValue: Bool) {
    regenerateConnectionURL()
  }

  private func regenerateConnectionURL() {
    let connection = Connection(server)
    let deepLinkURL = DeepLinkManager.createConnectionDeepLink(
      from: connection,
      includeToken: includeCredentials
    )

    connectionURL = deepLinkURL

    if let url = deepLinkURL {
      qrCodeImage = generateQRCode(from: url.absoluteString)
    }
  }

  override func onShareTapped() {
    guard let connectionURL else { return }

    let activityVC = UIActivityViewController(
      activityItems: [connectionURL],
      applicationActivities: nil
    )

    presentActivityViewController(activityVC)
  }

  override func onShareQRCodeTapped() {
    guard let qrCodeImage else { return }

    let activityVC = UIActivityViewController(
      activityItems: [qrCodeImage],
      applicationActivities: nil
    )

    presentActivityViewController(activityVC)
  }

  private func presentActivityViewController(_ activityVC: UIActivityViewController) {
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootViewController = windowScene.windows.first?.rootViewController
    {
      var topController = rootViewController
      while let presented = topController.presentedViewController {
        topController = presented
      }
      activityVC.popoverPresentationController?.sourceView = topController.view
      topController.present(activityVC, animated: true)
    }
  }

  private func generateQRCode(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()

    filter.message = Data(string.utf8)
    filter.correctionLevel = "L"

    guard let outputImage = filter.outputImage else { return nil }

    let transform = CGAffineTransform(scaleX: 10, y: 10)
    let scaledImage = outputImage.transformed(by: transform)

    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
      return nil
    }

    return UIImage(cgImage: cgImage)
  }
}
