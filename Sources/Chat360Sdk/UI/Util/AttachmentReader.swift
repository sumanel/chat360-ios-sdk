import Foundation
import UniformTypeIdentifiers

public struct AttachmentPayload {
    public let bytes: Data
    public let fileName: String
    public let mimeType: String

    public init(bytes: Data, fileName: String, mimeType: String) {
        self.bytes = bytes
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

public let maxAttachmentBytes = 10_000_000

@available(iOS 14.0, *)
public func readAttachment(url: URL) -> AttachmentPayload? {
    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
    defer { if shouldStopAccessing { url.stopAccessingSecurityScopedResource() } }
    guard let bytes = try? Data(contentsOf: url) else { return nil }
    guard bytes.count <= maxAttachmentBytes else { return nil }
    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    return AttachmentPayload(bytes: bytes, fileName: url.lastPathComponent, mimeType: mimeType)
}
