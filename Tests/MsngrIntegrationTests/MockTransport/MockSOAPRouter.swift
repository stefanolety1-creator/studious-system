//
// MockSOAPRouter.swift
// MsngrIntegrationTests
//
// Routing table and URLProtocol extensions directing SOAP requests
// to in-memory fixtures, passport servers, and ABCH servers.
//

import Foundation
import MsngrCore
import MsngrProtocol

/// Describes a declarative SOAP route pattern and its responder closure.
public struct SOAPRoute: Sendable {
    public let pathPattern: String
    public let soapAction: String?
    public let handler: @Sendable (URLRequest, Data) -> MockSOAPResponse?

    public init(
        pathPattern: String,
        soapAction: String? = nil,
        handler: @escaping @Sendable (URLRequest, Data) -> MockSOAPResponse?
    ) {
        self.pathPattern = pathPattern
        self.soapAction = soapAction
        self.handler = handler
    }
}

/// Standard server preset endpoint pairs for in-memory SOAP routing.
public struct SOAPPresetEndpoints: Sendable, Equatable {
    public let authUrl: String
    public let addressBookUrl: String

    public init(authUrl: String, addressBookUrl: String) {
        self.authUrl = authUrl
        self.addressBookUrl = addressBookUrl
    }

    /// Crosstalk default preset endpoints.
    public static let crosstalk = SOAPPresetEndpoints(
        authUrl: "https://ctas.login.ugnet.gay/RST.srf",
        addressBookUrl: "https://ctsvcs.addressbook.ugnet.gay/abservice/abservice.asmx"
    )

    /// Escargot preset endpoints.
    public static let escargot = SOAPPresetEndpoints(
        authUrl: "https://nexus.escargot.chat/RST.srf",
        addressBookUrl: "https://contacts.escargot.chat/abservice/abservice.asmx"
    )
}

/// Standalone thread-safe SOAP route table for dispatching mock SOAP responses based on URL and SOAPAction.
public final class MockSOAPRouteTable: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [SOAPRoute] = []

    public init() {}

    public func addRoute(_ route: SOAPRoute) {
        lock.lock()
        defer { lock.unlock() }
        routes.append(route)
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        routes.removeAll()
    }

    public func match(request: URLRequest, body: Data) -> MockSOAPResponse? {
        lock.lock()
        let currentRoutes = routes
        lock.unlock()

        guard let url = request.url else { return nil }
        let path = url.path
        let reqAction = request.value(forHTTPHeaderField: "SOAPAction")?.replacingOccurrences(of: "\"", with: "")

        for route in currentRoutes {
            if path.contains(route.pathPattern) || route.pathPattern == "*" {
                if let targetAction = route.soapAction {
                    if let reqAction = reqAction, reqAction.contains(targetAction) {
                        return route.handler(request, body)
                    }
                } else {
                    return route.handler(request, body)
                }
            }
        }
        return nil
    }
}

// MARK: - MockSOAPRouter Extensions

extension MockSOAPRouter {
    /// Configures the shared router to intercept all requests for a given preset and dispatch
    /// to the provided mock Passport and ABCH servers.
    public func configurePreset(
        _ preset: SOAPPresetEndpoints,
        passport: MockPassportServer,
        abch: MockABCHServer
    ) {
        self.passportServer = passport
        self.abchServer = abch

        // Register custom handler routing preset URLs directly
        self.addCustomHandler { request, body in
            guard let url = request.url else { return nil }
            let urlString = url.absoluteString

            if urlString.contains(preset.authUrl) || url.path.hasSuffix("/RST.srf") {
                return passport.handle(request: request, body: body)
            }

            if urlString.contains(preset.addressBookUrl) || url.path.contains("/abservice/") {
                return abch.handle(request: request, body: body)
            }

            return nil
        }
    }

    /// Registers a canned XML response for a given SOAPAction substring.
    public func registerSOAPAction(_ action: String, xmlResponse: String, statusCode: Int = 200) {
        self.addCustomHandler { request, _ in
            if let reqAction = request.value(forHTTPHeaderField: "SOAPAction"),
               reqAction.contains(action) {
                return MockSOAPResponse(statusCode: statusCode, xml: xmlResponse)
            }
            return nil
        }
    }

    /// Registers an error / SOAP Fault response for a given SOAPAction.
    public func registerFault(
        action: String,
        faultCode: String = "wsse:FailedAuthentication",
        faultString: String = "Authentication Failure"
    ) {
        let faultXml = """
        <?xml version="1.0" encoding="utf-8"?>
        <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
          <Body>
            <Fault>
              <faultcode>\(faultCode)</faultcode>
              <faultstring>\(faultString)</faultstring>
            </Fault>
          </Body>
        </Envelope>
        """
        registerSOAPAction(action, xmlResponse: faultXml, statusCode: 500)
    }

    /// Creates an ephemeral URLSession pre-configured with MockSOAPURLProtocol.
    public static func makeSession() -> URLSession {
        return URLSession(configuration: .mockSOAP)
    }

    /// Automatically installs mock sessions on default clients.
    public static func installDefaultMocks(passport: MockPassportServer, abch: MockABCHServer) {
        MockSOAPURLProtocol.register()
        let router = MockSOAPRouter.shared
        router.passportServer = passport
        router.abchServer = abch
    }

    /// Teardown helper resetting shared router and restoring default sessions.
    public static func restoreDefaults() {
        MockSOAPRouter.shared.reset()
        MockSOAPURLProtocol.unregister()
    }
}
