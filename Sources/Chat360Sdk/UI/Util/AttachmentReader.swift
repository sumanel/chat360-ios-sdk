import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AttachmentPayload {
    var bytes: Data
    var fileName: String
    var mimeType: String
}

/// Matches the widget's 10MB cap.
let maxAttachmentBytes = 10_000_000

enum AttachmentReader {
    static func read(from url: URL) -> AttachmentPayload? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= maxAttachmentBytes else { return nil }
        return AttachmentPayload(bytes: data, fileName: url.lastPathComponent, mimeType: mimeType(for: url))
    }

    private static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

/// Opens the system document picker for any file type (the closest iOS equivalent of Android's
/// `GetContent("*/*")` - it also surfaces Photos via the Files app's own integration).
struct AttachmentDocumentPicker: UIViewControllerRepresentable {
    var onPicked: (AttachmentPayload) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (AttachmentPayload) -> Void
        init(onPicked: @escaping (AttachmentPayload) -> Void) { self.onPicked = onPicked }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first, let payload = AttachmentReader.read(from: url) else { return }
            onPicked(payload)
        }
    }
}

/// Ports the FILE_UPLOAD node's `enableCameraInput` option via the platform's own Camera app
/// instead of a custom live-preview UI, the same way the Android side defers to the system Camera
/// activity rather than reimplementing a getUserMedia-style preview screen.
struct AttachmentCameraCapture: UIViewControllerRepresentable {
    var onPicked: (AttachmentPayload) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (AttachmentPayload) -> Void
        init(onPicked: @escaping (AttachmentPayload) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) else { return }
            let fileName = "chat360_camera_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
            onPicked(AttachmentPayload(bytes: data, fileName: fileName, mimeType: "image/jpeg"))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
