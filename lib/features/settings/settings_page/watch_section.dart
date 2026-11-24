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

/// See [pairWatch]. Names the watch and asks before the key leaves the phone.
Future<void> _pairWatch(BuildContext context, WidgetRef ref) async {
  final config = ref.read(relayConfigProvider);
  final nsec = config.nsec;
  if (nsec == null || nsec.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  void report(String message, {required bool ok}) =>
      messenger.showFeedbackSnackBar(
        SnackBar(content: Text(message)),
        kind: ok ? ToastKind.success : ToastKind.error,
      );
  List<String> watches;
  try {
    watches = await connectedWatches();
  } on Object catch (error) {
    report('Could not look for a watch: $error', ok: false);
    return;
  }
  if (watches.isEmpty) {
    report('No watch is connected to this phone.', ok: false);
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Pair ${watches.join(', ')}?'),
      content: const Text(
        'Your watch will sign in as you. This copies your key to the watch. '
        'Only pair a watch you own and that has a screen lock.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Pair'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await pairWatch(ownerNsec: nsec, relayWsUrl: config.wsUrl);
    report('Watch paired. Open Buzz on your watch.', ok: true);
  } on Object catch (error) {
    report('Pairing failed: $error', ok: false);
  }
}
