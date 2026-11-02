import 'dart:convert';

import 'package:flexpos/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structured logger redacts secrets and masks email addresses', () {
    String? message;
    final logger = AppLogger(sink: (value) => message = value);

    logger.info(
      'auth.sign_in.started',
      fields: {
        'email': 'pithvakaushal24@gmail.com',
        'password': 'never-log-this',
        'nested': {'access_token': 'secret-token'},
      },
    );

    final payload = jsonDecode(message!) as Map<String, dynamic>;
    final fields = payload['fields'] as Map<String, dynamic>;
    expect(fields['email'], 'p***@gmail.com');
    expect(fields['password'], '[redacted]');
    expect((fields['nested'] as Map)['access_token'], '[redacted]');
    expect(message, isNot(contains('never-log-this')));
    expect(message, isNot(contains('secret-token')));
  });
}
