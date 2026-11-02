/// A bounded page returned by a server-backed data source.
class ServerPage<T> {
  const ServerPage({
    required this.items,
    required this.pageSize,
    required this.hasMore,
    this.nextCreatedAt,
    this.nextId,
  });

  final List<T> items;
  final int pageSize;
  final bool hasMore;
  final DateTime? nextCreatedAt;
  final String? nextId;

  bool get isEmpty => items.isEmpty;

  ServerPage<T> copyWith({
    List<T>? items,
    int? pageSize,
    bool? hasMore,
    DateTime? nextCreatedAt,
    String? nextId,
  }) => ServerPage<T>(
    items: items ?? this.items,
    pageSize: pageSize ?? this.pageSize,
    hasMore: hasMore ?? this.hasMore,
    nextCreatedAt: nextCreatedAt ?? this.nextCreatedAt,
    nextId: nextId ?? this.nextId,
  );
}

/// Converts a keyset response into a stable page and cursor.
ServerPage<Map<String, dynamic>> serverJsonPage(
  List<dynamic> response, {
  int pageSize = 50,
  String idKey = 'id',
  String createdAtKey = 'created_at',
}) {
  final rows = response
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
  final last = rows.isEmpty ? null : rows.last;
  return ServerPage<Map<String, dynamic>>(
    items: rows,
    pageSize: pageSize,
    hasMore: rows.length == pageSize,
    nextCreatedAt: last == null || last[createdAtKey] == null
        ? null
        : DateTime.tryParse(last[createdAtKey].toString()),
    nextId: last?[idKey]?.toString(),
  );
}
