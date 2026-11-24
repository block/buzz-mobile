import Foundation

/// One community the watch can sign in to: what to call it, where to connect and the key to sign with.
public struct Pairing: Sendable, Equatable, Codable {
    public var name: String
    public var relay: String
    public var secret: String

    /// A pairing from the phone's JSON, or nil unless it names a relay the watch may use and a usable key.
    /// `allowInsecure` admits `ws://` relays, for a development relay on the same machine as a simulator.
    public init?(json: Any?, allowInsecure: Bool = false) {
        guard let object = json as? [String: Any],
              let relay = object["relay"] as? String,
              let secret = object["secret"] as? String,
              let url = URL(string: relay), let host = url.host,
              url.scheme == "wss" || (allowInsecure && url.scheme == "ws"),
              (try? WatchKey(hex: secret)) != nil
        else { return nil }
        let name = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.name = name ?? host
        self.relay = relay
        self.secret = secret
    }

    /// The communities in the phone's pairing message, one per relay, and the relay to open first.
    public static func parse(message: [String: Any], allowInsecure: Bool = false) -> (pairings: [Pairing], active: String?) {
        let list = message["communities"] as? [Any] ?? [message]
        var seen = Set<String>()
        let pairings = list.compactMap { Pairing(json: $0, allowInsecure: allowInsecure) }.filter { seen.insert($0.relay).inserted }
        return (pairings, message["active"] as? String)
    }
}
