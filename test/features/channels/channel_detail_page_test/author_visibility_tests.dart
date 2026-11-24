part of '../channel_detail_page_test.dart';

void messageAuthorVisibilityTests() {
  for (final dark in [false, true]) {
    for (final kind in [
      'dm',
      'solo',
      'group',
      'channel',
      'pair-channel',
      'unknown',
      'outsider',
      'stale-dm',
    ]) {
      testWidgets('message identity: $kind dark=$dark', (tester) async {
        final participants = kind == 'unknown'
            ? <String>[]
            : [
                'self',
                'alice',
                if (kind == 'group' || kind == 'channel' || kind == 'stale-dm')
                  'bob',
              ];
        final channel = Channel(
          id: _channelId,
          name: 'Conversation',
          channelType:
              kind == 'channel' || kind == 'pair-channel' || kind == 'solo'
              ? 'stream'
              : 'dm',
          labels: kind == 'solo' ? const ['buzz.solo'] : const [],
          visibility: 'private',
          description: '',
          createdBy: 'self',
          createdAt: DateTime(2025),
          memberCount: participants.length,
          participantPubkeys: participants,
          isMember: true,
        );
        final channels = _FakeChannelsNotifier([channel]);
        await tester.pumpWidget(
          _buildTestable(
            channel: channel,
            channelsNotifier: channels,
            personalChat: kind == 'solo',
            darkTheme: dark,
            signingPubkey: 'self',
            members: [
              for (final pubkey in participants.where(
                (key) => kind != 'stale-dm' || key != 'bob',
              ))
                ChannelMember(
                  pubkey: pubkey,
                  role: 'member',
                  joinedAt: DateTime(2025),
                ),
            ],
            users: const {
              'self': UserProfile(pubkey: 'self', displayName: 'Me'),
              'alice': UserProfile(pubkey: 'alice', displayName: 'Alice'),
              'bob': UserProfile(pubkey: 'bob', displayName: 'Bob'),
            },
            messages: [
              _textMsg(
                id: 'incoming',
                pubkey: kind == 'outsider' ? 'bob' : 'alice',
                content: List.filled(
                  6,
                  'A message that fills the available width.',
                ).join(' '),
              ),
              _textMsg(
                id: 'outgoing',
                pubkey: 'self',
                content: List.filled(
                  6,
                  'An outgoing message filling its width.',
                ).join(' '),
                createdAt: 1100,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final name = find.byKey(const ValueKey('message-author-incoming'));
        expect(name, findsOneWidget);
        expect(
          tester.widget<Text>(name).data,
          kind == 'outsider' ? 'Bob' : 'Alice',
        );
        final ownName = find.byKey(const ValueKey('message-author-outgoing'));
        expect(ownName, findsOneWidget);
        expect(tester.widget<Text>(ownName).data, 'Me');

        final incomingRow = find.byKey(const ValueKey('message-row-incoming'));
        final outgoingRow = find.byKey(const ValueKey('message-row-outgoing'));
        Finder avatars(Finder row) =>
            find.descendant(of: row, matching: find.byType(AvatarImage));
        expect(avatars(incomingRow), findsOneWidget);
        expect(avatars(outgoingRow), findsOneWidget);

        expect(
          find.byKey(const ValueKey('message-timestamp-incoming')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('message-timestamp-outgoing')),
          findsOneWidget,
        );
        final root = _textMsg(
          id: 'incoming',
          pubkey: kind == 'outsider' ? 'bob' : 'alice',
          content: List.filled(
            6,
            'A message that fills the available width.',
          ).join(' '),
        );
        unawaited(
          Navigator.of(tester.element(incomingRow)).push(
            MaterialPageRoute<void>(
              builder: (_) => ThreadDetailPage(
                threadHead: formatTimeline([root]).single,
                allMessages: formatTimeline([root]),
                channelId: _channelId,
                currentPubkey: 'self',
                isMember: true,
                isArchived: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final threadRow = find.byKey(
          const ValueKey('thread-message-row-incoming'),
        );
        expect(threadRow, findsOneWidget);
        expect(
          find.byKey(const ValueKey('thread-message-author-incoming')),
          findsOneWidget,
        );
        expect(avatars(threadRow), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
