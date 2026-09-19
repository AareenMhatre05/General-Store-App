import '../models/product_inquiry.dart';
import '../models/user_role.dart';
import '../supabase/supabase_bootstrap.dart';

/// How a thread's product id survives a trip through a URL.
///
/// The general conversation with the shop has no product, and a route
/// path parameter cannot be null. Both apps invented their own answer to
/// that and disagreed: the customer app used a 'general' sentinel, while
/// the staff app interpolated the null straight into the path, which
/// Dart renders as the literal string "null". That matched no message,
/// so every general conversation opened blank on the shop's side.
///
/// One definition, used by both, so they cannot drift again.
abstract final class ChatThreadRoute {
  static const generalSentinel = 'general';

  /// Product id as it should appear in a path segment.
  static String encode(String? productId) => productId ?? generalSentinel;

  /// The reverse: back to a real product id, or null for the general
  /// conversation. Treats "null" as general too, so links created by the
  /// old buggy build still open the right thread.
  static String? decode(String segment) =>
      (segment == generalSentinel || segment == 'null') ? null : segment;
}

/// One customer↔product conversation, summarised for an inbox list.
class InquiryThread {
  const InquiryThread({
    required this.customerId,
    required this.productId,
    required this.productName,
    required this.customerName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastSenderRole,
    required this.messageCount,
  });

  final String customerId;

  /// Null for the general conversation with the shop.
  final String? productId;
  final String productName;
  final String customerName;
  final String lastMessage;
  final DateTime lastMessageAt;
  final UserRole lastSenderRole;
  final int messageCount;

  /// True when the other side spoke last, i.e. it's your turn. Staff use
  /// this to spot unanswered questions; customers to spot replies.
  bool awaitingReplyFrom(UserRole viewerRole) =>
      viewerRole == UserRole.customer
          ? lastSenderRole != UserRole.customer
          : lastSenderRole == UserRole.customer;
}

/// Pre-purchase Q&A between a customer and staff about a specific
/// product (the "Chat for Personalized Order" feature).
class ChatRepository {
  /// Live-updating list of messages for one customer/product thread,
  /// oldest first. Emits an initial snapshot immediately, then updates
  /// as new messages arrive.
  /// [productId] null selects the general conversation with the shop --
  /// the one started from the Chat tab without opening a product first.
  Stream<List<ProductInquiry>> streamMessages({
    required String customerId,
    String? productId,
  }) {
    return supabase
        .from('product_inquiries')
        .stream(primaryKey: ['id'])
        .eq('customer_id', customerId)
        // `ascending` is REQUIRED here. On a stream, order() defaults to
        // *descending* -- the opposite of the postgrest builder people
        // expect -- which handed the view newest-first while it assumed
        // oldest-first, so new messages appeared at the top.
        .order('created_at', ascending: true)
        .map((rows) {
          // Deduplicate by id. The stream's cache appends realtime
          // INSERTs without checking whether the row is already in the
          // snapshot it fetched, so a message sent while the stream is
          // (re)subscribing can land in the list twice.
          final seen = <String>{};
          return rows
              .where((row) => row['product_id'] == productId)
              .where((row) => seen.add(row['id'] as String))
              .map(ProductInquiry.fromJson)
              .toList();
        });
  }

  /// Every conversation the caller can see, newest activity first.
  ///
  /// RLS decides the scope: a customer gets only their own threads, a
  /// staff member gets all of them -- so both inboxes are this one
  /// method. Grouping happens client-side because the message volume
  /// for a single shop is small, and a `distinct on` view would have to
  /// be maintained for no practical gain.
  Future<List<InquiryThread>> getThreads() async {
    final rows = await supabase
        .from('product_inquiries')
        .select('*, products(name), profiles(full_name)')
        .order('created_at', ascending: false)
        .limit(500);

    final threads = <String, InquiryThread>{};
    for (final row in rows) {
      final customerId = row['customer_id'] as String;
      final productId = row['product_id'] as String?;
      // Null groups as one 'general' thread rather than scattering.
      final key = customerId + '|' + (productId ?? 'general');

      final existing = threads[key];
      if (existing != null) {
        threads[key] = InquiryThread(
          customerId: existing.customerId,
          productId: existing.productId,
          productName: existing.productName,
          customerName: existing.customerName,
          lastMessage: existing.lastMessage,
          lastMessageAt: existing.lastMessageAt,
          lastSenderRole: existing.lastSenderRole,
          messageCount: existing.messageCount + 1,
        );
        continue;
      }

      // First row seen for this thread is the newest, because of the
      // descending order above.
      final product = row['products'] as Map<String, dynamic>?;
      final profile = row['profiles'] as Map<String, dynamic>?;
      threads[key] = InquiryThread(
        customerId: customerId,
        productId: productId,
        productName: productId == null
            ? 'Chat with the shop'
            : (product?['name'] as String? ?? 'Product'),
        customerName: (profile?['full_name'] as String?)?.trim().isNotEmpty == true
            ? profile!['full_name'] as String
            : 'Customer',
        lastMessage: row['message'] as String,
        lastMessageAt: DateTime.parse(row['created_at'] as String),
        lastSenderRole: UserRole.fromJson(row['sender_role'] as String),
        messageCount: 1,
      );
    }

    return threads.values.toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  }

  /// [productId] null posts to the general conversation.
  Future<void> sendMessage({
    required String customerId,
    String? productId,
    required UserRole senderRole,
    required String message,
  }) async {
    await supabase.from('product_inquiries').insert({
      'customer_id': customerId,
      'product_id': productId,
      'sender_role': senderRole.toJson(),
      'message': message,
    });
  }
}
