import 'dart:typed_data';

import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/receipts/domain/receipt_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(ref.watch(supabaseClientProvider)),
);

class ReceiptRepository implements SupabaseRepositoryContract {
  ReceiptRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<ReceiptDocument> fetchReceipt({
    required String businessId,
    required String saleId,
  }) async {
    final sale = Map<String, dynamic>.from(
      await _client
          .from('sales')
          .select(
            'id,business_id,branch_id,customer_id,invoice_number,currency_code,'
            'subtotal,discount_total,tax_total,service_charge_total,'
            'rounding_amount,grand_total,paid_total,due_total,payment_status,'
            'status,notes,completed_at',
          )
          .eq('business_id', businessId)
          .eq('id', saleId)
          .single(),
    );

    final branchId = sale['branch_id'] as String;
    final customerId = sale['customer_id'] as String?;
    final rows = await Future.wait([
      _client
          .from('businesses')
          .select(
            'id,name,tax_registration_number,receipt_footer,receipt_template,'
            'receipt_logo_path,receipt_qr_payload,receipt_show_logo,receipt_show_qr',
          )
          .eq('id', businessId)
          .single(),
      _client
          .from('branches')
          .select(
            'id,business_id,name,email,phone,address_line_1,address_line_2,'
            'city,state_region,postal_code,country_code',
          )
          .eq('business_id', businessId)
          .eq('id', branchId)
          .single(),
      _client
          .from('sale_items')
          .select(
            'product_name,variant_name,sku,quantity,unit_price,'
            'discount_amount,tax_rate,tax_amount,line_total,note,created_at',
          )
          .eq('business_id', businessId)
          .eq('sale_id', saleId)
          .order('created_at'),
      _client
          .from('payments')
          .select('payment_method,status,amount,reference,provider,created_at')
          .eq('business_id', businessId)
          .eq('sale_id', saleId)
          .order('created_at'),
    ]);

    Map<String, dynamic>? customer;
    if (customerId != null) {
      final customerRow = await _client
          .from('customers')
          .select('id,business_id,name,phone,gstin')
          .eq('business_id', businessId)
          .eq('id', customerId)
          .maybeSingle();
      if (customerRow != null) {
        customer = Map<String, dynamic>.from(customerRow);
      }
    }

    List<Map<String, dynamic>> maps(Object value) => (value as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);

    final business = Map<String, dynamic>.from(rows[0] as Map);
    Uint8List? logoBytes;
    final logoPath = business['receipt_logo_path'] as String?;
    if (logoPath != null && logoPath.isNotEmpty) {
      try {
        logoBytes = await _client.storage
            .from('business-assets')
            .download(logoPath);
      } catch (_) {
        // A missing/revoked asset must not prevent receipt reconstruction.
      }
    }

    return ReceiptDocument.fromRows(
      sale: sale,
      business: business,
      branch: Map<String, dynamic>.from(rows[1] as Map),
      items: maps(rows[2]),
      payments: maps(rows[3]),
      customer: customer,
      logoBytes: logoBytes,
    );
  }
}
