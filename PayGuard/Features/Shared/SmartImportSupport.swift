//
//  SmartImportSupport.swift
//  PayGuard
//
//  Created by Ali Ozkul on 02.05.26.
//

import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision
import VisionKit

struct SmartImportPayload: Identifiable {
    let id = UUID()
    let text: String
    let sourceName: String
    let attachment: AttachmentRecord?

    init(text: String, sourceName: String, attachment: AttachmentRecord? = nil) {
        self.text = text
        self.sourceName = sourceName
        self.attachment = attachment
    }
}

struct SmartImportSourceSheet: View {
    @Environment(PremiumAccessController.self) private var premiumAccess

    let title: String
    let detail: String
    let onImported: (SmartImportPayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingFileImporter = false
    @State private var showingScanner = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var importErrorMessage: String?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                SectionTitleView(
                    eyebrow: "Smart Import",
                    title: title,
                    detail: detail
                )

                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        importChip(title: "Photo", systemName: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    Button {
                        showingFileImporter = true
                    } label: {
                        importChip(title: "File", systemName: "doc.text.viewfinder")
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    Button {
                        guard VNDocumentCameraViewController.isSupported else {
                            importErrorMessage = PMLocalized("Document scanning is not available on this device.")
                            return
                        }
                        showingScanner = true
                    } label: {
                        importChip(title: "Scan", systemName: "doc.viewfinder")
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }

                PayGuardPanel(
                    title: "What it can detect",
                    symbol: "sparkles.rectangle.stack.fill",
                    detail: "This import stays on-device and tries to pull out names, dates, prices, billing cycle clues, and seller lines from screenshots, receipts, saved email text files, and scans."
                ) {
                    Text("Best results come from clean screenshots, App Store subscription pages, emailed receipts saved as PDFs, copied email text files, or store receipts with a visible total.")
                        .font(PayGuardTheme.captionFont)
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }

                if isProcessing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the document on-device...")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(PayGuardTheme.surfaceSecondary)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(PayGuardTheme.stroke, lineWidth: 1)
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(PayGuardBackdrop())
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .payGuardNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarCircleIcon(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image, .pdf, .plainText, .text, .html]
        ) { result in
            guard case .success(let url) = result else { return }
            processFile(url)
        }
        .onChange(of: photoPickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await processPhoto(newValue)
            }
        }
        .sheet(isPresented: $showingScanner) {
            SmartImportScannerSheet(
                onScanned: { images in
                    Task {
                        await processImages(images, sourceName: PMLocalized("Scanned document"))
                    }
                },
                onFailed: {
                    importErrorMessage = $0
                }
            )
        }
        .alert("Import Error", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "The selected file could not be read.")
        }
    }

    private func importChip(title: String, systemName: String) -> some View {
        Label(title.localizedKey, systemImage: systemName)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(PayGuardTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PayGuardTheme.surfaceSecondary)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PayGuardTheme.stroke, lineWidth: 1)
            }
    }

    private func processFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        Task {
            await MainActor.run {
                isProcessing = true
            }
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
                Task { @MainActor in
                    isProcessing = false
                }
            }

            do {
                var payload = try await SmartImportOCRService.payload(from: url)
                let attachment = try AttachmentService.shared.importFile(from: url)
                payload = SmartImportPayload(
                    text: payload.text,
                    sourceName: payload.sourceName,
                    attachment: attachment
                )
                await MainActor.run {
                    premiumAccess.registerDocumentScanIfNeeded()
                    onImported(payload)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = PMLocalized("The selected file could not be read.")
                }
            }
        }
    }

    private func processPhoto(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isProcessing = true
        }
        defer {
            Task { @MainActor in
                isProcessing = false
                photoPickerItem = nil
            }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw SmartImportError.unreadable
            }
            var payload = try await SmartImportOCRService.payload(fromImageData: data, sourceName: PMLocalized("Imported photo"))
            let attachment = try AttachmentService.shared.importData(
                data,
                preferredName: "SmartImport-\(UUID().uuidString).jpg"
            )
            payload = SmartImportPayload(
                text: payload.text,
                sourceName: payload.sourceName,
                attachment: attachment
            )
            await MainActor.run {
                premiumAccess.registerDocumentScanIfNeeded()
                onImported(payload)
                dismiss()
            }
        } catch {
            await MainActor.run {
                importErrorMessage = PMLocalized("The selected photo could not be read.")
            }
        }
    }

    private func processImages(_ images: [UIImage], sourceName: String) async {
        await MainActor.run {
            isProcessing = true
        }
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        do {
            var payload = try await SmartImportOCRService.payload(from: images, sourceName: sourceName)
            guard let scanData = smartImportPDFData(from: images) else {
                throw SmartImportError.unreadable
            }
            let attachment = try AttachmentService.shared.importData(
                scanData,
                preferredName: "SmartImport-Scan-\(UUID().uuidString).pdf"
            )
            payload = SmartImportPayload(
                text: payload.text,
                sourceName: payload.sourceName,
                attachment: attachment
            )
            await MainActor.run {
                premiumAccess.registerDocumentScanIfNeeded()
                onImported(payload)
                dismiss()
            }
        } catch {
            await MainActor.run {
                importErrorMessage = PMLocalized("The scanned document could not be read.")
            }
        }
    }
}

