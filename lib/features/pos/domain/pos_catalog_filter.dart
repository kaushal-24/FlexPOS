import 'package:flexpos/features/catalog/domain/catalog_models.dart';

List<CatalogProduct> filterPosCatalog({
  required Iterable<CatalogProduct> products,
  String query = '',
  String? categoryId,
  bool favoritesOnly = false,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  return products
      .where(
        (product) =>
            (!favoritesOnly || product.isFavorite) &&
            (categoryId == null || product.categoryId == categoryId) &&
            (normalizedQuery.isEmpty ||
                product.searchText.contains(normalizedQuery)),
      )
      .toList(growable: false);
}

CatalogProduct? findExactBarcodeProduct(
  Iterable<CatalogProduct> products,
  String input,
) {
  final normalizedInput = input.trim().toLowerCase();
  if (normalizedInput.isEmpty) return null;
  CatalogProduct? match;
  for (final product in products) {
    final matches = product.barcodes.any(
      (barcode) => barcode.trim().toLowerCase() == normalizedInput,
    );
    if (!matches) continue;
    if (match != null && match.variantId != product.variantId) return null;
    match = product;
  }
  return match;
}
