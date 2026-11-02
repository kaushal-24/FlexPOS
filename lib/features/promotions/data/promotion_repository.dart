import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/promotions/domain/promotion_models.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final promotionRepositoryProvider = Provider<PromotionRepository>(
  (ref) => PromotionRepository(ref.watch(supabaseClientProvider)),
);

final promotionsProvider = FutureProvider.autoDispose<List<Promotion>>((ref) {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null || !workspace.permissionCodes.contains('sales.view')) {
    return Future.value(const []);
  }
  return ref
      .watch(promotionRepositoryProvider)
      .fetchPromotions(workspace.businessId);
});

class PromotionRepository implements SupabaseRepositoryContract {
  PromotionRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<Promotion>> fetchPromotions(String businessId) async {
    final rows = await _client
        .from('promotions')
        .select(
          'id,business_id,branch_id,code,name,discount_type,discount_value,minimum_subtotal,usage_limit,redeemed_count,starts_at,ends_at,is_active,created_at',
        )
        .eq('business_id', businessId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => Promotion.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> createPromotion({
    required String businessId,
    String? branchId,
    required String code,
    required String name,
    required String discountType,
    required double discountValue,
    required int minimumSubtotalMinor,
    int? usageLimit,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Authentication required');
    await _client.from('promotions').insert({
      'business_id': businessId,
      'branch_id': branchId,
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'discount_type': discountType,
      'discount_value': discountValue,
      'minimum_subtotal': minimumSubtotalMinor / 100,
      'usage_limit': usageLimit,
      'starts_at': startsAt?.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'created_by': userId,
    });
  }

  Future<void> updatePromotion({
    required String businessId,
    required String promotionId,
    required String code,
    required String name,
    required String discountType,
    required double discountValue,
    required int minimumSubtotalMinor,
    int? usageLimit,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    await _client
        .from('promotions')
        .update({
          'code': code.trim().toUpperCase(),
          'name': name.trim(),
          'discount_type': discountType,
          'discount_value': discountValue,
          'minimum_subtotal': minimumSubtotalMinor / 100,
          'usage_limit': usageLimit,
          'starts_at': startsAt?.toUtc().toIso8601String(),
          'ends_at': endsAt?.toUtc().toIso8601String(),
        })
        .eq('business_id', businessId)
        .eq('id', promotionId);
  }

  Future<void> setPromotionActive({
    required String businessId,
    required String promotionId,
    required bool isActive,
  }) async {
    await _client
        .from('promotions')
        .update({'is_active': isActive})
        .eq('business_id', businessId)
        .eq('id', promotionId);
  }

  Future<void> deletePromotion({
    required String businessId,
    required String promotionId,
  }) async {
    await _client
        .from('promotions')
        .delete()
        .eq('business_id', businessId)
        .eq('id', promotionId);
  }

  Future<CouponPreview> previewCoupon({
    required String businessId,
    required String branchId,
    required String code,
    required int subtotalMinor,
  }) async {
    final response = await _client.rpc(
      'preview_coupon',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'coupon_code': code.trim().toUpperCase(),
        'subtotal_amount': subtotalMinor / 100,
      },
    );
    return CouponPreview.fromJson(Map<String, dynamic>.from(response as Map));
  }
}
