import Foundation

/// An attachment on a message, from its NIP-92 `imeta` tag.
public struct Attachment: Sendable, Equatable, Hashable {
    public var url: String
    /// A small still to show in the conversation: the thumbnail, or a video's preview frame.
    public var preview: String?
    public var video: Bool
    public var durationSeconds: Int?
}

/// The images and videos attached to `event`. Other file types are left to the message text.
public func attachments(_ event: NostrEvent) -> [Attachment] {
    event.tags.compactMap { tag in
        guard tag.first == "imeta" else { return nil }
        var fields = [String: String]()
        for part in tag.dropFirst() {
            guard let space = part.firstIndex(of: " "), space != part.startIndex else { continue }
            fields[String(part[..<space])] = String(part[part.index(after: space)...])
        }
        guard let url = fields["url"], !url.isEmpty else { return nil }
        let type = fields["m"] ?? ""
        // Voice notes travel as small MP4 files; they are not something to look at.
        if (fields["filename"] ?? "").hasPrefix("voice-note-") { return nil }
        if type.hasPrefix("image/") {
            return Attachment(url: url, preview: fields["thumb"] ?? url, video: false, durationSeconds: nil)
        }
        if type.hasPrefix("video/") {
            let duration = fields["duration"].flatMap(Double.init).flatMap { $0.isFinite && $0 >= 0 && $0 < 360_000 ? Int($0) : nil }
            return Attachment(url: url, preview: fields["image"] ?? fields["thumb"], video: true, durationSeconds: duration)
        }
        return nil
    }
}

/// Downloads media. The relay's own media is private, so those requests carry
/// a short-lived proof signed by the owner's key (Blossom BUD-01). The proof is
/// sent only to the relay itself, never to another host.
public struct MediaFetcher: Sendable {
    private let relay: URL
    private let key: WatchKey
    private let session: URLSession

    public init(relayURL: URL, key: WatchKey, session: URLSession = .shared) {
        relay = relayURL
        self.key = key
        self.session = session
    }

    /// The bytes at `url`, or nil if it cannot be fetched or is larger than `maxBytes`.
    public func fetch(_ url: String, maxBytes: Int = 12 * 1024 * 1024) async -> Data? {
        guard let target = URL(string: url), target.scheme == "https" else { return nil }
        var request = URLRequest(url: target, timeoutInterval: 30)
        if isRelayMedia(target) { request.setValue("Nostr \(proof())", forHTTPHeaderField: "Authorization") }
        guard let (bytes, response) = try? await session.bytes(for: request, delegate: SameHostAuthorization()),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.expectedContentLength <= Int64(maxBytes)
        else { return nil }
        var data = Data()
        do {
            // A missing length header must not let a huge download through.
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { return nil }
            }
        } catch { return nil }
        return data
    }

    /// Whether `target` is the relay's own media, the only place the proof may go.
    func isRelayMedia(_ target: URL) -> Bool {
        guard let host = target.host, let relayHost = relay.host else { return false }
        return host.caseInsensitiveCompare(relayHost) == .orderedSame &&
            (target.port ?? 443) == (relay.port ?? 443) && target.path.hasPrefix("/media/")
    }

    private func proof() -> String {
        let authority = (relay.host ?? "").lowercased() + (relay.port.map { ":\($0)" } ?? "")
        let event = key.sign(
            kind: 24242,
            tags: [["t", "get"], ["expiration", String(now() + 60)], ["server", authority]],
            content: "Get buzz-media"
        )
        return Data(event.json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Keeps the signed proof from following a redirect to another host.
private final class SameHostAuthorization: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var next = request
        let from = task.originalRequest?.url
        if next.url?.scheme != "https" || next.url?.host?.lowercased() != from?.host?.lowercased() || next.url?.port != from?.port {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(next)
    }
}
