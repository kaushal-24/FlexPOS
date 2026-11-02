import 'package:flutter_test/flutter_test.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/business_receipt_settings.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';

void main() {
  group('BusinessWorkspace', () {
    test('maps a membership and its branches', () {
      const branch = BusinessBranch(
        id: 'branch-1',
        businessId: 'business-1',
        name: 'Main Branch',
        code: 'MAIN',
        timezone: 'Asia/Kolkata',
      );
      final workspace = BusinessWorkspace.fromMembership(
        {
          'id': 'membership-1',
          'branch_access_all': true,
          'businesses': {
            'id': 'business-1',
            'name': 'Flex Retail',
            'business_type': 'retail',
            'currency_code': 'INR',
            'timezone': 'Asia/Kolkata',
          },
          'roles': {
            'id': 'role-1',
            'name': 'Owner',
            'role_permissions': [
              {'permission_code': 'roles.manage'},
            ],
          },
        },
        const [branch],
        enabledFeatureCodes: const {
          FeatureCodes.inventory,
          FeatureCodes.purchasing,
        },
      );

      expect(workspace.businessName, 'Flex Retail');
      expect(workspace.roleName, 'Owner');
      expect(workspace.hasAllBranchAccess, isTrue);
      expect(workspace.permissionCodes, contains('roles.manage'));
      expect(workspace.branches.single.code, 'MAIN');
      expect(workspace.isFeatureEnabled(FeatureCodes.inventory), isTrue);
      expect(workspace.isFeatureEnabled(FeatureCodes.registers), isFalse);
    });
  });

  group('CreateBusinessRequest', () {
    test('normalizes values sent to the onboarding RPC', () {
      const request = CreateBusinessRequest(
        businessName: '  Flex Retail  ',
        businessType: 'retail',
        currencyCode: 'INR',
        timezone: 'Asia/Kolkata',
        branchName: '  Main Branch ',
        branchCode: ' main-01 ',
        countryCode: 'IN',
      );

      expect(request.toRpcParameters(), {
        'business_name': 'Flex Retail',
        'selected_business_type': 'retail',
        'selected_currency_code': 'INR',
        'selected_timezone': 'Asia/Kolkata',
        'branch_name': 'Main Branch',
        'branch_code': 'MAIN-01',
        'selected_country_code': 'IN',
      });
    });
  });

  group('BusinessReceiptSettings', () {
    test('maps optional receipt identity fields', () {
      final settings = BusinessReceiptSettings.fromJson({
        'id': 'business-1',
        'name': 'Flex Retail',
        'tax_registration_number': '  GST-123  ',
        'invoice_prefix': 'INV',
        'receipt_footer': '  Thank you.  ',
      });

      expect(settings.businessId, 'business-1');
      expect(settings.businessName, 'Flex Retail');
      expect(settings.taxRegistrationNumber, 'GST-123');
      expect(settings.invoicePrefix, 'INV');
      expect(settings.receiptFooter, 'Thank you.');
    });
  });
}
