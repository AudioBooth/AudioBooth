import Foundation

extension URL {
  nonisolated var directorySize: Int64 {
    guard
      let enumerator = FileManager.default.enumerator(
        at: self,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else { return 0 }

    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
      size += Int64(values?.fileSize ?? 0)
    }
    return size
  }
}
