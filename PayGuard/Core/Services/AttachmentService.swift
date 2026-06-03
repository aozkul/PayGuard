//
//  AttachmentService.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation

final class AttachmentService {
    static let shared = AttachmentService()

    private init() {}

    private var baseDirectoryURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = root.appendingPathComponent("Attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appFolder.path()) {
            try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }
        return appFolder
    }

    func importFile(from sourceURL: URL) throws -> AttachmentRecord {
        let sanitizedFileName = sourceURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let uniqueName = "\(UUID().uuidString)-\(sanitizedFileName)"
        let destination = baseDirectoryURL.appendingPathComponent(uniqueName)

        if FileManager.default.fileExists(atPath: destination.path()) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        return AttachmentRecord(
            fileName: sourceURL.lastPathComponent,
            fileType: sourceURL.pathExtension.uppercased(),
            relativePath: uniqueName
        )
    }

    func importData(_ data: Data, preferredName: String) throws -> AttachmentRecord {
        let uniqueName = "\(UUID().uuidString)-\(preferredName.replacingOccurrences(of: " ", with: "_"))"
        let destination = baseDirectoryURL.appendingPathComponent(uniqueName)
        try data.write(to: destination, options: .atomic)
        return AttachmentRecord(
            fileName: preferredName,
            fileType: destination.pathExtension.uppercased(),
            relativePath: uniqueName
        )
    }

    func delete(_ attachment: AttachmentRecord) {
        let url = url(for: attachment)
        try? FileManager.default.removeItem(at: url)
    }

    func url(for attachment: AttachmentRecord) -> URL {
        baseDirectoryURL.appendingPathComponent(attachment.relativePath)
    }
}
