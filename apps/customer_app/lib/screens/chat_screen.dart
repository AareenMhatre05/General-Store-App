import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Inbox of the customer's own product conversations. RLS scopes
/// [ChatRepository.getThreads] to them, so no filtering is needed here.
class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  late Future<List<InquiryThread>> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = context.read<ChatRepository>().getThreads();
  }

  Future<void> _reload() async {
    setState(() => _loadFuture = context.read<ChatRepository>().getThreads());
    await _loadFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Chat')),
      body: FutureBuilder<List<InquiryThread>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load your messages.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final threads = snapshot.data ?? [];
          final hasGeneral = threads.any((t) => t.productId == null);
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              // +1 for the shop conversation, which is always offered even
              // before a first message exists -- the whole point is that a
              // customer can start talking without opening a product.
              itemCount: threads.length + (hasGeneral ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.base),
              itemBuilder: (context, index) {
                if (!hasGeneral && index == 0) {
                  return _StartShopChatTile(
                    onTap: () => context
                        .push('/chat/general', extra: 'Chat with the shop')
                        .then((_) => _reload()),
                  );
                }
                final thread = threads[index - (hasGeneral ? 0 : 1)];
                final theirTurn = thread.awaitingReplyFrom(UserRole.customer);

                return InkWell(
                  onTap: () => context
                      .push('/chat/${ChatThreadRoute.encode(thread.productId)}',
                          extra: thread.productName)
                      .then((_) => _reload()),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: theirTurn ? context.colors.primary : context.colors.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(thread.productName, style: AppTextStyles.labelLg),
                              const SizedBox(height: 4),
                              Text(
                                thread.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySm.copyWith(
                                  color: theirTurn
                                      ? context.colors.onSurface
                                      : context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.base),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('d MMM').format(thread.lastMessageAt.toLocal()),
                              style: AppTextStyles.labelMd
                                  .copyWith(color: context.colors.onSurfaceVariant),
                            ),
                            if (theirTurn) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                ),
                                child: Text(
                                  'Replied',
                                  style: AppTextStyles.labelMd
                                      .copyWith(color: context.colors.onPrimaryContainer),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// One conversation, opened from the inbox. The customer is always
/// themselves, so only the product needs identifying.
class ChatThreadScreen extends StatelessWidget {
  const ChatThreadScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  final String productId;
  final String productName;

  @override
  Widget build(BuildContext context) {
    final customerId = context.read<AppAuthState>().profile!.id;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text(productName)),
      body: SafeArea(
        child: InquiryThreadView(
          customerId: customerId,
          // The route uses the literal 'general' for the shop-wide
          // conversation, which the repository represents as a null
          // product.
          productId: ChatThreadRoute.decode(productId),
          viewerRole: UserRole.customer,
        ),
      ),
    );
  }
}


/// Offered even with no messages yet: a customer should be able to ask
/// the shop something without first finding a product to hang the
/// question on.
class _StartShopChatTile extends StatelessWidget {
  const _StartShopChatTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
        decoration: BoxDecoration(
          color: context.colors.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Icon(Icons.storefront, color: context.colors.onPrimaryContainer),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chat with the shop',
                    style: AppTextStyles.labelLg
                        .copyWith(color: context.colors.onPrimaryContainer),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ask for anything, or request a personalised order',
                    style: AppTextStyles.bodySm
                        .copyWith(color: context.colors.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.colors.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}
