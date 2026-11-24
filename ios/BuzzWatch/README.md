# Buzz for Apple Watch (proof of concept)

The Apple Watch counterpart of the Wear OS app in [`wear/`](../../wear/README.md): the same flows and look, written in SwiftUI. Talk to your agents from your wrist, as yourself.

- **Connecting:** the Buzz bees fly while the watch reaches the relay.
- **Conversation:** the channel is pinned on top (tap to change it), messages below with markdown, pictures and a "working" line while an agent is busy, and one button to start a message.
- **Starting a message:** pick the agent, then an emoji, the microphone or the keyboard. The microphone and the keyboard both open the watch's own text entry, which offers dictation, the keyboard and scribble; its Done button is the single confirmation, and the message is sent.
- **Pickers:** channels, agents, and communities when the watch holds more than one. The watch remembers the last community, the channel per community and the agent per channel.
- **Back:** the system back button and edge swipe.

## Layout

| Path | What |
|------|------|
| `ios/BuzzWatchCore/` | Swift package with no UI: event signing and checking, the relay connection, media downloads, pairing parsing, markdown. Tested on a Mac with `swift test`. |
| `ios/BuzzWatch/BuzzWatch/` | The watch app. |
| `ios/BuzzWatch/BuzzWatch.xcodeproj` | Its own Xcode project, so the phone app's project and release builds do not change. |
| `ios/BuzzWatch/embed-watch-app.sh` | Opt-in build step of the phone app that puts the watch app inside it. |
| `ios/Runner/WatchPairingPlugin.swift` | The phone side of pairing (debug builds only). |

## Pairing

As on Android: in a debug build of the phone app, Settings, then **Pair watch**. Open Buzz on the watch first. The phone hands over each ticked community's relay and your key for it through WatchConnectivity, which delivers only to this app's own watch app on a watch paired with this phone. It is sent as a live message, which the system does not queue or store on the way. The watch keeps the pairings in its Keychain (this device only, readable after first unlock) and nowhere else.

The watch accepts only `wss://` relays. A debug build running in a simulator also accepts `ws://`, for a development relay on the same Mac.

## Building

The phone and the watch app only see each other when the watch app is inside the phone app. To get that, add this line to `ios/Flutter/AppOverrides.xcconfig` (gitignored), then build the phone app as usual:

```
BUZZ_EMBED_WATCH_APP = YES
```

The build step then builds the watch app with the phone app's bundle identifier, team and version, and copies it to `Runner.app/Watch/`. Without the line the step does nothing. Pairing exists only in debug builds of the phone app, so embed the watch app in those.

In simulators, pair a watch with a phone (`xcrun simctl pair <watch> <phone>`), install the phone app on the phone and `Runner.app/Watch/BuzzWatch.app` on the watch.

To work on the watch app alone, open `ios/BuzzWatch/BuzzWatch.xcodeproj`. A debug build in a simulator takes a pairing from the environment, so no phone is needed:

```
SIMCTL_CHILD_BUZZ_WATCH_PAIR='{"relay":"ws://127.0.0.1:8080","secret":"<64 hex characters>","name":"Local"}' \
  xcrun simctl launch <watch> xyz.block.buzz.dev.mobile.watchkitapp
```

## Icons

The watch uses the phone's Tabler icons from a small font holding only the glyphs it shows, the same file as the Wear OS app. [`wear/README.md`](../../wear/README.md) says how to add one.

## Not done

- It has run only in simulators. Signing and installing on a real Apple Watch is untried.
- A real watch may refuse the relay connection. Apple's technote TN3135 restricts WebSocket connections on watchOS to apps that are streaming audio or on a call, and the simulator does not enforce it. If so, the watch would have to reach the relay through the phone instead. This is the first thing to check on a device.
- Videos show their preview frame and length but do not play.
- No notifications, complications or background refresh: the watch talks to the relay only while the app is open.
