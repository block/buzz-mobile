import CryptoKit
import XCTest
@testable import BuzzWatchCore

final class NostrTests: XCTestCase {
    func testDerivesTheBip340PublicKey() throws {
        // BIP-340 test vector 0: secret key 3.
        let key = try WatchKey(hex: "0000000000000000000000000000000000000000000000000000000000000003")
        XCTAssertEqual(key.pubkey, "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9")
    }

    func testRejectsAnUnusableKey() {
        XCTAssertThrowsError(try WatchKey(hex: String(repeating: "0", count: 64)))
        XCTAssertThrowsError(try WatchKey(hex: "abcd"))
        XCTAssertThrowsError(try WatchKey(hex: String(repeating: "z", count: 64)))
    }

    func testSignsEventsThatVerifyAndRejectsTampering() {
        let key = WatchKey.generate()
        let event = key.sign(kind: 9, tags: [["h", "channel"]], content: "line one\n\"quoted\" \\ tab\t é 🐝")
        XCTAssertTrue(verify(event))
        var edited = event
        edited.content += "!"
        XCTAssertFalse(verify(edited))
        var stolen = event
        stolen.pubkey = WatchKey.generate().pubkey
        XCTAssertFalse(verify(stolen))
    }

    func testComputesTheCanonicalEventId() throws {
        let key = try WatchKey(hex: "0000000000000000000000000000000000000000000000000000000000000003")
        let event = key.sign(kind: 1, tags: [["t", "a\"b"]], content: "hi\n", createdAt: 1_700_000_000)
        let expected = SHA256.hash(data: Data("[0,\"\(key.pubkey)\",1700000000,1,[[\"t\",\"a\\\"b\"]],\"hi\\n\"]".utf8))
        XCTAssertEqual(event.id, Data(expected).hex)
    }

    func testRoundTripsThroughRelayJson() throws {
        let event = WatchKey.generate().sign(kind: 9, tags: [["h", "c"], ["p", "x", "bot"]], content: "a \u{01} b")
        let parsed = NostrEvent(json: try JSONSerialization.jsonObject(with: Data(event.json.utf8)))
        XCTAssertEqual(parsed, event)
        XCTAssertNil(NostrEvent(json: ["id": "x"]))
    }
}

final class MediaTests: XCTestCase {
    private func event(_ tags: [[String]]) -> NostrEvent {
        NostrEvent(id: "", pubkey: "", createdAt: 0, kind: 9, tags: tags, content: "", sig: "")
    }

    func testReadsImagesAndVideosAndSkipsTheRest() {
        let found = attachments(event([
            ["imeta", "url https://r.example/media/a.png", "m image/png", "thumb https://r.example/media/a.thumb.jpg"],
            ["imeta", "url https://r.example/media/b.mp4", "m video/mp4", "image https://r.example/media/b.jpg", "duration 12.7"],
            ["imeta", "url https://r.example/media/voice.mp4", "m video/mp4", "filename voice-note-1.mp4"],
            ["imeta", "url https://r.example/media/c.pdf", "m application/pdf"],
            ["imeta", "m image/png"],
            ["h", "channel"],
        ]))
        XCTAssertEqual(found, [
            Attachment(url: "https://r.example/media/a.png", preview: "https://r.example/media/a.thumb.jpg", video: false, durationSeconds: nil),
            Attachment(url: "https://r.example/media/b.mp4", preview: "https://r.example/media/b.jpg", video: true, durationSeconds: 12),
        ])
    }

    func testSendsTheProofOnlyToTheRelaysOwnMedia() {
        let fetcher = MediaFetcher(relayURL: URL(string: "wss://Relay.Example")!, key: .generate())
        XCTAssertTrue(fetcher.isRelayMedia(URL(string: "https://relay.example/media/abc.png")!))
        XCTAssertTrue(fetcher.isRelayMedia(URL(string: "https://relay.example:443/media/abc.png")!))
        XCTAssertFalse(fetcher.isRelayMedia(URL(string: "https://relay.example/other/abc.png")!))
        XCTAssertFalse(fetcher.isRelayMedia(URL(string: "https://relay.example:8443/media/abc.png")!))
        XCTAssertFalse(fetcher.isRelayMedia(URL(string: "https://relay.example.evil.test/media/abc.png")!))
    }
}

final class PairingTests: XCTestCase {
    private let secret = "0000000000000000000000000000000000000000000000000000000000000003"

    func testReadsEachCommunityOnce() {
        let (pairings, active) = Pairing.parse(message: [
            "active": "wss://b.example",
            "communities": [
                ["name": "A", "relay": "wss://a.example", "secret": secret],
                ["relay": "wss://b.example", "secret": secret],
                ["name": "A again", "relay": "wss://a.example", "secret": secret],
                ["name": "Plain", "relay": "ws://c.example", "secret": secret],
                ["name": "Bad key", "relay": "wss://d.example", "secret": "00"],
            ],
        ])
        XCTAssertEqual(pairings.map(\.name), ["A", "b.example"])
        XCTAssertEqual(active, "wss://b.example")
    }

    func testAdmitsAnInsecureRelayOnlyWhenAsked() {
        let message: [String: Any] = ["relay": "ws://localhost:3000", "secret": secret]
        XCTAssertTrue(Pairing.parse(message: message).pairings.isEmpty)
        XCTAssertEqual(Pairing.parse(message: message, allowInsecure: true).pairings.map(\.relay), ["ws://localhost:3000"])
    }
}

final class MarkdownTests: XCTestCase {
    /// The text and its styles as `plain|bold|…` runs, to compare at a glance.
    private func runs(_ text: String) -> [String] {
        markdown(text).runs.map { run in
            let intent = run.inlinePresentationIntent ?? []
            var names = [String]()
            if intent.contains(.stronglyEmphasized) { names.append("bold") }
            if intent.contains(.emphasized) { names.append("italic") }
            if intent.contains(.code) { names.append("code") }
            if intent.contains(.strikethrough) { names.append("strike") }
            return String(markdown(text)[run.range].characters) + (names.isEmpty ? "" : "<" + names.joined(separator: ",") + ">")
        }
    }

    func testStylesEmphasisCodeAndLinks() {
        XCTAssertEqual(runs("a **b** *c* `d` ~~e~~ [f](https://x.test)"), ["a ", "b<bold>", " ", "c<italic>", " ", "d<code>", " ", "e<strike>", " f"])
        XCTAssertEqual(runs("**bold _both_**"), ["bold <bold>", "both<bold,italic>"])
    }

    func testLeavesSnakeCaseAndEscapesAlone() {
        XCTAssertEqual(runs("snake_case_name and 2 * 3 * 4"), ["snake_case_name and 2 * 3 * 4"])
        XCTAssertEqual(runs("snake\\_case"), ["snake_case"])
    }

    func testHandlesBlocksAndDropsInlinePictures() {
        XCTAssertEqual(runs("# Title\n- one\n  - two\n> said"), ["Title<bold>", "\n• one\n • two\n", "said<italic>"])
        XCTAssertEqual(runs("see ![shot](https://x.test/a.png) here"), ["see  here"])
        XCTAssertEqual(runs("```\nlet a = *b*\n```"), ["let a = *b*<code>"])
    }
}
