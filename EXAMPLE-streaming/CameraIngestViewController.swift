import AVFoundation
import Cocoa
import HaishinKit
import VideoToolbox
import SRTHaishinKit

@available(macOS 14, *)
extension NSPopUpButton {
    fileprivate func present(mediaType: AVMediaType) {
        
        // --- choose which kinds of hardware you care about ---
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,   // built-in FaceTime / iSight
            .continuityCamera,
            .deskViewCamera,
            .external,
            .microphone,
        ]

        // --- discovery session replaces the deprecated `devices(for:)` ---
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: mediaType,          // .video or .audio
            position: .unspecified         // front / back if you want to filter
        )

        // --- populate your UI just as before ---
        for device in discovery.devices {
            addItem(withTitle: device.localizedName)
        }
    }
}

@available(macOS 14, *)
final class CameraIngestViewController: NSViewController {
    @IBOutlet private weak var lfView: MTHKView!
    @IBOutlet private weak var audioPopUpButton: NSPopUpButton!
    @IBOutlet private weak var cameraPopUpButton: NSPopUpButton!
    @IBOutlet private weak var urlField: NSTextField!
    private var session: (any Session)?
    private var mixer = MediaMixer()

    @ScreenActor
    private var textScreenObject = TextScreenObject()

    override func viewDidLoad() {
        super.viewDidLoad()
        urlField.stringValue = Preference.default.uri ?? ""
        audioPopUpButton?.present(mediaType: .audio)
        cameraPopUpButton?.present(mediaType: .video)

        Task {
            var videoMixerSettings = await mixer.videoMixerSettings
            videoMixerSettings.mode = .offscreen
            await mixer.setVideoMixerSettings(videoMixerSettings)
            session = await SessionBuilderFactory.shared.make(Preference.default.makeURL())?.build()
            
            guard let session else {
                return
            }
            await session.stream.addOutput(lfView!)
            await mixer.addOutput(session.stream)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        Task { @ScreenActor in
            let videoScreenObject = VideoTrackScreenObject()
            videoScreenObject.cornerRadius = 32.0
            videoScreenObject.track = 1
            videoScreenObject.horizontalAlignment = .right
            videoScreenObject.layoutMargin = .init(top: 16, left: 0, bottom: 0, right: 16)
            videoScreenObject.size = .init(width: 160 * 2, height: 90 * 2)
            _ = videoScreenObject.registerVideoEffect(MonochromeEffect())

            let imageScreenObject = ImageScreenObject()
            let imageURL = URL(fileURLWithPath: Bundle.main.path(forResource: "game_jikkyou", ofType: "png") ?? "")
            if let provider = CGDataProvider(url: imageURL as CFURL) {
                imageScreenObject.verticalAlignment = .bottom
                imageScreenObject.layoutMargin = .init(top: 0, left: 0, bottom: 16, right: 0)
                imageScreenObject.cgImage = CGImage(
                    pngDataProviderSource: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                )
            } else {
                logger.info("no image")
            }

            let assetScreenObject = AssetScreenObject()
            assetScreenObject.size = .init(width: 180, height: 180)
            assetScreenObject.layoutMargin = .init(top: 16, left: 16, bottom: 0, right: 0)
            try? assetScreenObject.startReading(AVURLAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "SampleVideo_360x240_5mb", ofType: "mp4") ?? "")))

            try? await mixer.screen.addChild(assetScreenObject)
            try? await mixer.screen.addChild(videoScreenObject)
            try? await mixer.screen.addChild(imageScreenObject)
            try? await mixer.screen.addChild(textScreenObject)
        }

        Task {
            try? await mixer.attachAudio(DeviceUtil.device(withLocalizedName: audioPopUpButton.titleOfSelectedItem!, mediaType: .audio))

            // ---------- AUDIO ----------
               let audioDiscovery = AVCaptureDevice.DiscoverySession(
                   deviceTypes: [.microphone],          // all mics (built-in + USB)
                   mediaType: .audio,
                   position: .unspecified)

               var microphones = audioDiscovery.devices
               if !microphones.isEmpty { microphones.removeFirst() }   // skip primary mic

               if let mic2 = microphones.first,
                  await mixer.isMultiTrackAudioMixingEnabled {
                   try? await mixer.attachAudio(mic2, track: 1)
               }

               // ---------- PRIMARY VIDEO (selected from UI) ----------
               if let primaryCam =
                   DeviceUtil.device(withLocalizedName: cameraPopUpButton.titleOfSelectedItem!,
                                     mediaType: .video) {
                   try? await mixer.attachVideo(primaryCam, track: 0)
               }

               // ---------- SECONDARY VIDEO ----------
               var videoTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]

                videoTypes += [.external, .continuityCamera, .deskViewCamera]

               let videoDiscovery = AVCaptureDevice.DiscoverySession(
                   deviceTypes: videoTypes,
                   mediaType: .video,
                   position: .unspecified)

               var cameras = videoDiscovery.devices
               if !cameras.isEmpty { cameras.removeFirst() }           // skip primary cam

               if let cam2 = cameras.first {
                   try? await mixer.attachVideo(cam2, track: 1)
               }
            
            /*
                // ------- SCREEN CAPTURE -------
            if let screenInput = AVCaptureScreenInput(displayID: CGMainDisplayID()) {
                screenInput.minFrameDuration = CMTime(value: 1, timescale: 30)   // 30 fps
                screenInput.capturesCursor      = true                          // optional
                screenInput.capturesMouseClicks = true                          // optional
                try? await mixer.attachScreen(screenInput, track: 2)            // NEW
            }
            
            var v = await mixer.videoMixerSettings
            v.mainTrack = 2          // screen becomes the base layer
            await mixer.setVideoMixerSettings(v)
             */
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
                try? await session?.close()
            }
        }
    }

    @IBAction private func orientation(_ sender: AnyObject) {
        lfView.rotate(byDegrees: 90)
    }

    @IBAction private func mirror(_ sender: AnyObject) {
        Task {
            try await mixer.configuration(video: 0) { unit in
                unit.isVideoMirrored.toggle()
            }
        }
    }

    @IBAction private func selectAudio(_ sender: AnyObject) {
        Task {
            let device = DeviceUtil.device(withLocalizedName: audioPopUpButton.titleOfSelectedItem!, mediaType: .audio)
            try? await mixer.attachAudio(device)
        }
    }

    @IBAction private func selectCamera(_ sender: AnyObject) {
        Task {
            let device = DeviceUtil.device(withLocalizedName: cameraPopUpButton.titleOfSelectedItem!, mediaType: .video)
            try? await mixer.attachVideo(device, track: 0)
        }
    }
}

@available(macOS 14, *)
extension CameraIngestViewController: ScreenDelegate {
    nonisolated func screen(_ screen: Screen, willLayout time: CMTime) {
        Task { @ScreenActor in
            textScreenObject.string = Date().description
        }
    }
}
