#!/usr/bin/swift

import AVFoundation
import Foundation

guard CommandLine.arguments.count > 2 else {
    fputs("Usage: scale_app_preview.swift <input> <output>\n", stderr)
    exit(1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

let asset = AVURLAsset(url: inputURL)
guard let sourceTrack = asset.tracks(withMediaType: .video).first else {
    fputs("No video track found in input\n", stderr)
    exit(1)
}

let composition = AVMutableComposition()
guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
    fputs("Unable to create composition track\n", stderr)
    exit(1)
}

try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: sourceTrack, at: .zero)

let renderSize = CGSize(width: 886, height: 1920)
let naturalSize = sourceTrack.naturalSize.applying(sourceTrack.preferredTransform)
let sourceWidth = abs(naturalSize.width)
let sourceHeight = abs(naturalSize.height)
let scale = renderSize.width / sourceWidth

let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
let transform = sourceTrack.preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

let scaledHeight = sourceHeight * scale
let verticalInset = (renderSize.height - scaledHeight) / 2
let centeredTransform = transform.concatenating(CGAffineTransform(translationX: 0, y: verticalInset))
layerInstruction.setTransform(centeredTransform, at: .zero)

instruction.layerInstructions = [layerInstruction]

let videoComposition = AVMutableVideoComposition()
videoComposition.renderSize = renderSize
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
videoComposition.instructions = [instruction]

try? FileManager.default.removeItem(at: outputURL)

guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
    fputs("Unable to create export session\n", stderr)
    exit(1)
}

exportSession.outputURL = outputURL
exportSession.outputFileType = .mp4
exportSession.shouldOptimizeForNetworkUse = true
exportSession.videoComposition = videoComposition

let semaphore = DispatchSemaphore(value: 0)
exportSession.exportAsynchronously {
    semaphore.signal()
}
semaphore.wait()

if exportSession.status == .completed {
    print(outputURL.path)
} else {
    fputs("Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")\n", stderr)
    exit(1)
}
