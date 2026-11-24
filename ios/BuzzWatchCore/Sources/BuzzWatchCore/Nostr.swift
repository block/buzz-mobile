import CryptoKit
import Foundation
import P256K

/// A signed Nostr event (NIP-01).
public struct NostrEvent: Sendable, Equatable {
    public var id: String
    public var pubkey: String
    public var createdAt: Int64
    public var kind: Int
    public var tags: [[String]]
    public var content: String
    public var sig: String

    public init(id: String, pubkey: String, createdAt: Int64, kind: Int, tags: [[String]], content: String, sig: String) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
        self.sig = sig
    }

    /// The first value of the first tag called `name`.
    public func tag(_ name: String) -> String? {
        tags.first { $0.first == name && $0.count > 1 }?[1]
    }

    public var json: String {
        "{\"id\":\(quote(id)),\"pubkey\":\(quote(pubkey)),\"created_at\":\(createdAt),\"kind\":\(kind)," +
            "\"tags\":\(tagsJSON(tags)),\"content\":\(quote(content)),\"sig\":\(quote(sig))}"
    }

    /// An event from a relay's JSON, or nil if a field is missing or of the wrong type.
    public init?(json: Any?) {
        guard let object = json as? [String: Any],
              let id = object["id"] as? String,
              let pubkey = object["pubkey"] as? String,
              let createdAt = (object["created_at"] as? NSNumber)?.int64Value,
              let kind = (object["kind"] as? NSNumber)?.intValue,
              let tags = object["tags"] as? [[String]],
              let content = object["content"] as? String,
              let sig = object["sig"] as? String
        else { return nil }
        self.init(id: id, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content, sig: sig)
    }
}

public struct InvalidKey: Error {}

/// The key the watch signs with: its owner's, handed over by their phone at pairing.
public struct WatchKey: Sendable {
    private let secret: Data
    /// x-only public key, lowercase hex.
    public let pubkey: String

    public init(hex: String) throws {
        guard let bytes = Data(hex: hex), bytes.count == 32,
              let key = try? P256K.Schnorr.PrivateKey(dataRepresentation: bytes)
        else { throw InvalidKey() }
        secret = bytes
        pubkey = key.xonly.dataRepresentation.hex
    }

    public static func generate() -> WatchKey {
        while true {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
            if let key = try? WatchKey(hex: Data(bytes).hex) { return key }
        }
    }

    public var secretHex: String { secret.hex }

    public func sign(kind: Int, tags: [[String]], content: String, createdAt: Int64 = now()) -> NostrEvent {
        let id = eventID(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        // The key was validated when this value was made, so neither call can fail.
        let key = try! P256K.Schnorr.PrivateKey(dataRepresentation: secret)
        let signature = try! key.signature(message: id)
        return NostrEvent(
            id: id.hex, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content,
            sig: signature.dataRepresentation.hex
        )
    }
}

/// Whether `event` has the id its contents hash to and a signature by its author.
public func verify(_ event: NostrEvent) -> Bool {
    let id = eventID(pubkey: event.pubkey, createdAt: event.createdAt, kind: event.kind, tags: event.tags, content: event.content)
    guard id.hex == event.id,
          let pubkey = Data(hex: event.pubkey), pubkey.count == 32,
          let sig = Data(hex: event.sig),
          let signature = try? P256K.Schnorr.SchnorrSignature(dataRepresentation: sig),
          let key = try? P256K.Schnorr.XonlyKey(dataRepresentation: pubkey)
    else { return false }
    return key.isValid(signature, for: id)
}

func eventID(pubkey: String, createdAt: Int64, kind: Int, tags: [[String]], content: String) -> Data {
    let serialized = "[0,\(quote(pubkey)),\(createdAt),\(kind),\(tagsJSON(tags)),\(quote(content))]"
    return Data(SHA256.hash(data: Data(serialized.utf8)))
}

public func now() -> Int64 { Int64(Date().timeIntervalSince1970) }

func tagsJSON(_ tags: [[String]]) -> String {
    "[" + tags.map { "[" + $0.map(quote).joined(separator: ",") + "]" }.joined(separator: ",") + "]"
}

/// NIP-01 canonical string escaping: the event id depends on these exact bytes.
func quote(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        default:
            if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    return out + "\""
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        let digits = Array(hex.utf8)
        guard digits.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = Self.nibble(digits[index]), let low = Self.nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
        }
        self.init(bytes)
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case 48...57: digit - 48
        case 97...102: digit - 87
        case 65...70: digit - 55
        default: nil
        }
    }
}
