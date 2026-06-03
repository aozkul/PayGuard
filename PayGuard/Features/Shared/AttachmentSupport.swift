//
//  AttachmentSupport.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

private struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct AttachmentGalleryView: View {
    @Environment(PremiumAccessController.self) private var premiumAccess

    let attachments: [AttachmentRecord]
    let onImported: (AttachmentRecord) -> Void
    let onDeleted: (AttachmentRecord) -> Void

    @State private var showingFileImporter = false
    @State private var showingScanner = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var previewItem: PreviewItem?
    @State private var importErrorMessage: String?
    @State private var premiumGate: PremiumGate?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attachments")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text("Attach photos, files or scans and tap any item to preview it.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    attachmentActionChip(title: "Photo", systemName: "photo.on.rectangle.angled")
                }
                .buttonStyle(.plain)

                Button {
                    showingFileImporter = true
                } label: {
                    attachmentActionChip(title: "File", systemName: "paperclip")
                }
                .buttonStyle(.plain)

                Button {
                    if !premiumAccess.canUseDocumentScan() {
                        premiumGate = .scanLimit
                    } else if !VNDocumentCameraViewController.isSupported {
                        importErrorMessage = PMLocalized("Document scanning is not available on this device.")
                    } else {
                        showingScanner = true
                    }
                } label: {
                    attachmentActionChip(title: "Scan", systemName: "doc.viewfinder")
                }
                .buttonStyle(.plain)
            }

            if attachments.isEmpty {
                Text("Add receipts, invoices, PDFs or photos for quick access.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            } else {
                ForEach(attachments) { attachment in
                    HStack(spacing: 12) {
                        Button {
                            previewItem = PreviewItem(url: AttachmentService.shared.url(for: attachment))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: iconName(for: attachment))
                                    .font(.title3)
                                    .foregroundStyle(PayGuardTheme.accent)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(PayGuardTheme.surface)
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(attachment.fileName)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(PayGuardTheme.textPrimary)
                                        .lineLimit(1)
                                    Text("\(attachment.fileType) • \(attachment.createdAt.shortRelativeDescription)")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(PayGuardTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(PayGuardTheme.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            onDeleted(attachment)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(PayGuardTheme.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PayGuardTheme.surfaceSecondary)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PayGuardTheme.stroke, lineWidth: 1)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item]
        ) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let imported = try AttachmentService.shared.importFile(from: url)
                onImported(imported)
            } catch {
                importErrorMessage = PMLocalized("The selected file could not be attached.")
            }
        }
        .onChange(of: photoPickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self),
                      let attachment = try? AttachmentService.shared.importData(data, preferredName: "Photo-\(UUID().uuidString).jpg") else {
                    await MainActor.run {
                        importErrorMessage = PMLocalized("The selected photo could not be attached.")
                    }
                    return
                }
                await MainActor.run {
                    onImported(attachment)
                    photoPickerItem = nil
                }
            }
        }
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScannerSheet(
                onScanned: { images in
                    do {
                        guard let data = pdfData(from: images) else {
                            importErrorMessage = PMLocalized("The scan could not be converted into a document.")
                            return
                        }
                        let attachment = try AttachmentService.shared.importData(data, preferredName: "Scan-\(UUID().uuidString).pdf")
                        onImported(attachment)
                        premiumAccess.registerDocumentScanIfNeeded()
                    } catch {
                        importErrorMessage = PMLocalized("The scanned document could not be attached.")
                    }
                },
                onFailed: {
                    importErrorMessage = $0
                }
            )
        }
        .sheet(item: $premiumGate) { gate in
            PremiumUpgradeSheet(gate: gate)
        }
        .alert("Attachment Error", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Something went wrong while importing the attachment.")
        }
    }

    private func iconName(for attachment: AttachmentRecord) -> String {
        switch attachment.fileType.uppercased() {
        case "PDF":
            "doc.richtext"
        case "JPG", "JPEG", "PNG", "HEIC":
            "photo"
        default:
            "doc"
        }
    }

    private func attachmentActionChip(title: String, systemName: String) -> some View {
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

    private func pdfData(from images: [UIImage]) -> Data? {
        guard !images.isEmpty else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for image in images {
                context.beginPage()
                let pageBounds = context.pdfContextBounds
                let fittedRect = aspectFitRect(aspectRatio: image.size, inside: pageBounds.insetBy(dx: 24, dy: 24))
                image.draw(in: fittedRect)
            }
        }
    }
}

private struct DocumentScannerSheet: UIViewControllerRepresentable {
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
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onScanned(pages)
            controller.dismiss(animated: true)
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

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private func aspectFitRect(aspectRatio: CGSize, inside boundingRect: CGRect) -> CGRect {
    let scale = min(boundingRect.width / aspectRatio.width, boundingRect.height / aspectRatio.height)
    let size = CGSize(width: aspectRatio.width * scale, height: aspectRatio.height * scale)
    let origin = CGPoint(
        x: boundingRect.midX - size.width / 2,
        y: boundingRect.midY - size.height / 2
    )
    return CGRect(origin: origin, size: size)
}
