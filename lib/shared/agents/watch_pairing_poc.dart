import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart' as nostr;

const _channel = MethodChannel('buzz/watch_pairing');

/// Names of the watches paired with this phone and in reach right now.
Future<List<String>> connectedWatches() async {
  final names = await _channel.invokeListMethod<String>('watches');
  return names ?? const [];
}

/// One community to put on the watch: its name, relay and the owner's key there.
typedef WatchCommunity = ({String name, String relayWsUrl, String ownerNsec});

/// Proof of concept: makes the watch the same identity as this phone in each
/// of [communities], by handing it the relay and the owner's key for each.
/// [activeRelayWsUrl] is the one the watch opens first. The keys travel over
/// the system's phone-to-watch link, which delivers only to this app on a
/// watch paired with this phone. They never touch a relay.
///
/// This replaces whatever the watch held before.
Future<void> pairWatch({
  required List<WatchCommunity> communities,
  required String activeRelayWsUrl,
}) async {
  final payload = jsonEncode({
    'active': activeRelayWsUrl,
    'communities': [
      for (final community in communities)
        {
          'name': community.name,
          'relay': community.relayWsUrl,
          'secret': nostr.Keys(community.ownerNsec).secret,
        },
    ],
  });
  await _channel.invokeMethod<int>(
    'pair',
    Uint8List.fromList(utf8.encode(payload)),
  );
}
