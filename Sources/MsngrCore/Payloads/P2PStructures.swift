import Foundation

// MARK: - MSNSLP Message Protocol

public struct SlpMessage: Hashable, Sendable {
    public static let sessionRequestContentType = "application/x-msnmsgr-sessionreqbody"
    public static let sessionCloseContentType = "application/x-msnmsgr-sessionclosebody"
    public static let transportRequestContentType = "application/x-msnmsgr-transreqbody"
    public static let transportResponseContentType = "application/x-msnmsgr-transrespbody"

    public static let displayPictureGuid = "A4268EEC-FEC5-49E5-95C3-F126696BDBF6"
    public static let fileTransferGuid = "5D3E02AB-6190-11D3-BBBB-00C04F795683"
    public static let webcamProducerGuid = "4BD96FC0-AB17-4425-A14A-439185962DC8"
    public static let webcamRequestGuid = "1C9AA97E-9C05-4583-A3BD-908A196F1E92"
    public static let videoConferenceGuid = "02D3C01F-BF30-4825-A83A-DE7AF41648AA"

    public let firstLine: String
    public let to: String
    public let from: String
    public let branch: String
    public let callId: String
    public let cseq: Int
    public let contentType: String
    public let body: String

    public init(
        firstLine: String,
        to: String = "",
        from: String = "",
        branch: String,
        callId: String,
        cseq: Int = 0,
        contentType: String,
        body: String
    ) {
        self.firstLine = firstLine
        self.to = to
        self.from = from
        self.branch = branch
        self.callId = callId
        self.cseq = cseq
        self.contentType = contentType
        self.body = body
    }

    public static func parse(data: Data) -> SlpMessage? {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) else {
            return nil
        }
        guard let delimiterRange = text.range(of: "\r\n\r\n") else {
            return nil
        }
        let headerSection = String(text[..<delimiterRange.lowerBound])
        let bodySection = String(text[delimiterRange.upperBound...])
        let lines = headerSection.components(separatedBy: "\r\n")
        guard let firstLine = lines.first, !firstLine.isEmpty else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        var branch = ""
        if let via = headers["via"],
           let match = via.range(of: "branch=\\{([^}]+)\\}", options: .regularExpression) {
            let captured = String(via[match]).replacingOccurrences(of: "branch={", with: "").replacingOccurrences(of: "}", with: "")
            branch = captured
        }

        let callId = headers["call-id"]?.trimmingCharacters(in: CharacterSet(charactersIn: "{}")) ?? ""
        let contentType = headers["content-type"]?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let cseq = Int(headers["cseq"] ?? "0") ?? 0
        let to = headers["to"]?.trimmingCharacters(in: CharacterSet(charactersIn: "<>")).replacingOccurrences(of: "msnmsgr:", with: "") ?? ""
        let from = headers["from"]?.trimmingCharacters(in: CharacterSet(charactersIn: "<>")).replacingOccurrences(of: "msnmsgr:", with: "") ?? ""

        return SlpMessage(
            firstLine: firstLine,
            to: to,
            from: from,
            branch: branch,
            callId: callId,
            cseq: cseq,
            contentType: contentType,
            body: bodySection
        )
    }

    public func encode() -> Data {
        let contentBytes = (body + "\0").data(using: .utf8) ?? Data()
        var header = "\(firstLine)\r\n"
        header += "To: <msnmsgr:\(to)>\r\n"
        header += "From: <msnmsgr:\(from)>\r\n"
        header += "Via: MSNSLP/1.0/TLP ;branch={\(branch)}\r\n"
        header += "CSeq: \(cseq)\r\n"
        header += "Call-ID: {\(callId)}\r\n"
        header += "Max-Forwards: 0\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(contentBytes.count)\r\n\r\n"

        var data = Data(header.utf8)
        data.append(contentBytes)
        return data
    }
}

// MARK: - P2Pv1 48-Byte Header & 4-Byte Footer Framing

public struct P2Pv1Header: Hashable, Sendable {
    public static let size = 48
    public static let flagNone: UInt32 = 0x00
    public static let flagAck: UInt32 = 0x02
    public static let flagMsnObjectData: UInt32 = 0x20
    public static let flagFileData: UInt32 = 0x01000030

    public var sessionId: UInt32
    public var id: UInt32
    public var offset: UInt64
    public var totalSize: UInt64
    public var length: UInt32
    public var flags: UInt32
    public var ackId: UInt32
    public var ackSubId: UInt32
    public var ackSize: UInt64

