import 'package:flutter/material.dart';

import '../../shared/profile/user_profile.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/avatar_image.dart';
import '../../shared/widgets/message_author_meta.dart';
import 'date_formatters.dart';
import 'timeline_message.dart';

/// The profile control and metadata at the start of a conversation message group.
class MessageSenderByline extends StatelessWidget {
  const MessageSenderByline({
    super.key,
    required this.keyPrefix,
    required this.message,
    required this.displayName,
    required this.username,
    required this.profile,
    required this.isAgent,
    required this.onOpenProfile,
  });

  final String keyPrefix;
  final TimelineMessage message;
  final String displayName;
  final String? username;
  final UserProfile? profile;
  final bool isAgent;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    const size = 16.0;
    final initial =
        profile?.initial ??
        (message.pubkey.isNotEmpty ? message.pubkey[0].toUpperCase() : '?');
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: Grid.xs,
        bottom: Grid.quarter,
      ),
      child: MessageAuthorMeta(
        avatar: AvatarImage(
          imageUrl: profile?.avatarUrl,
          radius: size / 2,
          backgroundColor: context.controlSurface,
          fallback: Text(
            initial,
            style: TextStyle(
              fontSize: size / 2,
              fontWeight: FontWeight.w600,
              color: context.colors.onPrimaryContainer,
            ),
          ),
          isAgent: isAgent,
        ),
        displayName: displayName,
        username: username,
        timestamp: formatMessageTime(message.createdAt),
        timestampGap: Grid.half,
        nameStyle: messageUsernameTextStyle.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 11,
          height: 17 / 11,
        ),
        metadataStyle: messageMetadataTextStyle.copyWith(
          fontSize: 11,
          height: 17 / 11,
        ),
        timestampStyle: messageTimestampTextStyle.copyWith(
          fontSize: 11,
          height: 17 / 11,
        ),
        nameColor: context.tertiaryTextColor,
        metadataColor: context.tertiaryTextColor,
        onAuthorTap: onOpenProfile,
        displayNameKey: ValueKey('$keyPrefix-author-${message.id}'),
        usernameKey: ValueKey('$keyPrefix-username-${message.id}'),
        timestampKey: ValueKey('$keyPrefix-timestamp-${message.id}'),
      ),
    );
  }
}
