import Foundation
import UniformTypeIdentifiers

public enum Device {
  public static let identifier: String = {
    #if targetEnvironment(simulator)
    if let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
      return identifier
    }
    #endif

    #if targetEnvironment(macCatalyst)
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var bytes = [UInt8](repeating: 0, count: size)
    sysctlbyname("hw.model", &bytes, &size, nil, 0)
    return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    #else
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafeBytes(of: &systemInfo.machine) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    #endif
  }()

  public static let model: String = {
    guard
      let type = UTType(
        tag: identifier,
        tagClass: UTTagClass(rawValue: "com.apple.device-model-code"),
        conformingTo: nil
      ),
      !type.isDynamic,
      let name = type.localizedDescription
    else { return identifier }

    return name
  }()
}
