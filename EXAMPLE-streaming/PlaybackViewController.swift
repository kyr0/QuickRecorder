import AppKit
import AVFoundation
import Foundation
import HaishinKit

final class PlaybackViewController: NSViewController {
    @IBOutlet private weak var lfView: MTHKView!
    private var session: (any Session)?
    private let audioPlayer = AudioPlayer(audioEngine: AVAudioEngine())

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            session = await SessionBuilderFactory.shared.make(Preference.default.makeURL())?.build()
            guard let session else {
                return
            }
            await session.stream.attachAudioPlayer(audioPlayer)
            await session.stream.addOutput(lfView)
        }
    }

    @IBAction private func didTappedPlayback(_ button: NSButton) {
        Task { @MainActor in
            if button.title == "Playback" {
                button.title = "Close"
                try? await session?.connect(.playback)
            } else {
                button.title = "Playback"
                try? await session?.close()
            }
        }
    }
}
