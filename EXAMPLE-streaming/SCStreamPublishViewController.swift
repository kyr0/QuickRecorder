import AppKit
import Foundation
import HaishinKit
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

class SCStreamPublishViewController: NSViewController {
    @IBOutlet private weak var cameraPopUpButton: NSPopUpButton!
    @IBOutlet private weak var urlField: NSTextField!
    @IBOutlet private weak var mthkView: MTHKView!
    private var session: (any Session)?
    private let lockQueue = DispatchQueue(label: "SCStreamPublishViewController.lock")
    private var _scstream: Any?

    @available(macOS 12.3, *)
    private var scstream: SCStream? {
        get {
            _scstream as? SCStream
        }
        set {
            _scstream = newValue
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        urlField.stringValue = Preference.default.uri ?? ""
        Task {
            session = await SessionBuilderFactory.shared.make(Preference.default.makeURL())?.build()
            guard let session else {
                return
            }
            await session.stream.addOutput(mthkView!)
            try await SCShareableContent.current.windows.forEach {
                cameraPopUpButton.addItem(withTitle: $0.owningApplication?.applicationName ?? "")
            }
        }
    }

    @IBAction private func publishOrStop(_ sender: NSButton) {
        Task {
            // Publish
            if sender.title == "Publish" {
                sender.title = "Stop"
                try? await session?.connect(.ingest)
            } else {
                // Stop
                sender.title = "Publish"
                try? await session?.connect(.ingest)
            }
        }
    }
    
    @IBAction private func selectCamera(_ sender: AnyObject) {
        if #available(macOS 12.3, *) {
         
            if  CGPreflightScreenCaptureAccess() ||
                CGRequestScreenCaptureAccess() {
              
                Task { @MainActor in
                    // 2. Safe to touch ScreenCaptureKit now
                    let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                      onScreenWindowsOnly: false)
                    guard let display0 = content.displays.first else { return }

                    let finder = content.applications.first { $0.bundleIdentifier == "com.apple.finder" }
                    let filter = SCContentFilter(display: display0,
                                                 excludingApplications: finder.map { [$0] } ?? [],
                                                 exceptingWindows: [])
                    let cfg = SCStreamConfiguration()
                    cfg.width  = Int(display0.width)
                    cfg.height = Int(display0.height)
                    cfg.showsCursor = true

                    scstream = SCStream(filter: filter, configuration: cfg, delegate: self)
                    try await scstream?.startCapture()
                }
                // safe to touch SCShareableContent / SCStream here
            }
        }
    }
}

extension SCStreamPublishViewController: SCStreamDelegate {
    // MARK: SCStreamDelegate
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print(error)
    }
}
