import CarPlay
import Foundation

protocol CarPlayPageProtocol: AnyObject {
  var template: CPListTemplate { get }
  func willAppear()
}
