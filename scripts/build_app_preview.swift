#!/usr/bin/swift

import AVFoundation
import AppKit
import CoreImage

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let slidesDir = root.appendingPathComponent("marketing/app-store/final", isDirectory: true)
let outputURL = root.appendingPathComponent("marketing/app-store/preview/payguard-app-preview.mp4")

let fileManager = FileManager.default
try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let slides = try fileManager.contentsOfDirectory(at: slidesDir, includingPropertiesForKeys: nil)
    .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !slides.isEmpty else {
    fputs("No final slides found in marketing/app-store/final\n", stderr)
    exit(1)
}

let renderSize = CGSize(width: 886, height: 1920)
let fps: Int32 = 30
let secondsPerSlide = 3.0
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: Int(renderSize.width),
    AVVideoHeightKey: Int(renderSize.height),
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 11_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
    ]
]

let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: Int(renderSize.width),
        kCVPixelBufferHeightKey as String: Int(renderSize.height),
    ]
)

guard writer.canAdd(input) else {
    fputs("Cannot add writer input\n", stderr)
    exit(1)
}

writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let ciContext = CIContext()

func makePixelBuffer(from image: NSImage) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    guard let pool = adaptor.pixelBufferPool else { return nil }
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
    guard let pixelBuffer, let tiff = image.tiffRepresentation, let ciImage = CIImage(data: tiff) else { return nil }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    ciContext.render(ciImage, to: pixelBuffer)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    return pixelBuffer
}

func renderedImage(url: URL, progress: Double) -> NSImage? {
    guard let base = NSImage(contentsOf: url) else { return nil }
    let image = NSImage(size: renderSize)
    image.lockFocus()

    NSColor.black.setFill()
    NSRect(origin: .zero, size: renderSize).fill()

    let zoom = 1.0 + (0.035 * progress)
    let drawWidth = renderSize.width * CGFloat(zoom)
    let drawHeight = renderSize.height * CGFloat(zoom)
    let rect = CGRect(
        x: (renderSize.width - drawWidth) / 2,
        y: (renderSize.height - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    )

    base.draw(in: rect)
    image.unlockFocus()
    return image
}

let framesPerSlide = Int(secondsPerSlide * Double(fps))
var frameCount: Int64 = 0

for slide in slides {
    for frame in 0..<framesPerSlide {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.02)
        }

        let progress = Double(frame) / Double(max(framesPerSlide - 1, 1))
        guard let nsImage = renderedImage(url: slide, progress: progress),
              let buffer = makePixelBuffer(from: nsImage) else {
            continue
        }

        let time = CMTime(value: frameCount, timescale: fps)
        adaptor.append(buffer, withPresentationTime: time)
        frameCount += 1
    }
}

input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting {
    if writer.status == .completed {
        print(outputURL.path)
    } else {
        fputs("Video export failed: \(writer.error?.localizedDescription ?? "Unknown error")\n", stderr)
    }
    semaphore.signal()
}
semaphore.wait()
