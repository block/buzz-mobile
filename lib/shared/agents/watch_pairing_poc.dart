import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nostr/nostr.dart' as nostr;

const _channel = MethodChannel('buzz/watch_pairing');

/// Names of the watches paired with this phone and in reach right now.
Future<List<String>> connectedWatches() async {
  final names = await _channel.invokeListMethod<String>('watches');
  return names ?? const [];
}

/// Proof of concept: makes the watch the same identity as this phone by
/// handing it [ownerNsec] and the relay to use. The key travels over the
/// system's phone-to-watch link, which delivers only to this app on a watch
/// paired with this phone. It never touches the relay.
Future<void> pairWatch({
  required String ownerNsec,
  required String relayWsUrl,
}) async {
  final payload = jsonEncode({
    'relay': relayWsUrl,
    'secret': nostr.Keys(ownerNsec).secret,
  });
  await _channel.invokeMethod<int>(
    'pair',
    Uint8List.fromList(utf8.encode(payload)),
  );
}
