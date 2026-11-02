import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/pos/domain/pos_catalog_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const coffee = CatalogProduct(
    productId: 'product-coffee',
    variantId: 'variant-coffee',
    name: 'Coffee',
    variantName: 'Default',
    sku: 'DRINK-1',
    priceMinor: 4000,
    costMinor: 2000,
    taxRateBasisPoints: 0,
    trackInventory: true,
    allowFractionalQuantity: false,
    barcodes: ['890000000001'],
    categoryId: 'drinks',
    categoryName: 'Drinks',
    isFavorite: true,
  );
  const cake = CatalogProduct(
    productId: 'product-cake',
    variantId: 'variant-cake',
    name: 'Chocolate cake',
    variantName: 'Slice',
    sku: 'FOOD-1',
    priceMinor: 5500,
    costMinor: 2500,
    taxRateBasisPoints: 0,
    trackInventory: true,
    allowFractionalQuantity: false,
    barcodes: [],
    categoryId: 'food',
    categoryName: 'Food',
  );

  test('POS catalog combines category tabs with normalized search', () {
    expect(
      filterPosCatalog(
        products: const [coffee, cake],
        categoryId: 'drinks',
        query: ' COF ',
      ),
      const [coffee],
    );
    expect(
      filterPosCatalog(
        products: const [coffee, cake],
        categoryId: 'drinks',
        query: 'cake',
      ),
      isEmpty,
    );
  });

  test('catalog product search includes its category name', () {
    expect(
      filterPosCatalog(products: const [coffee, cake], query: 'drinks'),
      const [coffee],
    );
  });

  test('favorites mode returns only quick-sale products', () {
    expect(
      filterPosCatalog(products: const [coffee, cake], favoritesOnly: true),
      const [coffee],
    );
  });

  test('scanner input resolves an exact normalized barcode only', () {
    expect(
      findExactBarcodeProduct(const [coffee, cake], ' 890000000001 '),
      coffee,
    );
    expect(findExactBarcodeProduct(const [coffee, cake], 'DRINK-1'), isNull);
    expect(findExactBarcodeProduct(const [coffee, cake], ''), isNull);
  });

  test('ambiguous barcode input is rejected instead of adding a product', () {
    const duplicate = CatalogProduct(
      productId: 'product-duplicate',
      variantId: 'variant-duplicate',
      name: 'Duplicate barcode',
      variantName: 'Default',
      sku: 'DUP-1',
      priceMinor: 100,
      costMinor: 50,
      taxRateBasisPoints: 0,
      trackInventory: false,
      allowFractionalQuantity: false,
      barcodes: ['890000000001'],
    );
    expect(
      findExactBarcodeProduct(const [coffee, duplicate], '890000000001'),
      isNull,
    );
  });
}
