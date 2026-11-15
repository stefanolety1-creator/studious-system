import Foundation

/// Handles Windows Live Messenger Wink (Datacast Type 8) metadata and CAB archives.
public struct WinkPayload: Hashable, Sendable {
    public static let objectType = 8
    public static let appId: UInt32 = 1
    public static let maxCabBytes = 2 * 1024 * 1024 // 2 MB
    public static let maxExpandedBytes = 8 * 1024 * 1024 // 8 MB
    public static let maxPlaybackDuration: TimeInterval = 12.0 // 12 seconds

    public let metadata: MsnObject
    public let name: String

    public init(metadata: MsnObject, name: String = "Wink") {
        precondition(metadata.type == Self.objectType, "Wink MSNObject must have Type 8")
        self.metadata = metadata
        self.name = name
    }

    /// Formats the Switchboard datacast offer body for a Wink.
    public static func makeOfferBody(metadata: MsnObject) -> String {
        "ID: 2\r\nData: \(metadata.toXml())\r\n\r\n"
    }

    /// Parses an incoming Switchboard datacast offer body into a Wink MSNObject.
    public static func parseOffer(body: String) -> MsnObject? {
        guard let dataRange = body.range(of: "Data: ", options: .caseInsensitive) else {
            return nil
        }
        let xmlCandidate = String(body[dataRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let obj = MsnObject.parse(xmlCandidate, expectedType: objectType) else {
            return nil
        }
        guard obj.size >= 36, obj.size <= maxCabBytes else { return nil }
        guard let decodedSha = Data(base64Encoded: obj.sha1d), decodedSha.count == 20 else {
            return nil
        }
        return obj
    }

    /// Checks whether an archive-relative path is safe against directory traversal.
    public static func isSafeArchivePath(_ name: String) -> Bool {
        sanitizeArchivePath(name) != nil
    }

    /// Sanitizes an archive-relative path to guard against directory traversal.
    public static func sanitizeArchivePath(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed.replacingOccurrences(of: "\\", with: "/").lowercased()
        guard cleaned.count <= 240, !cleaned.hasPrefix("/"), !cleaned.contains(":") else {
            return nil
        }
        let segments = cleaned.components(separatedBy: "/")
        if segments.contains("..") || segments.contains(".") || segments.contains("") {
            return nil
        }
        return cleaned
    }
}
