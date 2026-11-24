import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A consistent inline author row for message-oriented surfaces.
class MessageAuthorMeta extends StatelessWidget {
  /// Primary author name shown at the start of the row.
  final String displayName;

  /// Optional secondary username, hidden when blank or equal to [displayName].
  final String? username;

  /// Timestamp label shown after the author metadata.
  final String timestamp;

  /// Whether metadata includes the timestamp alongside the author.
  final bool showTimestamp;

  /// Whether the name and username are visible.
  final bool showIdentity;

  /// Space before the timestamp when the author is visible.
  final double timestampGap;

  /// Color applied to [displayName].
  final Color nameColor;

  /// Color applied to the username and [timestamp].
  final Color metadataColor;

  /// Optional portrait shown beside [displayName].
  final Widget? avatar;

  /// Optional callback invoked when the author identity is tapped.
  final VoidCallback? onAuthorTap;

  /// Optional key assigned to the display-name text.
  final Key? displayNameKey;

  /// Optional key assigned to the username text.
  final Key? usernameKey;

  /// Optional key assigned to the timestamp text.
  final Key? timestampKey;

  /// Base text style for [displayName], with [nameColor] applied.
  final TextStyle nameStyle;

  /// Base text style for secondary metadata, with [metadataColor] applied.
  final TextStyle metadataStyle;

  /// Base text style for [timestamp], with [metadataColor] applied.
  final TextStyle timestampStyle;

  /// Mirrors metadata order without changing text reading direction.
  final bool reversed;

  /// Positions the metadata within the available message width.
  final MainAxisAlignment alignment;

  /// Creates an inline author row with optional username and tap handling.
  const MessageAuthorMeta({
    super.key,
    required this.displayName,
    required this.timestamp,
    required this.nameColor,
    required this.metadataColor,
    this.username,
    this.alignment = MainAxisAlignment.start,
    this.reversed = false,
    this.showTimestamp = true,
    this.showIdentity = true,
    this.timestampGap = Grid.xxs,
    this.avatar,
    this.onAuthorTap,
    this.displayNameKey,
    this.usernameKey,
    this.timestampKey,
    this.nameStyle = messageUsernameTextStyle,
    this.metadataStyle = messageMetadataTextStyle,
    this.timestampStyle = messageTimestampTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedUsername = username?.trim();
    final showUsername =
        normalizedUsername != null &&
        normalizedUsername.isNotEmpty &&
        normalizedUsername != displayName.trim();
    final resolvedNameStyle = nameStyle.copyWith(color: nameColor);
    final resolvedMetadataStyle = metadataStyle.copyWith(color: metadataColor);
    final resolvedTimestampStyle = timestampStyle.copyWith(
      color: metadataColor,
    );

    final name = Text(
      displayName,
      key: displayNameKey,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: resolvedNameStyle,
    );
    final portrait = avatar;
    final onTap = onAuthorTap;
    Widget identity = name;
    if (portrait != null) {
      identity = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: portrait),
          const SizedBox(width: Grid.half),
          Flexible(child: name),
        ],
      );
      if (onTap != null) {
        final minimum = Theme.of(context).platform == TargetPlatform.iOS
            ? 44.0
            : kMinInteractiveDimension;
        identity = Semantics(
          label: 'Open $displayName profile',
          button: true,
          onTap: onTap,
          excludeSemantics: true,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: Size.square(minimum),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: AlignmentDirectional.centerStart,
              padding: EdgeInsets.zero,
            ),
            child: identity,
          ),
        );
      }
    } else if (onTap != null) {
      identity = GestureDetector(onTap: onTap, child: name);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final metadataMaxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth / (showUsername ? 3 : 2)
            : double.infinity;

        final children = <Widget>[
          if (showIdentity) Flexible(child: identity),
          if (showIdentity && showUsername) ...[
            const SizedBox(width: Grid.half),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: metadataMaxWidth),
              child: Text(
                normalizedUsername,
                key: usernameKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: resolvedMetadataStyle,
              ),
            ),
          ],
          if (showTimestamp) ...[
            if (showIdentity) SizedBox(width: timestampGap),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: metadataMaxWidth),
              child: Text(
                timestamp,
                key: timestampKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: resolvedTimestampStyle,
              ),
            ),
          ],
        ];
        return Semantics(
          label: showIdentity ? null : displayName,
          child: Row(
            mainAxisAlignment: alignment,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: reversed ? children.reversed.toList() : children,
          ),
        );
      },
    );
  }
}
