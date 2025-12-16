import Combine
import CoreImage
import SwiftUI

struct ConnectionSharingPage: View {
  @ObservedObject var model: Model

  var body: some View {
    VStack(spacing: 20) {
      Text("Share this QR code or link with another AudioBooth user to help them connect to your server")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if let qrCode = model.qrCodeImage {
        Image(uiImage: qrCode)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .frame(width: 250, height: 250)
          .padding()
      } else {
        ProgressView()
      }

      VStack(alignment: .leading, spacing: 16) {
        Toggle("Include Credentials", isOn: $model.includeCredentials)
          .font(.subheadline)
          .bold()
          .onChange(of: model.includeCredentials) { _, newValue in
            model.onIncludeCredentialsChanged(newValue)
          }

        if model.includeCredentials {
          HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)

            Text(
              "Sharing credentials will invalidate them on this device once another device uses them. You will need to reconnect to continue using this connection."
            )
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
          }
          .font(.footnote)
          .padding(12)
          .background(.orange.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }

      Spacer()

      VStack(spacing: 12) {
        Button(action: model.onShareTapped) {
          Label("Share Link", systemImage: "square.and.arrow.up")
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.connectionURL == nil)

        Button(action: model.onShareQRCodeTapped) {
          Label("Share QR Code", systemImage: "qrcode")
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(model.qrCodeImage == nil)
      }
    }
    .padding()
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: model.onAppear)
  }
}

extension ConnectionSharingPage {
  @Observable
  class Model: ObservableObject {
    var qrCodeImage: UIImage?
    var connectionURL: URL?
    var includeCredentials: Bool

    func onAppear() {}
    func onShareTapped() {}
    func onShareQRCodeTapped() {}
    func onIncludeCredentialsChanged(_ newValue: Bool) {}

    init(
      qrCodeImage: UIImage? = nil,
      connectionURL: URL? = nil,
      includeCredentials: Bool = false
    ) {
      self.qrCodeImage = qrCodeImage
      self.connectionURL = connectionURL
      self.includeCredentials = includeCredentials
    }
  }
}

extension ConnectionSharingPage.Model {
  static var mock = ConnectionSharingPage.Model()
}

#Preview {
  let context = CIContext()
  let filter = CIFilter.qrCodeGenerator()
  filter.message = Data("audiobooth://connection?data=test".utf8)
  filter.correctionLevel = "L"

  let outputImage = filter.outputImage!
  let transform = CGAffineTransform(scaleX: 10, y: 10)
  let scaledImage = outputImage.transformed(by: transform)
  let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent)!
  let qrCode = UIImage(cgImage: cgImage)

  return NavigationStack {
    ConnectionSharingPage(
      model: .init(
        qrCodeImage: qrCode,
        connectionURL: URL(string: "audiobooth://connection?data=test")
      )
    )
  }
}