private func smartImportPDFData(from images: [UIImage]) -> Data? {
    guard !images.isEmpty else { return nil }
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
    return renderer.pdfData { context in
        for image in images {
            context.beginPage()
            let pageBounds = context.pdfContextBounds
            let fittedRect = smartImportAspectFitRect(
                aspectRatio: image.size,
                inside: pageBounds.insetBy(dx: 24, dy: 24)
            )
            image.draw(in: fittedRect)
        }
    }
}

private func smartImportAspectFitRect(aspectRatio: CGSize, inside boundingRect: CGRect) -> CGRect {
    let scale = min(boundingRect.width / aspectRatio.width, boundingRect.height / aspectRatio.height)
    let size = CGSize(width: aspectRatio.width * scale, height: aspectRatio.height * scale)
    let origin = CGPoint(
        x: boundingRect.midX - size.width / 2,
        y: boundingRect.midY - size.height / 2
    )
    return CGRect(origin: origin, size: size)
}

private enum SmartImportError: Error {
    case unreadable
}

private enum SmartImportOCRService {
    static func payload(from url: URL) async throws -> SmartImportPayload {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "pdf" {
            let text = try await extractTextFromPDF(url)
            return SmartImportPayload(text: text, sourceName: url.lastPathComponent)
        }

        if ["txt", "text", "eml", "html", "htm"].contains(fileExtension),
           let text = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return SmartImportPayload(text: text, sourceName: url.lastPathComponent)
        }

        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           !looksLikeBinaryImageData(data) {
            return SmartImportPayload(text: text, sourceName: url.lastPathComponent)
        }

        return try await payload(fromImageData: data, sourceName: url.lastPathComponent)
    }

    private static func looksLikeBinaryImageData(_ data: Data) -> Bool {
        let prefix = Array(data.prefix(8))
        return prefix.starts(with: [0xFF, 0xD8])
            || prefix.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || prefix.starts(with: [0x47, 0x49, 0x46])
            || prefix.starts(with: [0x25, 0x50, 0x44, 0x46])
    }

    static func payload(fromImageData data: Data, sourceName: String) async throws -> SmartImportPayload {
        guard let image = UIImage(data: data) else {
            throw SmartImportError.unreadable
        }
        let text = try await extractText(from: image)
        return SmartImportPayload(text: text, sourceName: sourceName)
    }

    static func payload(from images: [UIImage], sourceName: String) async throws -> SmartImportPayload {
        let parts = try await withThrowingTaskGroup(of: String.self) { group in
            for image in images {
                group.addTask {
                    try await extractText(from: image)
                }
            }

            var values: [String] = []
            for try await text in group {
                values.append(text)
            }
            return values
        }

        let combined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !combined.isEmpty else {
            throw SmartImportError.unreadable
        }

        return SmartImportPayload(text: combined, sourceName: sourceName)
    }

    private static func extractTextFromPDF(_ url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw SmartImportError.unreadable
        }

        let nativeText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !nativeText.isEmpty {
            return nativeText
        }

        let images = (0..<min(document.pageCount, 3)).compactMap { index -> UIImage? in
            guard let page = document.page(at: index) else { return nil }
            return page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
        }

        let payload = try await payload(from: images, sourceName: url.lastPathComponent)
        return payload.text
    }

    private static func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw SmartImportError.unreadable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if text.isEmpty {
                    continuation.resume(throwing: SmartImportError.unreadable)
                } else {
                    continuation.resume(returning: text)
                }
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private struct SmartImportScannerSheet: UIViewControllerRepresentable {
    let onScanned: ([UIImage]) -> Void
    let onFailed: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onFailed: onFailed)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanned: ([UIImage]) -> Void
        let onFailed: (String) -> Void

        init(onScanned: @escaping ([UIImage]) -> Void, onFailed: @escaping (String) -> Void) {
            self.onScanned = onScanned
            self.onFailed = onFailed
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map(scan.imageOfPage(at:))
            controller.dismiss(animated: true)
            onScanned(images)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onFailed(PMLocalized("PayGuard could not open the document scanner. Check camera access and try again."))
            controller.dismiss(animated: true)
        }
    }
}
