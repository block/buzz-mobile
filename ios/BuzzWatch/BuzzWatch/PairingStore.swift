import BuzzWatchCore
import Foundation
import Security
import WatchConnectivity

/// Keeps the pairings on the watch, in the Keychain: readable only on this
/// watch, and only after it has been unlocked once since it started.
enum PairingStore {
    private static let service = "buzz-watch-pairing"
    private static let defaults = UserDefaults.standard

    /// Replace everything the watch holds with `pairings`; `active` is the relay to open first.
    static func save(_ pairings: [Pairing], active: String?) -> Bool {
        guard let data = try? JSONEncoder().encode(pairings) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        // Update in place where there is one, so a failed write leaves the old pairings.
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }
        defaults.set(pairings.first { $0.relay == active }?.relay ?? pairings.first?.relay, forKey: "active")
        return true
    }

    static func loadAll() -> [Pairing] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return [] }
        return (try? JSONDecoder().decode([Pairing].self, from: data)) ?? []
    }

    /// The community to open: the one last chosen, else the first.
    static func load() -> Pairing? {
        let all = loadAll()
        let active = defaults.string(forKey: "active")
        return all.first { $0.relay == active } ?? all.first
    }

    static func choose(_ relay: String) { defaults.set(relay, forKey: "active") }

    static func channel(for relay: String) -> String? { defaults.string(forKey: "channel:\(relay)") }
    static func setChannel(_ id: String, for relay: String) { defaults.set(id, forKey: "channel:\(relay)") }
    static func agent(for channel: String) -> String? { defaults.string(forKey: "agent:\(channel)") }
    static func setAgent(_ id: String, for channel: String) { defaults.set(id, forKey: "agent:\(channel)") }
}

/// Receives the pairing from the owner's phone. The system delivers these
/// messages only between an iPhone app and its own watch app, on a watch
/// paired with that phone.
final class PairingReceiver: NSObject, WCSessionDelegate {
    static let shared = PairingReceiver()
    /// Called on the main actor after a pairing has been saved.
    var onPaired: (@MainActor () -> Void)?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["path"] as? String == "/buzz/pair" else { return replyHandler(["paired": 0]) }
        #if DEBUG && targetEnvironment(simulator)
        // A simulator may use a development relay on the same Mac, which has no certificate.
        let allowInsecure = true
        #else
        let allowInsecure = false
        #endif
        let (pairings, active) = Pairing.parse(message: message, allowInsecure: allowInsecure)
        guard !pairings.isEmpty, PairingStore.save(pairings, active: active) else { return replyHandler(["paired": 0]) }
        replyHandler(["paired": pairings.count])
        let notify = onPaired
        Task { @MainActor in notify?() }
    }
}
