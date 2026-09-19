import '../models/offer.dart';
import '../supabase/supabase_bootstrap.dart';

/// Staff/owner-only offer management. [CatalogRepository.getActiveOffers]
/// covers the public/customer read; this repository is for the staff
/// "Offer Manager" screen, which needs to see and edit every offer
/// regardless of whether it's currently active.
class OfferRepository {
  Future<List<Offer>> getAllOffers() async {
    final rows = await supabase.from('offers').select().order('created_at', ascending: false);
    return rows.map(Offer.fromJson).toList();
  }

  Future<Offer> createOffer({
    required String title,
    String? description,
    required DiscountType discountType,
    required double discountValue,
    required OfferScope scope,
    String? categoryId,
    String? productId,
    required DateTime startsAt,
    DateTime? endsAt,
  }) async {
    final row = await supabase
        .from('offers')
        .insert({
          'title': title,
          'description': description,
          'discount_type': discountType.toJson(),
          'discount_value': discountValue,
          'scope': scope.toJson(),
          'category_id': scope == OfferScope.category ? categoryId : null,
          'product_id': scope == OfferScope.product ? productId : null,
          'starts_at': startsAt.toIso8601String(),
          'ends_at': endsAt?.toIso8601String(),
        })
        .select()
        .single();
    return Offer.fromJson(row);
  }

  Future<void> setActive(String offerId, bool isActive) async {
    await supabase.from('offers').update({'is_active': isActive}).eq('id', offerId);
  }
}
