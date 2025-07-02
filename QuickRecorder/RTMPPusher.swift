//
//  RTMPPusher.swift
//  QuickRecorder
//
//  Created by kyr0 on 30.06.25.
//

import AVFoundation
import HaishinKit
import SRTHaishinKit

/// OLD IMPLEMENTATION IDEA. CURRENTLY UNUSED (!!)

/// Encapsulates HaishinKit's async RTMP connect/publish and sample-buffer appending.
final class RTMPPusher {
    
    static var connection: RTMPConnection!
    static var stream: RTMPStream!
    static var endpoint: String!
    static var streamKey: String!
    static var response: RTMPResponse!
    static var mixer: MediaMixer!
    
    // TODO: might need to render to surface as a stream and then read from it as stream?
    // https://github.com/HaishinKit/HaishinKit.swift/blob/346e1c73f09a7c3984df9ca16ed534b7f9bf32e6/HaishinKit/Sources/View/MTHKView.swift#L7

    // TODO: or: https://stackoverflow.com/questions/68633820/how-to-live-a-live-application-screen-having-camera-view-with-some-other-uiviews
    
    /// Initialize with full RTMP endpoint (incl. key), e.g. "rtmp://.../live2/streamKey".
    init(endpoint: String, name: String, streamKey: String) {
        RTMPPusher.endpoint = endpoint
        RTMPPusher.streamKey = streamKey
        RTMPPusher.mixer = MediaMixer()
        
        RTMPPusher.connection = RTMPConnection()
        RTMPPusher.stream = RTMPStream(connection: RTMPPusher.connection, fcPublishName: name)
        
    }
    /// Append a CMSampleBuffer to the stream (audio or video).
    func append(_ sb: CMSampleBuffer) {
        Task {
            await RTMPPusher.stream.append(sb)
        }
    }
    
    func publish() async throws {
        // Async connect & publish
        Task {
            do {
                await RTMPPusher.mixer.addOutput(RTMPPusher.stream)
                
                RTMPPusher.response = try await RTMPPusher.connection.connect(RTMPPusher.endpoint)
                RTMPPusher.response = try await RTMPPusher.stream.publish(RTMPPusher.streamKey)
                
            } catch {
                print("RTMP connect/publish error: \(error)")
            }
        }
    }

    /// Close stream and connection cleanly.
    func close() {
        Task {
            do {
                RTMPPusher.response = try await RTMPPusher.stream.close()
                try await RTMPPusher.connection.close()
            } catch {
                print("RTMP close error: \(error)")
            }
        }
    }
}
