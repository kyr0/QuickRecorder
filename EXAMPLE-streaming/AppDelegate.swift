import Cocoa
import HaishinKit
@preconcurrency import Logboard
import SRTHaishinKit

let logger = LBLogger.with("com.haishinkit.Exsample.macOS")

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Task {
            await SessionBuilderFactory.shared.register(RTMPSessionFactory())
            await SessionBuilderFactory.shared.register(SRTSessionFactory())
        }
        LBLogger.with(kHaishinKitIdentifier).level = .info
    }
}
