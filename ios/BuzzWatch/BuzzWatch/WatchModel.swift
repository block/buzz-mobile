import BuzzWatchCore
import Foundation
import SwiftUI

/// Something to pick from a list: a community, a channel or an agent.
struct Choice: Identifiable, Hashable {
    let id: String
    let name: String
    var picture: String?
}

/// One message in the conversation.
struct Line: Identifiable {
    let id: String
    let mine: Bool
    let text: String
    let styled: AttributedString
    let media: [Attachment]
}

enum ConnectionStatus: Equatable {
    case notPaired, connecting, connected, disconnected
    case failed(String)
}

/// Everything the screens show, and the one relay connection behind it.
@MainActor
final class WatchModel: ObservableObject {
    @Published var status = ConnectionStatus.notPaired
    @Published var notice: String?
    @Published var lines: [Line] = []
    @Published var communities: [Choice] = []
    @Published var community: Choice?
    @Published var channels: [Choice] = []
    @Published var channel: Choice?
    @Published var agents: [Choice] = []
    @Published var agent: Choice?
    @Published var busy: String?
    @Published private(set) var media: MediaFetcher?

    private var pairing: Pairing?
    private var connection: RelayConnection?
    private var me = ""
    private var subscription: String?
    private var shown = Set<String>()
    private var working: [String: Date] = [:]
    private var expiry: Task<Void, Never>?
    /// Bumped on every (re)connect, so work started for an earlier one is dropped.
    private var generation = 0
    /// Bumped each time a channel is opened, so a slower earlier choice cannot win.
    private var opening = 0
    private var retry: Task<Void, Never>?
    private var failures = 0
    /// Whether the app is in front; it does not reconnect on its own otherwise.
    var active = true

    /// Nothing to show yet: the relay has not answered, or the first channel is still loading.
    var starting: Bool {
        channel == nil && (status == .connecting || (status == .connected && !channels.isEmpty))
    }

    var agentLabel: String { agent?.name ?? channel?.name ?? "Buzz" }

