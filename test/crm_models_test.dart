import 'package:flexpos/features/crm/domain/crm_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const common = {
    'id': 'record-1',
    'created_by': 'user-1',
    'created_at': '2026-10-27T08:00:00Z',
    'updated_at': '2026-10-27T08:30:00Z',
  };

  test('CRM lead maps decimal value to exact minor units', () {
    final lead = CrmLead.fromJson({
      ...common,
      'title': 'Retail rollout',
      'source': 'referral',
      'status': 'qualified',
      'salesperson_id': 'user-1',
      'customer_id': 'customer-1',
      'estimated_value': '1250.75',
      'expected_close_at': '2026-11-15',
      'notes': 'Priority account',
      'archived_at': null,
    });

    expect(lead.estimatedValueMinor, 125075);
    expect(lead.status, 'qualified');
    expect(lead.isArchived, isFalse);
  });

  test('CRM opportunity exposes pipeline state', () {
    final opportunity = CrmOpportunity.fromJson({
      ...common,
      'title': 'New branch setup',
      'stage': 'negotiation',
      'probability': 70,
      'value_minor': 500000,
      'expected_close_at': '2026-12-01',
      'actual_close_at': null,
      'notes': null,
      'salesperson_id': 'user-1',
      'customer_id': 'customer-1',
      'lead_id': 'lead-1',
      'archived_at': null,
    });

    expect(opportunity.valueMinor, 500000);
    expect(opportunity.probability, 70);
    expect(opportunity.isClosed, isFalse);
  });

  test('CRM follow-up and reminder calculate completion state', () {
    final followUp = CrmFollowUp.fromJson({
      ...common,
      'title': 'Call buyer',
      'type': 'call',
      'due_at': '2026-10-28T09:00:00Z',
      'completed_at': '2026-10-28T09:15:00Z',
      'notes': null,
      'salesperson_id': 'user-1',
      'lead_id': 'lead-1',
      'opportunity_id': null,
      'quotation_id': null,
    });
    final reminder = CrmReminder.fromJson({
      ...common,
      'title': 'Send proposal',
      'description': 'Attach price list',
      'due_at': '2026-10-29T09:00:00Z',
      'is_completed': false,
      'completed_at': null,
      'related_table': 'opportunity',
      'related_id': 'opportunity-1',
      'salesperson_id': 'user-1',
    });

    expect(followUp.isCompleted, isTrue);
    expect(reminder.isCompleted, isFalse);
    expect(reminder.relatedTable, 'opportunity');
  });
}
