import BuzzWatchCore
import SwiftUI

enum Route: Hashable {
    case channels, communities, compose, agents, emoji
    case picture(String)
}

struct RootView: View {
    @EnvironmentObject private var model: WatchModel
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.starting {
                    Connecting()
                } else {
                    Conversation(path: $path)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .channels:
                    Picker(
                        title: "Channel", choices: model.channels, selected: model.channel?.id,
                        switcher: model.communities.count > 1 ? model.community?.name : nil,
                        onSwitch: { path.append(.communities) }
                    ) {
                        model.open($0)
                        path = []
                    }
                case .communities:
                    Picker(title: "Community", choices: model.communities, selected: model.community?.id) {
                        model.enter($0)
                        path = []
                    }
                case .agents:
                    Picker(title: "Talk to", choices: model.agents, selected: model.agent?.id, pictures: true) {
                        model.choose($0)
                        path.removeLast()
                    }
                case .compose: Chooser(path: $path)
                case .emoji: EmojiGrid { send($0) }
                case .picture(let url): FullPicture(url: url)
                }
            }
        }
        // Leaving a community leaves whatever was open in it.
        .onChange(of: model.community) { _, _ in path = [] }
    }

    private func send(_ text: String) {
        model.send(text)
        path = []
    }
}

/// The conversation: the channel pinned on top, the messages, and the button that starts a message.
private struct Conversation: View {
    @Binding var path: [Route]
    @EnvironmentObject private var model: WatchModel

    private var connected: Bool { model.status == .connected }

    private var statusText: String {
        switch model.status {
        case .notPaired: "Not paired"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .failed(let why): "Can't connect: \(why)"
        }
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if let problem = model.notice ?? (connected ? nil : statusText) {
                        Text(problem).font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    if model.lines.isEmpty, connected || model.status == .notPaired {
                        Text(model.status == .notPaired ? "On your phone, open Buzz, then Settings, then Pair watch" : "Ask your agent")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                    ForEach(model.lines) { line in
                        Bubble(line: line) { path.append(.picture($0)) }
                    }
                    if let busy = model.busy {
                        Text("\(busy)…").font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 4)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.lines.count) { _, _ in withAnimation { scroll.scrollTo("end", anchor: .bottom) } }
            .onChange(of: model.busy) { _, _ in withAnimation { scroll.scrollTo("end", anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) {
            Button { path.append(.compose) } label: { RoundIcon(icon: .mic, primary: true, size: 44) }
                .buttonStyle(.plain)
                .disabled(!connected || model.channel == nil)
                .opacity(connected && model.channel != nil ? 1 : 0.4)
                .accessibilityLabel("Write a message")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { path.append(.channels) } label: {
                    HStack(spacing: 2) {
                        Text(model.channel?.name ?? "Buzz").font(.footnote.weight(.semibold)).lineLimit(1)
                        BuzzIcon.chevronDown.glyph(size: 12)
                    }
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.channels.isEmpty && model.communities.count < 2)
                .accessibilityLabel("\(model.channel?.name ?? "Buzz"). \(statusText)")
                .accessibilityHint("Change channel")
            }
        }
    }
}

private struct Bubble: View {
    let line: Line
    let onView: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(line.media, id: \.self) { item in Thumbnail(item: item, onView: onView) }
            if !line.text.isEmpty {
                Text(line.styled).font(.footnote).foregroundStyle(line.mine ? Color.black : Color.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(line.mine ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: line.mine ? .trailing : .leading)
        .padding(line.mine ? .leading : .trailing, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((line.mine ? "You: " : "Agent: ") + line.text)
    }
}

/// A picture in a message; a video shows its preview frame and length, and does not play.
private struct Thumbnail: View {
    let item: Attachment
    let onView: (String) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePicture(url: item.preview ?? (item.video ? nil : item.url), maxSide: 320) { $0.resizable().scaledToFill() }
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .background(Color.black)
            if item.video {
                Text("▶" + (item.durationSeconds.map { String(format: "  %d:%02d", $0 / 60, $0 % 60) } ?? ""))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { if !item.video { onView(item.url) } }
        .accessibilityLabel(item.video ? "Video" : "Picture")
        .accessibilityAddTraits(item.video ? [] : .isButton)
    }
}

private struct FullPicture: View {
    let url: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
            Text("Loading…").foregroundStyle(Theme.muted)
            RemotePicture(url: url, maxSide: 800) { $0.resizable().scaledToFit() }
        }
        .ignoresSafeArea()
        .onTapGesture { dismiss() }
        .accessibilityLabel("Picture")
        .accessibilityHint("Close")
    }
}

/// A list to pick one thing from. `switcher` names the community, on the row that changes it.
private struct Picker: View {
    let title: String
    let choices: [Choice]
    let selected: String?
    var pictures = false
    var switcher: String?
    var onSwitch: () -> Void = {}
    let onPick: (Choice) -> Void

    var body: some View {
        List {
            if let switcher {
                Button(action: onSwitch) {
                    HStack {
                        Text(switcher).lineLimit(1)
                        Spacer()
                        BuzzIcon.chevronDown.glyph(size: 14)
                    }
                    .foregroundStyle(Theme.muted)
                }
                .accessibilityLabel("Community: \(switcher). Change")
            }
            ForEach(choices) { choice in
                Button { onPick(choice) } label: {
                    HStack(spacing: 8) {
                        if pictures { Avatar(choice: choice, size: 26) }
                        Text(choice.name).lineLimit(1)
                    }
                    .foregroundStyle(choice.id == selected ? Color.black : Color.white)
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 18).fill(choice.id == selected ? Theme.primary : Theme.surface))
                .accessibilityAddTraits(choice.id == selected ? .isSelected : [])
            }
        }
        .navigationTitle(title)
    }
}

/// How to answer: an emoji, speaking, or typing; and who it goes to.
private struct Chooser: View {
    @Binding var path: [Route]
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        VStack(spacing: 10) {
            Button { path.append(.agents) } label: {
                HStack(spacing: 6) {
                    if model.agent != nil { Avatar(choice: model.agent, size: 22) }
                    Text(model.agentLabel).font(.footnote.weight(.semibold)).lineLimit(1)
                    if model.agents.count > 1 { BuzzIcon.chevronDown.glyph(size: 12) }
                }
                .padding(.leading, model.agent == nil ? 10 : 4)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .background(Theme.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.agents.count < 2)
            .accessibilityLabel("To \(model.agentLabel)")
            .accessibilityHint(model.agents.count > 1 ? "Change agent" : "")

            HStack(spacing: 8) {
                Button { path.append(.emoji) } label: { RoundIcon(icon: .smile, size: 46) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Emoji")
                // The watch's own text entry is the single confirmation: its
                // Done sends. It offers dictation, the keyboard and scribble.
                TextFieldLink(prompt: Text("To \(model.agentLabel)")) {
                    RoundIcon(icon: .mic, primary: true, size: 54)
                } onSubmit: { send($0) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Speak")
                TextFieldLink(prompt: Text("To \(model.agentLabel)")) {
                    RoundIcon(icon: .keyboard, size: 46)
                } onSubmit: { send($0) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Keyboard")
            }
        }
    }

    private func send(_ text: String) {
        model.send(text)
        path = []
    }
}

private let emojis = ["👍", "👎", "🙏", "😂", "❤️", "🎉", "👀", "🤔", "✅", "❌", "🔥", "😅"]

private struct EmojiGrid: View {
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(emojis, id: \.self) { emoji in
                    Button { onPick(emoji) } label: {
                        Text(emoji).font(.title3).frame(maxWidth: .infinity, minHeight: 44).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Emoji")
    }
}