    func start() {
        PairingReceiver.shared.onPaired = { [weak self] in self?.reconnect() }
        PairingReceiver.shared.start()
        #if DEBUG && targetEnvironment(simulator)
        // For trying the app in a simulator with no phone: a pairing passed in
        // the environment (`SIMCTL_CHILD_BUZZ_WATCH_PAIR` with `simctl launch`).
        if let json = ProcessInfo.processInfo.environment["BUZZ_WATCH_PAIR"],
           let message = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            let (pairings, active) = Pairing.parse(message: message, allowInsecure: true)
            if !pairings.isEmpty { _ = PairingStore.save(pairings, active: active) }
        }
        #endif
        reconnect()
    }

    /// Called when the app comes back to the front.
    func resume() {
        active = true
        guard connection == nil else { return }
        switch status {
        case .disconnected, .failed: reconnect()
        default: break
        }
    }

    func reconnect() {
        let all = PairingStore.loadAll()
        guard let paired = PairingStore.load(), let url = URL(string: paired.relay), let key = try? WatchKey(hex: paired.secret) else {
            status = .notPaired
            return
        }
        retry?.cancel()
        generation += 1
        let attempt = generation
        let old = connection
        connection = nil
        subscription = nil
        pairing = paired
        communities = all.map { Choice(id: $0.relay, name: $0.name) }
        community = Choice(id: paired.relay, name: paired.name)
        status = .connecting
        notice = nil
        me = key.pubkey
        media = MediaFetcher(relayURL: url, key: key)
        Task {
            await old?.close()
            let relay = RelayConnection(relayURL: url, key: key) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == attempt else { return }
                    self.connection = nil
                    self.status = .disconnected
                    self.retryLater()
                }
            }
            do {
                try await relay.connect()
                guard generation == attempt else { return await relay.close() }
                connection = relay
                failures = 0
                let found = await myChannels(relay)
                guard generation == attempt else { return }
                let stored = PairingStore.channel(for: paired.relay)
                channels = found
                status = .connected
                if let first = found.first(where: { $0.id == stored }) ?? found.first(where: { $0.name == "watch" }) ?? found.first {
                    await load(relay, first, attempt)
                }
            } catch {
                await relay.close()
                guard generation == attempt else { return }
                status = .failed(error.localizedDescription)
                retryLater()
            }
        }
    }

    /// Try again shortly, waiting longer each time, while the app is in front.
    private func retryLater() {
        retry?.cancel()
        failures += 1
        let wait = UInt64(min(30, 1 << min(failures, 5))) * 1_000_000_000
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            guard !Task.isCancelled, let self, self.active, self.connection == nil else { return }
            self.reconnect()
        }
    }

    /// The channels this identity is a member of, by name.
    private func myChannels(_ relay: RelayConnection) async -> [Choice] {
        let ids = Array(Set(await relay.query(Filter(kinds: [39002]).tag("p", [me])).compactMap { $0.tag("d") }))
        if ids.isEmpty { return [] }
        let metadata = await relay.query(Filter(kinds: [39000]).tag("d", ids))
        return Dictionary(grouping: metadata) { $0.tag("d") ?? "" }
            .compactMap { id, versions -> Choice? in
                guard !id.isEmpty, let name = versions.max(by: { $0.createdAt < $1.createdAt })?.tag("name"),
                      !name.trimmingCharacters(in: .whitespaces).isEmpty
                else { return nil }
                return Choice(id: id, name: name)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func open(_ picked: Choice) {
        guard let relay = connection else { return }
        let attempt = generation
        Task { await load(relay, picked, attempt) }
    }

    /// Switch to another paired community; it opens on the channel last used there.
    func enter(_ picked: Choice) {
        guard picked.id != community?.id else { return }
        PairingStore.choose(picked.id)
        channel = nil
        channels = []
        agents = []
        agent = nil
        lines = []
        shown = []
        working = [:]
        refreshBusy()
        reconnect()
    }

    /// Switch the conversation to `picked`: its agents, its recent messages, then live ones.
    private func load(_ relay: RelayConnection, _ picked: Choice, _ attempt: Int) async {
        opening += 1
        let token = opening
        if let subscription { await relay.unsubscribe(subscription) }
        subscription = nil
        let members = (await relay.query(Filter(kinds: [39002]).tag("d", [picked.id]).limit(1)))
            .max { $0.createdAt < $1.createdAt }?.tags
            .filter { $0.count > 1 && $0[0] == "p" && $0[1] != me } ?? []
        // Agents carry the bot role. A channel that marks none still lets you
        // address whoever else is in it.
        let marked = members.filter { $0.count > 2 && $0[2] == "bot" }
        let bots = (marked.isEmpty ? members : marked).map { $0[1] }
        var profiles: [String: (name: String?, picture: String?)] = [:]
        if !bots.isEmpty {
            let found = await relay.query(Filter(kinds: [0]).authors(bots))
            for (pubkey, versions) in Dictionary(grouping: found, by: \.pubkey) {
                if let latest = versions.max(by: { $0.createdAt < $1.createdAt }) { profiles[pubkey] = Self.profile(latest) }
            }
        }
        let found = bots
            .map { Choice(id: $0, name: profiles[$0]?.name ?? String($0.prefix(8)) + "…", picture: profiles[$0]?.picture) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        let chosen = found.first { $0.id == PairingStore.agent(for: picked.id) } ?? found.first
        let history = (await relay.query(Filter(kinds: [9]).tag("h", [picked.id]).limit(10))).sorted { $0.createdAt < $1.createdAt }
        guard generation == attempt, opening == token else { return }
        if let pairing { PairingStore.setChannel(picked.id, for: pairing.relay) }
        channel = picked
        agents = found
        agent = chosen
        lines = []
        shown = []
        working = [:]
        refreshBusy()
        history.forEach(show)
        let live = try? await relay.subscribe(channel: picked.id) { [weak self] event in
            Task { @MainActor in
                guard let self, self.generation == attempt, self.channel?.id == picked.id else { return }
                self.show(event)
            }
        }
        if generation == attempt, opening == token {
            subscription = live
        } else if let live {
            await relay.unsubscribe(live)
        }
    }

    private func show(_ event: NostrEvent) {
        if event.kind == 20002 {
            // Agents repeat this every few seconds while they work.
            if event.pubkey != me {
                // Matches the phone app: an indicator lasts this long without a fresh signal.
                working[event.pubkey] = Date().addingTimeInterval(8)
                refreshBusy()
            }
            return
        }
        // A message from someone ends their indicator: the answer has arrived.
        if working.removeValue(forKey: event.pubkey) != nil { refreshBusy() }
        guard shown.insert(event.id).inserted else { return }
        let media = attachments(event)
        // The attachment is shown as a picture, so its address is dropped from the text.
        var text = event.content
        for item in media {
            let escaped = NSRegularExpression.escapedPattern(for: item.url)
            text = text.replacingOccurrences(of: "!\\[[^\\]]*\\]\\(\(escaped)\\)", with: "", options: .regularExpression)
                .replacingOccurrences(of: item.url, with: "")
        }
        append(id: event.id, mine: event.pubkey == me, text: text, media: media)
    }

    private func append(id: String, mine: Bool, text: String, media: [Attachment] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(Line(id: id, mine: mine, text: trimmed, styled: markdown(trimmed), media: media))
    }

    /// Recompute who is working, and keep checking until nobody is.
    private func refreshBusy() {
        expiry?.cancel()
        let now = Date()
        working = working.filter { $0.value > now }
        switch working.count {
        case 0: busy = nil
        case 1: busy = (agents.first { $0.id == working.keys.first }?.name ?? "Someone") + " is working"
        default: busy = "\(working.count) are working"
        }
        if !working.isEmpty {
            expiry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled { self?.refreshBusy() }
            }
        }
    }

    func choose(_ picked: Choice) {
        agent = picked
        if let channel { PairingStore.setAgent(picked.id, for: channel.id) }
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let relay = connection, let target = channel else { return }
        // Agents answer only when mentioned, so each message mentions the chosen one.
        let mention = agent.map { [["p", $0.id]] } ?? []
        notice = nil
        Task {
            do {
                let id = try await relay.sendMessage(channel: target.id, text: text, extraTags: mention)
                if shown.insert(id).inserted, channel?.id == target.id { append(id: id, mine: true, text: text) }
            } catch {
                notice = "Not sent: \(error.localizedDescription)"
            }
        }
    }

    /// A profile's display name and picture address, where it has them.
    private static func profile(_ event: NostrEvent) -> (name: String?, picture: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: Data(event.content.utf8)) as? [String: Any] else { return (nil, nil) }
        func text(_ key: String) -> String? {
            (json[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        return (text("display_name") ?? text("name"), text("picture"))
    }
}
