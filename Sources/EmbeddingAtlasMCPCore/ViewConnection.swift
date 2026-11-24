import Foundation

public struct HTTPReply: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public enum ConnectionFailure: Error, Equatable {
    case unreachable
    case timedOut
}

/// The only door to a view. `LoopbackConnection` implements it over HTTP; the tests
/// implement it with `FakeView`.
///
/// The door takes a port and a path, never a host: a view is reached on this machine or
/// not at all.
public protocol ViewConnection: Sendable {
    /// A GET when `body` is nil, a JSON POST otherwise.
    func send(port: Int, path: String, body: Data?, timeout: Duration) async throws -> HTTPReply
}

/// HTTP to `127.0.0.1` and nowhere else: no proxy, no redirect, no cookie, no cache.
public final class LoopbackConnection: NSObject, ViewConnection, URLSessionTaskDelegate {
    private let session: URLSession

    public override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        super.init()
    }

    public func send(
        port: Int, path: String, body: Data?, timeout: Duration
    ) async throws -> HTTPReply {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            throw ConnectionFailure.unreachable
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = Double(timeout.components.seconds)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request, delegate: self)
            return HTTPReply(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch let error as URLError where error.code == .timedOut {
            throw ConnectionFailure.timedOut
        } catch {
            throw ConnectionFailure.unreachable
        }
    }

    /// A view has no reason to send this server elsewhere, so a redirect is not followed.
    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
