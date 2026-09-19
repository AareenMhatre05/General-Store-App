import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product_inquiry.dart';
import '../models/user_role.dart';
import '../repositories/chat_repository.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// One customer↔product conversation: live message list plus composer.
///
/// Shared by both apps because the conversation is genuinely the same
/// thing from either end -- only [viewerRole] differs, which decides
/// which side each bubble sits on and what role new messages are sent
/// as.
class InquiryThreadView extends StatefulWidget {
  const InquiryThreadView({
    super.key,
    required this.customerId,
    this.productId,
    required this.viewerRole,
  });

  final String customerId;

  /// Null for the general conversation with the shop, which a customer
  /// can start from the Chat tab without opening a product first.
  final String? productId;
  final UserRole viewerRole;

  @override
  State<InquiryThreadView> createState() => _InquiryThreadViewState();
}

class _InquiryThreadViewState extends State<InquiryThreadView> {
  final _messageController = TextEditingController();
  bool _isSending = false;

  /// Held rather than built in `build`. Creating the stream inline meant
  /// every setState -- including the two around sending -- tore down the
  /// subscription and opened a new one. Re-subscribing at the exact
  /// moment of an insert is what made a sent message appear twice: the
  /// fresh snapshot already contained it, and the realtime event for it
  /// then arrived on top.
  late Stream<List<ProductInquiry>> _messages;

  @override
  void initState() {
    super.initState();
    _messages = _openStream();
  }

  @override
  void didUpdateWidget(InquiryThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the conversation itself changes.
    if (oldWidget.customerId != widget.customerId ||
        oldWidget.productId != widget.productId) {
      _messages = _openStream();
    }
  }

  Stream<List<ProductInquiry>> _openStream() =>
      context.read<ChatRepository>().streamMessages(
            customerId: widget.customerId,
            productId: widget.productId,
          );

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chatRepository = context.read<ChatRepository>();
    setState(() => _isSending = true);
    try {
      await chatRepository.sendMessage(
        customerId: widget.customerId,
        productId: widget.productId,
        senderRole: widget.viewerRole,
        message: text,
      );
      _messageController.clear();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  bool _isMine(ProductInquiry message) => widget.viewerRole == UserRole.customer
      ? message.senderRole == UserRole.customer
      : message.senderRole != UserRole.customer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ProductInquiry>>(
            stream: _messages,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? [];
              if (messages.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.gutter),
                    child: Text(
                      widget.viewerRole == UserRole.customer
                          ? (widget.productId == null
                              ? 'Ask the shop anything, or request a '
                                  'personalised order.'
                              : 'Ask anything about this product.')
                          : 'No messages in this conversation yet.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySm
                          .copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                );
              }

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  // The stream is oldest-first; reverse: true keeps the
                  // newest message pinned at the bottom without having
                  // to scroll programmatically on every update.
                  final message = messages[messages.length - 1 - index];
                  final mine = _isMine(message);

                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.base),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.containerPaddingMobile,
                        vertical: AppSpacing.base,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: mine
                            ? context.colors.primaryContainer
                            : context.colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.message,
                            style: AppTextStyles.bodyMd.copyWith(
                              color: mine
                                  ? context.colors.onPrimaryContainer
                                  : context.colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _timeLabel(message.createdAt.toLocal()),
                            style: AppTextStyles.labelMd.copyWith(
                              color: mine
                                  ? context.colors.onPrimaryContainer.withValues(alpha: 0.7)
                                  : context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.containerPaddingMobile,
            right: AppSpacing.containerPaddingMobile,
            top: AppSpacing.base,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.base,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Type a message...'),
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              IconButton.filled(
                onPressed: _isSending ? null : _send,
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _timeLabel(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }
}