    public init(
        sessionId: UInt32,
        id: UInt32,
        offset: UInt64,
        totalSize: UInt64,
        length: UInt32,
        flags: UInt32,
        ackId: UInt32 = 0,
        ackSubId: UInt32 = 0,
        ackSize: UInt64 = 0
    ) {
        self.sessionId = sessionId
        self.id = id
        self.offset = offset
        self.totalSize = totalSize
        self.length = length
        self.flags = flags
        self.ackId = ackId
        self.ackSubId = ackSubId
        self.ackSize = ackSize
    }
}

public struct P2Pv1Packet: Hashable, Sendable {
    public static let headerSize = 48
    public static let footerSize = 4

    public var header: P2Pv1Header
    public var body: Data
    public var appId: UInt32 // Big-Endian 4-byte footer

    public init(header: P2Pv1Header, body: Data, appId: UInt32) {
        self.header = header
        self.body = body
        self.appId = appId
    }

    public func encode() -> Data {
        var data = Data(capacity: Self.headerSize + body.count + Self.footerSize)
        withUnsafeBytes(of: header.sessionId.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: header.id.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: header.offset.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: header.totalSize.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: header.flags.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: header.ackId.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: header.ackSubId.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: header.ackSize.littleEndian) { data.append(contentsOf: $0) }
        data.append(body)
        withUnsafeBytes(of: appId.bigEndian) { data.append(contentsOf: $0) }
        return data
    }

    public static func parse(data: Data) -> P2Pv1Packet? {
        guard data.count >= headerSize + footerSize else { return nil }

        let sessionId = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let id = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let offset = data.subdata(in: 8..<16).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        let totalSize = data.subdata(in: 16..<24).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        let length = data.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let flags = data.subdata(in: 28..<32).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let ackId = data.subdata(in: 32..<36).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let ackSubId = data.subdata(in: 36..<40).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let ackSize = data.subdata(in: 40..<48).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }

        guard data.count == headerSize + Int(length) + footerSize else { return nil }
        let body = data.subdata(in: 48..<(48 + Int(length)))
        let appId: UInt32 = data.subdata(in: (48 + Int(length))..<data.count).withUnsafeBytes { buf in
            var val: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &val) { buf.copyBytes(to: $0) }
            return UInt32(bigEndian: val)
        }

        let header = P2Pv1Header(
            sessionId: sessionId,
            id: id,
            offset: offset,
            totalSize: totalSize,
            length: length,
            flags: flags,
            ackId: ackId,
            ackSubId: ackSubId,
            ackSize: ackSize
        )
        return P2Pv1Packet(header: header, body: body, appId: appId)
    }
}

// MARK: - P2Pv2 Framing & TLV Codec

public struct P2Pv2Packet: Hashable, Sendable {
    public static let opNone: UInt8 = 0
    public static let opSyn: UInt8 = 1
    public static let opRak: UInt8 = 2

    public static let tfNone: UInt8 = 0
    public static let tfFirst: UInt8 = 1
    public static let tfMsnObject: UInt8 = 4
    public static let tfFile: UInt8 = 6
    public static let tfWebcam: UInt8 = 4

    public var operationCode: UInt8
    public var identifier: UInt32
    public var ackIdentifier: UInt32?
    public var sessionId: UInt32
    public var tfCombination: UInt8
    public var packageNumber: UInt16
    public var dataRemaining: UInt64
    public var body: Data
    public var footer: UInt32
    public var peerInfo: Bool

    public var messageSize: Int {
        body.isEmpty ? 0 : dataHeaderLength + body.count
    }

    private var mainHeaderLength: Int {
        Self.padded(8 + (peerInfo ? 14 : 0) + (ackIdentifier != nil ? 6 : 0))
    }

    private var dataHeaderLength: Int {
        body.isEmpty ? 0 : Self.padded(8 + (dataRemaining > 0 ? 10 : 0))
    }

    public init(
        operationCode: UInt8 = opNone,
        identifier: UInt32,
        ackIdentifier: UInt32? = nil,
        sessionId: UInt32 = 0,
        tfCombination: UInt8 = tfNone,
        packageNumber: UInt16 = 0,
        dataRemaining: UInt64 = 0,
        body: Data = Data(),
        footer: UInt32 = 0,
        peerInfo: Bool = false
    ) {
        self.operationCode = operationCode
        self.identifier = identifier
        self.ackIdentifier = ackIdentifier
        self.sessionId = sessionId
        self.tfCombination = tfCombination
        self.packageNumber = packageNumber
        self.dataRemaining = dataRemaining
        self.body = body
        self.footer = footer
        self.peerInfo = peerInfo
    }

