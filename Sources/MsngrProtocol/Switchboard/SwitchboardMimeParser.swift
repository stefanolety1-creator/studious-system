import Foundation

/// Parsed MIME message payload received over an MSNP18 Switchboard session.
public enum SwitchboardMimeMessage: Sendable, Equatable {
    case text(body: String, formatHeader: String?)
    case typing(user: String)
    case nudge(sender: String)
    case datacast(id: Int, rawBody: String)
    case unsupported(contentType: String)
}

/// Parser for MSNP18 Switchboard MIME envelopes (`text/plain`, `text/x-msmsgscontrol`, `text/x-msnmsgr-datacast`).
public struct SwitchboardMimeParser: Sendable {
    public static func parse(mimeText: String, sender: String = "peer@msngr.dev") -> SwitchboardMimeMessage {
        return parse(data: Data(mimeText.utf8), sender: sender)
    }

    public static func parse(data: Data, sender: String = "peer@msngr.dev") -> SwitchboardMimeMessage {
        let crlfCrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let lfLf = Data([0x0A, 0x0A])

        let delimRange = data.range(of: crlfCrlf) ?? data.range(of: lfLf)
        let headerData: Data
        let bodyData: Data

        if let delim = delimRange {
            headerData = data.subdata(in: 0..<delim.lowerBound)
            bodyData = data.subdata(in: delim.upperBound..<data.count)
        } else {
            headerData = data
            bodyData = Data()
        }

        let headerString = String(data: headerData, encoding: .utf8) ?? ""
        var headers: [String: String] = [:]
        headerString.enumerateLines { line, _ in
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let contentType = headers["content-type"]?
            .components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""

        switch contentType {
        case "text/plain":
            return .text(body: bodyString, formatHeader: headers["x-mms-im-format"])
        case "text/x-msmsgscontrol":
            guard let typingUser = headers["typinguser"], !typingUser.isEmpty else {
                return .unsupported(contentType: contentType)
            }
            return .typing(user: typingUser)
        case "text/x-msnmsgr-datacast":
            if bodyString.contains("ID: 1\r\n") || bodyString.trimmingCharacters(in: .whitespacesAndNewlines) == "ID: 1" {
                return .nudge(sender: sender)
            }
            return .datacast(id: 0, rawBody: bodyString)
        default:
            return .unsupported(contentType: contentType)
        }
    }
}
