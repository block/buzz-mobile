# Buzz for Wear OS (proof of concept)

A small standalone Wear OS app: talk to an agent in one of your channels from
your watch, by voice, keyboard or emoji. It connects to the relay on its own,
so it works with the phone out of reach.

It is a separate Gradle build from the Flutter app, in Kotlin and Compose for
Wear OS:

- `core/` is plain JVM Kotlin: Nostr event signing, the relay connection and
  signed media downloads. Its tests run without a device.
- `app/` is the watch app.

## How it signs in

The watch signs in as you. In a debug build of the phone app, Settings has
**Pair watch**: after you confirm, the phone sends the relay address and your
key to the watch over the Wear Data Layer. The system delivers that message
only to the same app, signed with the same certificate, on a watch paired
with the phone. The watch stores the key encrypted under a key held in the
Android Keystore.

A lost watch therefore holds your identity. Pair only a watch with a screen
lock. There is no unpair action yet; uninstalling the watch app removes the
key.

## Build and install

Needs JDK 21, the Android SDK and Gradle 9.

```sh
cd wear
gradle :core:test :app:assembleDebug
adb -s <watch> install -r app/build/outputs/apk/debug/app-debug.apk
```

The phone and watch apps must have the same application id. A phone debug
build from a git worktree carries an id suffix; pass the same one to the
watch build with `-PidSuffix=.<suffix>`.

## Not done yet

- Reconnecting on its own after the network drops (it reconnects when the app
  is reopened).
- Unpairing, and refusing to pair a watch that has no screen lock.
- Threads, reactions, sending media and video playback.
