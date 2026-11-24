part of '../settings_page.dart';

/// Proof of concept, shown in debug builds only: pairs a Wear OS watch.
class _WatchSection extends ConsumerWidget {
  const _WatchSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppListCard(
    verticalPadding: Grid.twelve,
    children: [
      AppListRow(
        key: const ValueKey('settings-watch-pair'),
        title: 'Pair watch',
        subtitle: 'Proof of concept: sign in on your watch as you',
        onTap: () => _pairWatch(context, ref),
      ),
    ],
  );
}

/// See [pairWatch]. Names the watch and asks which communities to put on it
/// before any key leaves the phone.
Future<void> _pairWatch(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void report(String message, {required bool ok}) =>
      messenger.showFeedbackSnackBar(
        SnackBar(content: Text(message)),
        kind: ok ? ToastKind.success : ToastKind.error,
      );
  final active = ref.read(relayConfigProvider);
  final List<WatchCommunity> offered;
  List<String> watches;
  try {
    final saved = await ref.read(communityListProvider.future);
    offered = [for (final community in saved) ?_watchCommunity(community)];
    watches = await connectedWatches();
  } on Object catch (error) {
    report('Could not look for a watch: $error', ok: false);
    return;
  }
  if (offered.isEmpty) {
    report('No community here can be put on a watch.', ok: false);
    return;
  }
  if (watches.isEmpty) {
    report('No watch is connected to this phone.', ok: false);
    return;
  }
  if (!context.mounted) return;
  final chosen = await showDialog<List<WatchCommunity>>(
    context: context,
    builder: (context) => _PairWatchDialog(
      watches: watches,
      offered: offered,
      activeRelayWsUrl: active.wsUrl,
    ),
  );
  if (chosen == null || chosen.isEmpty) return;
  try {
    await pairWatch(
      communities: chosen,
      activeRelayWsUrl:
          chosen.any((community) => community.relayWsUrl == active.wsUrl)
          ? active.wsUrl
          : chosen.first.relayWsUrl,
    );
    report('Watch paired. Open Buzz on your watch.', ok: true);
  } on Object catch (error) {
    report('Pairing failed: $error', ok: false);
  }
}

/// [community] as the watch needs it, or null when the watch could not use
/// it: no key on this phone, or a relay without a secure address.
WatchCommunity? _watchCommunity(Community community) {
  final nsec = community.nsec?.trim();
  if (community.accountSyncRemoved || nsec == null || nsec.isEmpty) return null;
  final wsUrl = RelayConfig(baseUrl: community.relayUrl, nsec: nsec).wsUrl;
  if (!wsUrl.startsWith('wss://')) return null;
  return (name: community.name, relayWsUrl: wsUrl, ownerNsec: nsec);
}

/// Which communities to put on the watch. Only the one in use starts ticked,
/// so no other key leaves the phone unless the owner asks for it.
class _PairWatchDialog extends HookWidget {
  final List<String> watches;
  final List<WatchCommunity> offered;
  final String activeRelayWsUrl;

  const _PairWatchDialog({
    required this.watches,
    required this.offered,
    required this.activeRelayWsUrl,
  });

  @override
  Widget build(BuildContext context) {
    final ticked = useState(<String>{
      for (final community in offered)
        if (community.relayWsUrl == activeRelayWsUrl) community.relayWsUrl,
    });
    return AlertDialog(
      title: Text('Pair ${watches.join(', ')}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your watch will sign in as you in the communities you tick. '
              'This copies your key for each one to the watch, and replaces '
              'what the watch had. Only pair a watch you own and that has a '
              'screen lock.',
            ),
            const SizedBox(height: Grid.twelve),
            for (final community in offered)
              CheckboxListTile(
                key: ValueKey('pair-watch-${community.relayWsUrl}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(community.name),
                value: ticked.value.contains(community.relayWsUrl),
                onChanged: (value) => ticked.value = {
                  ...ticked.value.where((url) => url != community.relayWsUrl),
                  if (value ?? false) community.relayWsUrl,
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: ticked.value.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                  for (final community in offered)
                    if (ticked.value.contains(community.relayWsUrl)) community,
                ]),
          child: const Text('Pair'),
        ),
      ],
    );
  }
}
