import Foundation

/// Sends one batch and returns the HTTP status. Injectable for tests.
protocol RouteRevTransport: Sendable {
    func send(_ body: Data, to endpoint: URL) async throws -> Int
}

struct URLSessionTransport: RouteRevTransport {
    func send(_ body: Data, to endpoint: URL) async throws -> Int {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
