import XCTest
import Foundation
import Network
@testable import MsngrCore
@testable import MsngrProtocol

// MARK: - Test Timeouts

public enum TestTimeout {
    public static let fast: TimeInterval = 1.0
    public static let standard: TimeInterval = 3.0
    public static let long: TimeInterval = 5.0
}

// MARK: - Async Test Errors

public struct AsyncStreamExpectationError: Error, LocalizedError, CustomStringConvertible {
    public let description: String
    public init(_ description: String) {
        self.description = description
    }
    public var errorDescription: String? {
        return description
    }
}

// MARK: - XCTestCase Concurrency Helpers

extension XCTestCase {
    /// Await an event matching a predicate from an AsyncStream with timeout.
    @discardableResult
    public func expectEvent<T: Sendable>(
        from stream: AsyncStream<T>,
        timeout: TimeInterval = TestTimeout.standard,
        description: String = "Waiting for expected stream event",
        matching predicate: @escaping @Sendable (T) -> Bool
    ) async throws -> T {
        final class Box: @unchecked Sendable {
            var value: T?
        }
        let box = Box()

        let consumerTask = Task {
            for await item in stream {
                if Task.isCancelled { break }
                if predicate(item) {
                    box.value = item
                    break
                }
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let val = box.value {
                consumerTask.cancel()
                return val
            }
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
        }

        consumerTask.cancel()
        if let val = box.value {
            return val
        }
        throw AsyncStreamExpectationError("\(description): timed out after \(timeout)s")
    }

    /// Wait for an async condition to evaluate to true within the given timeout.
    public func waitForCondition(
        timeout: TimeInterval = TestTimeout.standard,
        pollInterval: TimeInterval = 0.05,
        description: String = "Waiting for condition",
        condition: @escaping @Sendable () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await condition() {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        XCTFail("\(description): timed out after \(timeout)s")
    }

    /// Helper to safely extract XML tag content using NSRegularExpression.
    public func extractTagContent(_ xml: String, tag: String) -> String? {
        return SOAPXmlBuilder.extractTag(xml, tag: tag)
    }

    /// Helper to safely extract XML attribute value using NSRegularExpression.
    public func extractTagAttribute(_ xml: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)[^>]*\\b\(attribute)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[captureRange])
    }
}
