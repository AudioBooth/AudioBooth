import Foundation
import KSCrashDemangleFilter
import KSCrashFilters
import KSCrashInstallations
import Logging

final class CrashReporter {
  static let shared = CrashReporter()

  private init() {
    let installation = CrashInstallationStandard.shared
    let config = KSCrashConfiguration()

    config.enableMemoryIntrospection = false
    config.monitors = MonitorType.all.subtracting(.watchdog)

    #if targetEnvironment(simulator)
    config.enableSwapCxaThrow = false
    #endif

    let storeConfig = CrashReportStoreConfiguration()
    storeConfig.maxReportCount = 10
    config.reportStoreConfiguration = storeConfig

    do {
      try installation.install(with: config)

      let reporter = KSCrash.shared

      guard let reportStore = reporter.reportStore else { return }

      reportStore.sink = CrashReportFilterPipeline(filters: [
        CrashReportFilterDemangle(),
        CrashReportFilterAppleFmt(reportStyle: .symbolicated),
      ])

      checkForPreviousCrashes()
    } catch {
      AppLogger.crash.error("Failed to install KSCrash: \(error.localizedDescription)")
    }
  }

  private func checkForPreviousCrashes() {
    guard let reportStore = KSCrash.shared.reportStore, reportStore.reportCount > 0 else { return }

    AppLogger.crash.info("Found \(reportStore.reportCount) crash report(s) from previous session(s)")

    reportStore.sendAllReports { reports, error in
      if let reports {
        for report in reports {
          if let reportString = report as? CrashReportString {
            AppLogger.crash.error("=== CRASH REPORT ===\n\(reportString.value)")
          }
        }
      } else if let error {
        AppLogger.crash.error("Error processing crash reports: \(error.localizedDescription)")
      }
    }
  }
}
