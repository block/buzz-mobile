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
**Pair watch**. It lists your communities, with only the one you are using
ticked. After you confirm, the phone sends the watch, for each ticked
community, its name, its relay address and your key there, over the Wear Data
Layer. The system delivers that message only to the same app, signed with the
same certificate, on a watch paired with the phone. The watch stores the keys
encrypted under a key held in the Android Keystore.

Pairing again replaces what the watch holds, so that is also how you add or
drop a community. With more than one on the watch, the top of the channel
list shows the current community; tap it to switch. The watch keeps one relay
connection at a time and remembers the last channel used in each community.

A lost watch therefore holds your identity in every community you put on it.
Pair only a watch with a screen lock. There is no unpair action yet;
uninstalling the watch app removes the keys.

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

## Icons

The watch draws the same Tabler icons as the phone app. `app/src/main/res/font/tabler_icons.ttf`
holds only the glyphs listed in `Icons.kt`, cut from the phone's `assets/fonts/TablerIcons.ttf`
(MIT, see `app/TABLER_ICONS_LICENSE.txt`). To add an icon, add its code point to `Icons.kt` and
to this command, then run it from `wear/`:

```sh
python3 -m venv /tmp/buzz-font-tools
/tmp/buzz-font-tools/bin/pip install fonttools==4.60.1
/tmp/buzz-font-tools/bin/pyftsubset ../assets/fonts/TablerIcons.ttf \
  --unicodes=eb55,ea5e,ea60,ea19,eaf0,eaf7,ebd6,eb16,ea5f \
  --no-hinting --name-IDs='*' \
  --output-file=app/src/main/res/font/tabler_icons.ttf
```
