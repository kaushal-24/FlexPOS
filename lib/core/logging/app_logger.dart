import 'dart:convert';
import 'dart:developer' as developer;

enum AppLogLevel { debug, info, warning, error }

class AppLogger {
  AppLogger({this._sink});

  final void Function(String message)? _sink;

  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      _write(AppLogLevel.debug, event, fields);

  void info(String event, {Map<String, Object?> fields = const {}}) =>
      _write(AppLogLevel.info, event, fields);

  void warning(String event, {Map<String, Object?> fields = const {}}) =>
      _write(AppLogLevel.warning, event, fields);

  void error(
    String event, {
    Object? exception,
    Map<String, Object?> fields = const {},
  }) => _write(AppLogLevel.error, event, {
    ...fields,
    if (exception != null) 'error': exception.toString(),
  });

  void _write(AppLogLevel level, String event, Map<String, Object?> fields) {
    final payload = <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'event': event,
      'fields': _redactMap(fields),
    };
    final message = jsonEncode(payload);
    (_sink ?? developer.log).call(message);
  }

  Map<String, Object?> _redactMap(Map<String, Object?> fields) => {
    for (final entry in fields.entries)
      entry.key: _redact(entry.key, entry.value),
  };

  Object? _redact(String key, Object? value) {
    final normalized = key.toLowerCase();
    if (normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('authorization') ||
        normalized.contains('api_key') ||
        normalized.contains('access_code')) {
      return '[redacted]';
    }
    if (normalized.contains('email') && value is String) {
      final at = value.indexOf('@');
      if (at > 1) return '${value.substring(0, 1)}***${value.substring(at)}';
      return '[redacted]';
    }
    if (value is Map) {
      return _redactMap(Map<String, Object?>.from(value));
    }
    if (value is Iterable) {
      return value.map((item) => _redact(key, item)).toList(growable: false);
    }
    return value;
  }
}
