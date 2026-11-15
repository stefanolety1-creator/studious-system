import Foundation
import MsngrCore

/// Represents a decoded or outbound MSNP18 protocol command frame.
public struct MsnpFrame: Sendable, Equatable {
    public let verb: String
    public let transactionId: Int?
    public let parameters: [String]
    public let payload: Data?

    public init(verb: String, transactionId: Int? = nil, parameters: [String] = [], payload: Data? = nil) {
        self.verb = verb
        self.transactionId = transactionId
        self.parameters = parameters
        self.payload = payload
    }

    /// Serializes the command frame into MSNP18 wire bytes (`VERB [trId] [params]\r\n[payload]`).
    public func toWireData() -> Data {
        var parts = [verb]
        if let trId = transactionId {
            parts.append(String(trId))
        }
        parts.append(contentsOf: parameters)
        var header = parts.joined(separator: " ") + "\r\n"
        var data = Data(header.utf8)
        if let payload = payload {
            data.append(payload)
        }
        return data
    }
}

public typealias MsnpCommand = MsnpFrame

// MARK: - MSNObject Validation Extensions & Types

public enum MsnObjectError: Error, Equatable, Sendable {
    case payloadTooLarge
    case missingChecksum
    case corruptedChecksum
}

public enum MsnObjectType: Int, Sendable {
    case userTile = 3
    case wink = 8
    case voiceClip = 11
}

extension MsnObject {
    public static func parseStrict(_ xml: String, expectedType: Int = userTileType) throws -> MsnObject {
        guard let obj = MsnObject.parse(xml, expectedType: expectedType) else {
            throw MsnObjectError.missingChecksum
        }
        guard obj.size <= maxDisplayPictureBytes else {
            throw MsnObjectError.payloadTooLarge
        }
        guard validateSha1c(obj.sha1c) else {
            throw MsnObjectError.corruptedChecksum
        }
        return obj
    }

    public static func createValidated(creator: String, data: Data, type: Int = userTileType) throws -> MsnObject {
        guard data.count <= maxDisplayPictureBytes else {
            throw MsnObjectError.payloadTooLarge
        }
        return MsnObject.create(creator: creator, data: data, type: type)
    }

    public static func validateSha1c(_ sha1c: String?) -> Bool {
        guard let sha1c = sha1c else { return true }
        guard sha1c.count == 28, let data = Data(base64Encoded: sha1c), data.count == 20 else {
            return false
        }
        return true
    }
}
