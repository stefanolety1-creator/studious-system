import Foundation
import CryptoKit

/// Represents an MSNP MSNObject XML envelope used for Display Pictures, Winks, and Voice Clips.
///
/// Format: `<msnobj Creator="..." Size="..." Type="..." Location="..." Friendly="..." SHA1D="..." SHA1C="..."/>`
public struct MsnObject: Hashable, Codable, Sendable {
    public static let userTileType = 3
    public static let winkType = 8
    public static let voiceClipType = 11
    public static let defaultLocation = "TFR2C2.tmp"
    public static let defaultFriendly = "AAA="
    public static let maxDisplayPictureBytes = 199_999 // Strictly < 200,000 bytes

    public let creator: String
    public let size: Int
    public let type: Int
    public let location: String
    public let friendly: String
    public let sha1d: String
    public let sha1c: String?
    public let url: String?
    public let url1: String?
    public let extraAttributes: [String: String]

    public var downloadUrl: String? {
        if let u1 = url1, !u1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return u1
        }
        if let u = url, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return u
        }
        return nil
    }

    public init(
        creator: String,
        size: Int,
        type: Int = userTileType,
        location: String = defaultLocation,
        friendly: String = defaultFriendly,
        sha1d: String,
        sha1c: String? = nil,
        url: String? = nil,
        url1: String? = nil,
        extraAttributes: [String: String] = [:]
    ) {
        self.creator = creator
        self.size = size
        self.type = type
        self.location = location
        self.friendly = friendly
        self.sha1d = sha1d
        self.sha1c = sha1c
        self.url = url
        self.url1 = url1
        self.extraAttributes = extraAttributes
    }

    /// Creates an MsnObject from raw payload bytes, computing canonical SHA1D and SHA1C digests.
    public static func create(
        creator: String,
        data: Data,
        type: Int = userTileType,
        location: String = defaultLocation,
        friendly: String = defaultFriendly,
        extraAttributes: [String: String] = [:]
    ) -> MsnObject {
        precondition(!creator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Creator cannot be blank")
        precondition(!data.isEmpty, "Data cannot be empty")

        let sha1d = computeSHA1D(data: data)
        let sha1c = computeSHA1C(
            creator: creator,
            size: data.count,
            type: type,
            location: location,
            friendly: friendly,
            sha1d: sha1d
        )

        return MsnObject(
            creator: creator,
            size: data.count,
            type: type,
            location: location,
            friendly: friendly,
            sha1d: sha1d,
            sha1c: sha1c,
            extraAttributes: extraAttributes
        )
    }

    /// Computes Base64-encoded SHA-1 digest of raw byte data.
    public static func computeSHA1D(data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return Data(digest).base64EncodedString()
    }

    /// Computes Base64-encoded SHA-1 digest of canonical metadata string.
    public static func computeSHA1C(
        creator: String,
        size: Int,
        type: Int,
        location: String,
        friendly: String,
        sha1d: String
    ) -> String {
        let canonical = "Creator\(creator)Size\(size)Type\(type)Location\(location)Friendly\(friendly)SHA1D\(sha1d)"
        let digest = Insecure.SHA1.hash(data: Data(canonical.utf8))
        return Data(digest).base64EncodedString()
    }

    /// Verifies if raw byte data matches this MSNObject's size and SHA1D hash.
    public func matches(data: Data) -> Bool {
        guard !data.isEmpty, data.count == size else { return false }
        return Self.computeSHA1D(data: data) == sha1d
    }

    /// Serializes this MSNObject into XML format.
    public func toXml() -> String {
        var xml = "<msnobj Creator=\"\(escapeXml(creator))\" Size=\"\(size)\" Type=\"\(type)\" Location=\"\(escapeXml(location))\" Friendly=\"\(escapeXml(friendly))\" SHA1D=\"\(escapeXml(sha1d))\""
        if let sha1c = sha1c {
            xml += " SHA1C=\"\(escapeXml(sha1c))\""
        }
        if let url = url {
            xml += " Url=\"\(escapeXml(url))\""
        }
        if let url1 = url1 {
            xml += " Url1=\"\(escapeXml(url1))\""
        }
        for (key, value) in extraAttributes.sorted(by: { $0.key < $1.key }) {
            let reserved = ["Creator", "Size", "Type", "Location", "Friendly", "SHA1D", "SHA1C", "Url", "Url1"]
            if !reserved.contains(key) {
                xml += " \(key)=\"\(escapeXml(value))\""
            }
        }
        xml += "/>"
        return xml
    }

    /// Encodes this MSNObject for inclusion in MSNP wire commands (URL percent-encoded with %20 for spaces).
    public func toEncodedValue() -> String {
        let xml = toXml()
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        let encoded = xml.addingPercentEncoding(withAllowedCharacters: allowed) ?? xml
        return encoded
    }

    /// Parses an MSNObject from an XML string or URL-encoded parameter.
    public static func parse(_ rawValue: String?, expectedType: Int = userTileType) -> MsnObject? {
        guard let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw != "0" else {
            return nil
        }

        let xml: String
        if raw.lowercased().hasPrefix("<msnobj") {
            xml = raw
        } else {
            xml = raw.removingPercentEncoding ?? raw
        }

        guard xml.count <= 64 * 1024,
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE") else {
            return nil
        }

        guard xml.localizedCaseInsensitiveContains("<msnobj") else { return nil }

        func extractAttribute(_ name: String) -> String? {
            let pattern = "\(name)=\"([^\"]*)\""
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: xml.utf16.count)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: xml) else {
                return nil
            }
            return unescapeXml(String(xml[range]))
        }

        guard let typeStr = extractAttribute("Type"),
              let parsedType = Int(typeStr),
              parsedType == expectedType,
              let creator = extractAttribute("Creator")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !creator.isEmpty,
              let sizeStr = extractAttribute("Size"),
              let size = Int(sizeStr),
              size > 0,
              let sha1d = extractAttribute("SHA1D")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha1d.isEmpty else {
            return nil
        }

        let location = extractAttribute("Location") ?? defaultLocation
        let friendly = extractAttribute("Friendly") ?? defaultFriendly
        let sha1c = extractAttribute("SHA1C")
        let url = extractAttribute("Url")
        let url1 = extractAttribute("Url1")

        return MsnObject(
            creator: creator,
            size: size,
            type: parsedType,
            location: location,
            friendly: friendly,
            sha1d: sha1d,
            sha1c: sha1c,
            url: url,
            url1: url1
        )
    }

    private func escapeXml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func unescapeXml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
