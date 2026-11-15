//
// MockSOAPURLProtocol.swift
// MsngrIntegrationTests
//
// HTTP and SOAP URLProtocol interceptor that captures in-process requests to /RST.srf
// and ABCH web services without outbound network traffic.
//

import Foundation
import MsngrProtocol

/// HTTP and SOAP URLProtocol interceptor that captures in-process requests to /RST.srf
/// and ABCH web services without outbound network traffic.
public final class MockSOAPURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "MockSOAPURLProtocolHandledKey"

    // MARK: - Registration Helpers

    /// Registers MockSOAPURLProtocol globally with the default URL loading system.
    public static func register() {
        URLProtocol.registerClass(MockSOAPURLProtocol.self)
        let mockSession = URLSession(configuration: .mockSOAP)
        PassportRST2Client.defaultSession = mockSession
        ABCHClient.defaultSession = mockSession
    }

    /// Unregisters MockSOAPURLProtocol globally from the default URL loading system.
    public static func unregister() {
        URLProtocol.unregisterClass(MockSOAPURLProtocol.self)
        PassportRST2Client.defaultSession = .shared
        ABCHClient.defaultSession = .shared
    }

    // MARK: - URLProtocol Lifecycle

    public override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }
        return MockSOAPRouter.shared.canHandle(request: request)
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    public override func startLoading() {
        guard let mutableRequest = (request as? NSMutableURLRequest) ?? (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        let bodyData = extractBodyData(from: request)

        guard let response = MockSOAPRouter.shared.route(request: request, body: bodyData) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        guard let requestUrl = request.url,
              let httpResponse = HTTPURLResponse(
                url: requestUrl,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {
        // Synchronous in-memory responder; no asynchronous stream cancellation required
    }

    // MARK: - Private Helpers

    private func extractBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }

        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data
    }
}

// MARK: - MockSOAPResponse

public struct MockSOAPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data

    public init(statusCode: Int = 200, headers: [String: String] = ["Content-Type": "text/xml; charset=utf-8"], data: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }

    public init(statusCode: Int = 200, xml: String) {
        let utf8Data = Data(xml.utf8)
        self.statusCode = statusCode
        self.headers = [
            "Content-Type": "text/xml; charset=utf-8",
            "Content-Length": "\(utf8Data.count)"
        ]
        self.data = utf8Data
    }
}

// MARK: - MockSOAPRouter

public final class MockSOAPRouter: @unchecked Sendable {
    public static let shared = MockSOAPRouter()

    private let lock = NSLock()
    private var _passportServer: MockPassportServer?
    private var _abchServer: MockABCHServer?
    private var _customHandlers: [(@Sendable (URLRequest, Data) -> MockSOAPResponse?)] = []

    public var passportServer: MockPassportServer? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _passportServer
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _passportServer = newValue
        }
    }

    public var abchServer: MockABCHServer? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _abchServer
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _abchServer = newValue
        }
    }

    public var customHandlers: [(@Sendable (URLRequest, Data) -> MockSOAPResponse?)] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _customHandlers
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _customHandlers = newValue
        }
    }

    private init() {}

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _passportServer = nil
        _abchServer = nil
        _customHandlers.removeAll()
    }

    public func addCustomHandler(_ handler: @escaping @Sendable (URLRequest, Data) -> MockSOAPResponse?) {
        lock.lock()
        defer { lock.unlock() }
        _customHandlers.append(handler)
    }

    public func canHandle(request: URLRequest) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let url = request.url else { return false }

        // Passport RST2 handler check
        if url.path.hasSuffix("/RST.srf") || url.path.contains("RST.srf") {
            return _passportServer != nil
        }

        // ABCH handler check
        if url.path.contains("/abservice/") || url.path.hasSuffix(".asmx") {
            return _abchServer != nil
        }

        // Custom handlers check
        for handler in _customHandlers {
            if handler(request, Data()) != nil {
                return true
            }
        }
        return false
    }

    public func route(request: URLRequest, body: Data) -> MockSOAPResponse? {
        lock.lock()
        let handlers = _customHandlers
        let passport = _passportServer
        let abch = _abchServer
        lock.unlock()

        guard let url = request.url else { return nil }

        // Custom handlers take precedence
        for handler in handlers {
            if let response = handler(request, body) {
                return response
            }
        }

        // Route to Passport Server
        if url.path.hasSuffix("/RST.srf") || url.path.contains("RST.srf") {
            return passport?.handle(request: request, body: body)
        }

        // Route to ABCH Server
        if url.path.contains("/abservice/") || url.path.hasSuffix(".asmx") {
            return abch?.handle(request: request, body: body)
        }

        return nil
    }
}

// MARK: - URLSession Extensions

public extension URLSessionConfiguration {
    /// Returns an ephemeral URLSessionConfiguration preconfigured with MockSOAPURLProtocol.
    static var mockSOAP: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSOAPURLProtocol.self]
        return config
    }
}
