import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Every customer question, newest first, with unanswered ones marked.
/// Same repository call as the customer inbox -- RLS is what widens it
/// from "mine" to "everyone's".
class StaffChatInboxScreen extends StatefulWidget {
  const StaffChatInboxScreen({super.key});

  @override
  State<StaffChatInboxScreen> createState() => _StaffChatInboxScreenState();
}

class _StaffChatInboxScreenState extends State<StaffChatInboxScreen> {
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
    final viewerRole = context.read<AppAuthState>().profile?.role ?? UserRole.staff;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Customer Questions')),
      body: FutureBuilder<List<InquiryThread>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load messages.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final threads = snapshot.data ?? [];
          if (threads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forum_outlined, size: 48, color: context.colors.outline),
                    const SizedBox(height: AppSpacing.base),
                    Text('No customer questions yet', style: AppTextStyles.headlineSm),
                  ],
                ),
              ),
            );
          }

          final unanswered = threads.where((t) => t.awaitingReplyFrom(viewerRole)).length;

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              itemCount: threads.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.base),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.base),
                    child: Text(
                      unanswered == 0
                          ? 'All questions answered.'
                          : '$unanswered question${unanswered == 1 ? '' : 's'} waiting for a reply',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: unanswered == 0 ? context.colors.success : context.colors.primary,
                      ),
                    ),
                  );
                }

                final thread = threads[index - 1];
                final needsReply = thread.awaitingReplyFrom(viewerRole);

                return InkWell(
                  onTap: () => context
                      .push(
                        '/chat/${thread.customerId}/'
                        '${ChatThreadRoute.encode(thread.productId)}',
                        extra: thread.productName,
                      )
                      .then((_) => _reload()),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: needsReply ? context.colors.primary : context.colors.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${thread.customerName} · ${thread.productName}',
                                style: AppTextStyles.labelLg,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                thread.lastMessage,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySm.copyWith(
                                  color: needsReply
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
                            if (needsReply) ...[
                              const SizedBox(height: 4),
                              Icon(Icons.reply, size: 18, color: context.colors.primary),
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

/// One conversation from the shop's side.
class StaffChatThreadScreen extends StatelessWidget {
  const StaffChatThreadScreen({
    super.key,
    required this.customerId,
    required this.productId,
    required this.productName,
  });

  final String customerId;
  final String productId;
  final String productName;

  @override
  Widget build(BuildContext context) {
    final viewerRole = context.read<AppAuthState>().profile?.role ?? UserRole.staff;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text(productName)),
      body: SafeArea(
        child: InquiryThreadView(
          customerId: customerId,
          productId: ChatThreadRoute.decode(productId),
          viewerRole: viewerRole,
        ),
      ),
    );
  }
}
