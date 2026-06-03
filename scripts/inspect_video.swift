#!/usr/bin/swift

import AVFoundation
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: inspect_video.swift <path>\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)

guard let track = asset.tracks(withMediaType: .video).first else {
    fputs("No video track found\n", stderr)
    exit(1)
}

let size = track.naturalSize.applying(track.preferredTransform)
let width = Int(abs(size.width))
let height = Int(abs(size.height))
let duration = CMTimeGetSeconds(asset.duration)

print("width=\(width)")
print("height=\(height)")
print("duration=\(duration)")
