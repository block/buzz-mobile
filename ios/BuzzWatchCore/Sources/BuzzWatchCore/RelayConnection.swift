import Foundation

public struct RelayRefused: Error, LocalizedError {
    public let reason: String
    public var errorDescription: String? { reason }
}

/// What to ask a relay for (NIP-01 filter).
public struct Filter: Sendable {
    var fields: [String: any Sendable] = [:]

    public init(kinds: [Int]) { fields["kinds"] = kinds }

    public func tag(_ name: String, _ values: [String]) -> Filter { with("#\(name)", values) }
    public func authors(_ values: [String]) -> Filter { with("authors", values) }
    public func limit(_ count: Int) -> Filter { with("limit", count) }
    public func since(_ time: Int64) -> Filter { with("since", time) }

    private func with(_ name: String, _ value: any Sendable) -> Filter {
        var copy = self
        copy.fields[name] = value
        return copy
    }

    var json: String {
        let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

/// One authenticated connection from the watch to a relay: NIP-42 login with
/// the key the watch holds, then publish, query and subscribe.
public actor RelayConnection {
    private let relayURL: URL
    private let key: WatchKey
    private let session: URLSession
    /// Called once if the connection drops after a successful login.
    private let onLost: @Sendable (String) -> Void

    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var pinger: Task<Void, Never>?
    private var authEventID: String?
    private var authenticated = false
    private var lost = false
    private var login: CheckedContinuation<Void, Error>?
    private var pendingOK: [String: CheckedContinuation<Void, Error>] = [:]
    private var subscriptions: [String: @Sendable (NostrEvent) -> Void] = [:]
    private var ends: [String: CheckedContinuation<Void, Never>] = [:]
    private var counter = 0

    public init(relayURL: URL, key: WatchKey, session: URLSession = .shared, onLost: @escaping @Sendable (String) -> Void = { _ in }) {
        self.relayURL = relayURL
        self.key = key
        self.session = session
        self.onLost = onLost
    }

    /// Connect and complete the relay login, or throw with the relay's reason.
    public func connect(timeout: TimeInterval = 15) async throws {
        let socket = session.webSocketTask(with: relayURL)
        self.socket = socket
        socket.resume()
        reader = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    if case let .string(text) = message { await self?.handle(text) }
                } catch {
                    await self?.fail("connection failed: \(error.localizedDescription)")
                    return
                }
            }
        }
        let deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
            if !Task.isCancelled { await self?.fail("the relay did not answer in time") }
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { login = $0 }
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if Task.isCancelled { return }
                socket.sendPing { [weak self] error in
                    if let error { Task { await self?.fail("connection failed: \(error.localizedDescription)") } }
                }
            }
        }
    }

    /// Publish a channel message (kind 9, NIP-29 `h` tag). Returns the event id.
    @discardableResult
    public func sendMessage(channel: String, text: String, extraTags: [[String]] = []) async throws -> String {
        let event = key.sign(kind: 9, tags: [["h", channel]] + extraTags, content: text)
        try await publish(event)
        return event.id
    }

    public func publish(_ event: NostrEvent, timeout: TimeInterval = 15) async throws {
        let id = event.id
        // The same text sent twice within a second is the same event.
        if pendingOK[id] != nil { throw RelayRefused(reason: "already sending") }
        let deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
            if !Task.isCancelled { await self?.settle(id, .failure(RelayRefused(reason: "the relay did not confirm in time"))) }
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<Void, Error>) in
            pendingOK[id] = waiting
            do { try send("[\"EVENT\",\(event.json)]") } catch { settle(id, .failure(error)) }
        }
    }

    /// Live channel messages and activity signals from now on. Returns an id for `unsubscribe`.
    public func subscribe(channel: String, onEvent: @escaping @Sendable (NostrEvent) -> Void) throws -> String {
        counter += 1
        let id = "watch-\(counter)"
        subscriptions[id] = onEvent
        // 20002 is the short-lived "working on it" signal agents send.
        let filter = Filter(kinds: [9, 20002]).tag("h", [channel]).since(now())
        try send("[\"REQ\",\(quote(id)),\(filter.json)]")
        return id
    }

    public func unsubscribe(_ id: String) {
        subscriptions[id] = nil
        try? send("[\"CLOSE\",\(quote(id))]")
    }

    /// What the relay holds for `filter` right now. Empty if it does not answer in time.
    public func query(_ filter: Filter, timeout: TimeInterval = 10) async -> [NostrEvent] {
        counter += 1
        let id = "query-\(counter)"
        let found = Collected()
        subscriptions[id] = { found.add($0) }
        let deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
            if !Task.isCancelled { await self?.end(id) }
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            ends[id] = done
            do { try send("[\"REQ\",\(quote(id)),\(filter.json)]") } catch { end(id) }
        }
        deadline.cancel()
        unsubscribe(id)
        return found.events
    }

    public func close() {
        lost = true
        reader?.cancel()
        pinger?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        fail("closed")
    }

    private func send(_ frame: String) throws {
        guard let socket, !lost else { throw RelayRefused(reason: "not connected") }
        socket.send(.string(frame)) { [weak self] error in
            if let error { Task { await self?.fail("connection failed: \(error.localizedDescription)") } }
        }
    }

    private func handle(_ text: String) {
        guard let frame = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any],
              let type = frame.first as? String
        else { return }
        func string(_ index: Int) -> String { frame.count > index ? frame[index] as? String ?? "" : "" }
        switch type {
        case "AUTH":
            let event = key.sign(kind: 22242, tags: [["relay", relayURL.absoluteString], ["challenge", string(1)]], content: "")
            authEventID = event.id
            try? send("[\"AUTH\",\(event.json)]")
        case "OK":
            let accepted = frame.count > 2 && (frame[2] as? Bool ?? false)
            if string(1) == authEventID {
                if accepted {
                    authenticated = true
                    login?.resume()
                } else {
                    login?.resume(throwing: RelayRefused(reason: "login refused: \(string(3))"))
                }
                login = nil
            } else {
                settle(string(1), accepted ? .success(()) : .failure(RelayRefused(reason: "event refused: \(string(3))")))
            }
        case "EVENT":
            guard frame.count > 2, let event = NostrEvent(json: frame[2]), verify(event) else { return }
            subscriptions[string(1)]?(event)
        case "EOSE":
            end(string(1))
        case "CLOSED":
            subscriptions[string(1)] = nil
            end(string(1))
        default:
            break
        }
    }

    private func settle(_ id: String, _ result: Result<Void, Error>) {
        pendingOK.removeValue(forKey: id)?.resume(with: result)
    }

    private func end(_ id: String) {
        ends.removeValue(forKey: id)?.resume()
    }

    private func fail(_ reason: String) {
        let error = RelayRefused(reason: reason)
        if authenticated, !lost {
            lost = true
            onLost(reason)
        }
        lost = true
        // Nothing may keep reading, pinging or answering on a connection that is over.
        reader?.cancel()
        pinger?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        login?.resume(throwing: error)
        login = nil
        for waiting in pendingOK.values { waiting.resume(throwing: error) }
        pendingOK.removeAll()
        for waiting in ends.values { waiting.resume() }
        ends.removeAll()
    }
}

/// Events gathered by one query, appended from the connection's callbacks.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [NostrEvent] = []

    func add(_ event: NostrEvent) {
        lock.lock()
        list.append(event)
        lock.unlock()
    }

    var events: [NostrEvent] {
        lock.lock()
        defer { lock.unlock() }
        return list
    }
}
