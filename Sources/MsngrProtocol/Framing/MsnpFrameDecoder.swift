import Foundation

/// Incremental TCP stream frame decoder for MSNP18 protocol commands and binary payloads.
public final class MsnpFrameDecoder: @unchecked Sendable {
    private var buffer = Data()
    private var pendingFrame: (frame: MsnpFrame, length: Int)?
    private static let crlf = Data([0x0D, 0x0A])
    private static let payloadVerbs: Set<String> = [
        "MSG", "UUM", "UBM", "UUX", "UBX", "UBN", "ADL", "RML", "NOT", "GCF", "SDG", "NFY", "PUT"
    ]

    public init() {}

    /// Feeds incoming TCP bytes and returns all completely decoded MSNP18 frames.
    public func feed(_ bytes: Data) -> [MsnpFrame] {
        buffer.append(bytes)
        var frames: [MsnpFrame] = []

        while true {
            if let pending = pendingFrame {
                if buffer.count < pending.length {
                    break
                }
                let payload = buffer.subdata(in: 0..<pending.length)
                buffer.removeSubrange(0..<pending.length)
                frames.append(MsnpFrame(
                    verb: pending.frame.verb,
                    transactionId: pending.frame.transactionId,
                    parameters: pending.frame.parameters,
                    payload: payload
                ))
                self.pendingFrame = nil
                continue
            }

            guard let crlfRange = buffer.range(of: Self.crlf) else {
                break
            }

            let lineData = buffer.subdata(in: 0..<crlfRange.lowerBound)
            buffer.removeSubrange(0..<crlfRange.upperBound)

            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                continue
            }

            let tokens = line.components(separatedBy: " ").filter { !$0.isEmpty }
            guard let verb = tokens.first?.uppercased() else { continue }

            let nonTx: Set<String> = ["RNG", "NOT", "QNG"]
            let trId: Int?
            let pStart: Int
            if nonTx.contains(verb) {
                trId = nil
                pStart = 1
            } else {
                trId = tokens.count > 1 ? Int(tokens[1]) : nil
                pStart = trId == nil ? 1 : 2
            }

            let params = tokens.count > pStart ? Array(tokens[pStart...]) : []
            let frame = MsnpFrame(verb: verb, transactionId: trId, parameters: params)

            if Self.payloadVerbs.contains(verb), let last = params.last, let len = Int(last), len > 0 {
                if buffer.count < len {
                    self.pendingFrame = (frame, len)
                    break
                } else {
                    let payload = buffer.subdata(in: 0..<len)
                    buffer.removeSubrange(0..<len)
                    frames.append(MsnpFrame(
                        verb: frame.verb,
                        transactionId: frame.transactionId,
                        parameters: frame.parameters,
                        payload: payload
                    ))
                }
            } else {
                frames.append(frame)
            }
        }
        return frames
    }
}