    public static func padded(_ value: Int) -> Int {
        (value + 3) & ~3
    }

    public func encode() -> Data {
        precondition(messageSize <= 0xFFFF, "P2Pv2 messageSize cannot exceed 65535 bytes")
        var data = Data()
        data.append(UInt8(mainHeaderLength))
        data.append(operationCode)
        withUnsafeBytes(of: UInt16(messageSize).bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: identifier.bigEndian) { data.append(contentsOf: $0) }

        if peerInfo {
            data.append(1) // Type 1
            data.append(12) // Length 12
            // 512, 0, 3584, 0, 271 in Little-Endian
            withUnsafeBytes(of: UInt16(512).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt16(0).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt16(3584).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt16(0).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(271).littleEndian) { data.append(contentsOf: $0) }
        }

        if let ack = ackIdentifier {
            data.append(2) // Type 2
            data.append(4) // Length 4
            withUnsafeBytes(of: ack.bigEndian) { data.append(contentsOf: $0) }
        }

        while data.count < mainHeaderLength {
            data.append(0)
        }

        if !body.isEmpty {
            data.append(UInt8(dataHeaderLength))
            data.append(tfCombination)
            withUnsafeBytes(of: packageNumber.bigEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: sessionId.bigEndian) { data.append(contentsOf: $0) }

            if dataRemaining > 0 {
                data.append(1) // Type 1
                data.append(8) // Length 8
                withUnsafeBytes(of: dataRemaining.bigEndian) { data.append(contentsOf: $0) }
            }

            while data.count < mainHeaderLength + dataHeaderLength {
                data.append(0)
            }
            data.append(body)
        }

        withUnsafeBytes(of: footer.bigEndian) { data.append(contentsOf: $0) }
        return data
    }

    public static func parse(data: Data) -> P2Pv2Packet? {
        guard data.count >= 12 else { return nil }
        let mainHeaderLen = Int(data[0])
        guard mainHeaderLen >= 8, mainHeaderLen % 4 == 0, mainHeaderLen <= data.count - 4 else {
            return nil
        }
        let opCode = data[1]
        let messageSize = data.subdata(in: 2..<4).withUnsafeBytes { Int($0.load(as: UInt16.self).bigEndian) }
        guard mainHeaderLen + messageSize + 4 == data.count else { return nil }

        let identifier = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        var pos = 8
        var ackId: UInt32? = nil
        var hasPeerInfo = false

        while pos + 2 <= mainHeaderLen {
            let t = data[pos]
            if t == 0 { break }
            let l = Int(data[pos + 1])
            pos += 2
            guard pos + l <= mainHeaderLen else { break }
            let val = data.subdata(in: pos..<(pos + l))
            if t == 1 && l == 12 {
                hasPeerInfo = true
            } else if t == 2 && l == 4 {
                ackId = val.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            }
            pos += l
        }

        var sessId: UInt32 = 0
        var tf: UInt8 = 0
        var pkgNum: UInt16 = 0
        var remaining: UInt64 = 0
        var packetBody = Data()

        if messageSize > 0 {
            let dataHeaderStart = mainHeaderLen
            let dataHeaderLen = Int(data[dataHeaderStart])
            guard dataHeaderLen >= 8, dataHeaderLen % 4 == 0, dataHeaderLen <= messageSize else {
                return nil
            }
            tf = data[dataHeaderStart + 1]
            pkgNum = data.subdata(in: (dataHeaderStart + 2)..<(dataHeaderStart + 4)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            sessId = data.subdata(in: (dataHeaderStart + 4)..<(dataHeaderStart + 8)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            var dPos = dataHeaderStart + 8
            let dEnd = dataHeaderStart + dataHeaderLen
            while dPos + 2 <= dEnd {
                let t = data[dPos]
                if t == 0 { break }
                let l = Int(data[dPos + 1])
                dPos += 2
                guard dPos + l <= dEnd else { break }
                let val = data.subdata(in: dPos..<(dPos + l))
                if t == 1 && l == 8 {
                    remaining = val.withUnsafeBytes { buf in
                        var v: UInt64 = 0
                        _ = withUnsafeMutableBytes(of: &v) { buf.copyBytes(to: $0) }
                        return UInt64(bigEndian: v)
                    }
                }
                dPos += l
            }

            let bodyStart = dataHeaderStart + dataHeaderLen
            let bodyEnd = dataHeaderStart + messageSize
            packetBody = data.subdata(in: bodyStart..<bodyEnd)
        }

        let footer: UInt32 = data.subdata(in: (mainHeaderLen + messageSize)..<data.count).withUnsafeBytes { buf in
            var val: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &val) { buf.copyBytes(to: $0) }
            return UInt32(bigEndian: val)
        }

        return P2Pv2Packet(
            operationCode: opCode,
            identifier: identifier,
            ackIdentifier: ackId,
            sessionId: sessId,
            tfCombination: tf,
            packageNumber: pkgNum,
            dataRemaining: remaining,
            body: packetBody,
            footer: footer,
            peerInfo: hasPeerInfo
        )
    }
}

// MARK: - MsnFileContext 574-Byte Binary Structure

public struct MsnFileContext: Hashable, Sendable {
    public static let contextSize = 574
    public static let maxFileNameBytes = 520 // 260 WCHARs

