import 'package:flutter/material.dart';
import '../../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatEntry entry;
  const MessageBubble({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final isUser = entry.isUser;
    final theme  = Theme.of(context);
    final cs     = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) _avatar(cs, isUser),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? cs.primaryContainer
                    : entry.isError
                        ? cs.errorContainer
                        : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Text(
                entry.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isUser
                      ? cs.onPrimaryContainer
                      : entry.isError
                          ? cs.onErrorContainer
                          : cs.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isUser) _avatar(cs, isUser),
        ],
      ),
    );
  }

  Widget _avatar(ColorScheme cs, bool isUser) {
    return CircleAvatar(
      radius: 16,
      backgroundColor:
          isUser ? cs.primary : cs.secondaryContainer,
      child: Icon(
        isUser ? Icons.person : Icons.auto_awesome,
        size: 16,
        color: isUser ? cs.onPrimary : cs.onSecondaryContainer,
      ),
    );
  }
}
