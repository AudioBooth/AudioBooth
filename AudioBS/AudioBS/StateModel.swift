import Combine
import SwiftUI

@propertyWrapper
struct StateModel<T: ObservableObject>: DynamicProperty {
  @StateObject private var model: T

  init(wrappedValue: T) {
    self._model = StateObject(wrappedValue: wrappedValue)
  }

  init(mock: T, default: T) {
    let resolvedModel: T

    #if DEBUG
      if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
        resolvedModel = mock
      } else {
        resolvedModel = `default`
      }
    #else
      resolvedModel = `default`
    #endif

    self._model = StateObject(wrappedValue: resolvedModel)
  }

  var wrappedValue: T {
    model
  }

  var projectedValue: Binding<T> {
    Binding(
      get: { model },
      set: { _ in }
    )
  }
}