    public var fileName: String
    public var fileSize: UInt64

    /// Sanitizes paths by stripping both Unix '/' and Windows '\' directory separators and trimming whitespace.
    public static func sanitizeFileName(_ path: String) -> String {
        let forwardClean = (path as NSString).lastPathComponent
        let backClean = forwardClean.split(separator: "\\").last.map(String.init) ?? forwardClean
        let trimmed = backClean.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "file.bin" : trimmed
    }

    public init(fileName: String, fileSize: UInt64) {
        self.fileName = Self.sanitizeFileName(fileName)
        self.fileSize = fileSize
    }

    public func encode() -> Data {
        var data = Data(count: Self.contextSize)
        data.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: UInt32(574).littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: UInt32(2).littleEndian, toByteOffset: 4, as: UInt32.self)
            buf.storeBytes(of: fileSize.littleEndian, toByteOffset: 8, as: UInt64.self)
            buf.storeBytes(of: UInt32(1).littleEndian, toByteOffset: 16, as: UInt32.self)

            let cleanName = Self.sanitizeFileName(fileName)
            let nameData = cleanName.data(using: .utf16LittleEndian) ?? Data()
            let copyLen = min(nameData.count, Self.maxFileNameBytes - 2) & ~1

            nameData.copyBytes(to: buf.baseAddress!.advanced(by: 20).assumingMemoryBound(to: UInt8.self), count: copyLen)
            // Bytes 540..569 are left zero
            buf.storeBytes(of: UInt32.max.littleEndian, toByteOffset: 570, as: UInt32.self)
        }
        return data
    }

    public func encodeBase64() -> String {
        encode().base64EncodedString()
    }

    public static func parse(base64: String) -> MsnFileContext? {
        let cleaned = base64.filter { !$0.isWhitespace && $0 != "\0" }
        let padded: String
        switch cleaned.count % 4 {
        case 2: padded = cleaned + "=="
        case 3: padded = cleaned + "="
        default: padded = cleaned
        }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return parse(data: data)
    }

    public static func parse(data: Data) -> MsnFileContext? {
        if data.count < 20 {
            if let text = String(data: data, encoding: .utf8), text.contains("|") {
                let parts = text.components(separatedBy: "|")
                let name = Self.sanitizeFileName(parts[0])
                let size = UInt64(parts.count > 1 ? parts[1] : "0") ?? 0
                return MsnFileContext(fileName: name, fileSize: size)
            }
            return nil
        }

        return data.withUnsafeBytes { buf -> MsnFileContext? in
            let length = buf.load(fromByteOffset: 0, as: UInt32.self).littleEndian
            guard length >= 20 else { return nil }
            let fileSize = buf.load(fromByteOffset: 8, as: UInt64.self).littleEndian

            let maxWindow = min(Self.maxFileNameBytes, data.count - 20)
            let nameRaw = data.subdata(in: 20..<(20 + maxWindow))

            var nullIndex = -1
            for i in stride(from: 0, to: nameRaw.count - 1, by: 2) {
                if nameRaw[i] == 0 && nameRaw[i + 1] == 0 {
                    nullIndex = i
                    break
                }
            }
            let validLen = nullIndex >= 0 ? nullIndex : (nameRaw.count & ~1)
            let sub = nameRaw.subdata(in: 0..<validLen)
            let rawStr = String(data: sub, encoding: .utf16LittleEndian) ?? "file.bin"
            let fileName = Self.sanitizeFileName(rawStr)

            return MsnFileContext(fileName: fileName, fileSize: fileSize)
        }
    }
}
