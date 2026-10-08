//
//  JiraMock.swift
//  GitHallsTests
//

import Foundation
@testable import GitHalls

/// A canned answer for one request.
struct MockReply {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()

    init(status: Int = 200, headers: [String: String] = [:], json: String = "") {
        self.status = status
        self.headers = headers
        self.body = Data(json.utf8)
    }

    init(status: Int = 200, data: Data) {
        self.status = status
        self.body = data
    }
}

/// What the client sent, as a test wants to read it.
struct SentRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data?

    var json: [String: Any]? { body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    var fields: [String: Any]? { json?["fields"] as? [String: Any] }
}

/// `URLProtocol` that answers from a closure, so the client is tested without a
/// network. Each mock owns a unique host and tests run in parallel, so the
/// handlers are looked up by host.
final class MockJira: @unchecked Sendable {
    typealias Handler = (SentRequest) -> MockReply

    let host = "t\(UUID().uuidString.prefix(8).lowercased()).jira.test"
    private let lock = NSLock()
    private var handler: Handler
    private var log: [SentRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
        MockJiraProtocol.register(host: host, mock: self)
    }

    deinit { MockJiraProtocol.unregister(host: host) }

    var requests: [SentRequest] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    var client: JiraClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockJiraProtocol.self]
        var client = JiraClient(credentials: JiraCredentials(
            site: URL(string: "https://\(host)")!, email: "me@acme.test", token: "secret"
        ), session: URLSession(configuration: configuration))
        client.retrySleep = { _ in }
        return client
    }

    fileprivate func answer(_ sent: SentRequest) -> MockReply {
        lock.lock()
        log.append(sent)
        let handler = handler
        lock.unlock()
        return handler(sent)
    }
}

final class MockJiraProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var mocks: [String: MockJira] = [:]

    fileprivate static func register(host: String, mock: MockJira) {
        lock.lock(); mocks[host] = mock; lock.unlock()
    }

    fileprivate static func unregister(host: String) {
        lock.lock(); mocks[host] = nil; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        Self.lock.lock()
        let mock = Self.mocks[host]
        Self.lock.unlock()

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }

        let sent = SentRequest(
            method: request.httpMethod ?? "GET",
            path: components?.percentEncodedPath ?? url.path,
            query: query,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? Self.read(request.httpBodyStream)
        )
        let reply = mock?.answer(sent) ?? MockReply(status: 599)

        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
