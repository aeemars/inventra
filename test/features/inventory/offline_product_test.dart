import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:inventra/core/cache/hive_adapters.dart';
import 'package:inventra/core/cache/local_database.dart';
import 'package:inventra/features/inventory/domain/entities/product.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_inventory_test_');
    Hive.init(tempDir.path);
    registerHiveAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await LocalDatabase.instance.initialize();
    await LocalDatabase.instance.clearShopData();
  });

  group('Offline Product Local Persistence', () {
    final now = DateTime.now();
    final testProduct = Product(
      id: 'prod-local-001',
      name: 'Indomie Instant Noodles',
      sku: 'IND-001',
      barcode: '071234567890',
      costPrice: 200.0,
      sellingPrice: 350.0,
      quantity: 100,
      reorderLevel: 20,
      unit: 'pcs',
      createdAt: now,
      updatedAt: now,
      createdBy: 'user-1',
      updatedBy: 'user-1',
    );

    test('saves and retrieves product from Hive immediately', () async {
      await LocalDatabase.instance.productsBox.put(testProduct.id, testProduct);

      final retrieved = LocalDatabase.instance.productsBox.get(testProduct.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Indomie Instant Noodles');
      expect(retrieved.sellingPrice, 350.0);
      expect(retrieved.quantity, 100);
      expect(retrieved.isActive, true);
    });

    test('updates product offline without network', () async {
      await LocalDatabase.instance.productsBox.put(testProduct.id, testProduct);

      final updated = testProduct.copyWith(
        sellingPrice: 400.0,
        quantity: 120,
      );
      await LocalDatabase.instance.productsBox.put(testProduct.id, updated);

      final retrieved = LocalDatabase.instance.productsBox.get(testProduct.id);
      expect(retrieved!.sellingPrice, 400.0);
      expect(retrieved.quantity, 120);
    });

    test('soft deletes product offline by marking isActive false', () async {
      await LocalDatabase.instance.productsBox.put(testProduct.id, testProduct);

      final deactivated = testProduct.copyWith(isActive: false);
      await LocalDatabase.instance.productsBox.put(testProduct.id, deactivated);

      final retrieved = LocalDatabase.instance.productsBox.get(testProduct.id);
      expect(retrieved!.isActive, false);

      // Active products query filters out inactive
      final activeProducts = LocalDatabase.instance.productsBox.values
          .where((p) => p.isActive)
          .toList();
      expect(activeProducts.any((p) => p.id == testProduct.id), false);
    });

    test('local barcode and SKU lookup works offline', () async {
      await LocalDatabase.instance.productsBox.put(testProduct.id, testProduct);

      final products = LocalDatabase.instance.productsBox.values.where((p) => p.isActive);

      // Exact barcode
      final byBarcode = products.firstWhere((p) => p.barcode == '071234567890');
      expect(byBarcode.id, testProduct.id);

      // Exact SKU
      final bySku = products.firstWhere((p) => p.sku == 'IND-001');
      expect(bySku.id, testProduct.id);

      // UPC-A ↔ EAN-13 candidate lookup
      final strippedZero = '71234567890';
      final matchCandidate = products.any((p) =>
          p.barcode == strippedZero || p.barcode == '0$strippedZero');
      expect(matchCandidate, true);
    });

    test('local product search filters correctly offline', () async {
      final p1 = testProduct;
      final p2 = testProduct.copyWith(
        id: 'prod-local-002',
        name: 'Golden Penny Spaghetti',
        sku: 'GPS-002',
        barcode: '998877665544',
      );

      await LocalDatabase.instance.productsBox.put(p1.id, p1);
      await LocalDatabase.instance.productsBox.put(p2.id, p2);

      final all = LocalDatabase.instance.productsBox.values.where((p) => p.isActive);

      final searchNoodles = all
          .where((p) => p.name.toLowerCase().contains('noodles'))
          .toList();
      expect(searchNoodles.length, 1);
      expect(searchNoodles.first.name, 'Indomie Instant Noodles');

      final searchSpaghetti = all
          .where((p) => p.name.toLowerCase().contains('spaghetti'))
          .toList();
      expect(searchSpaghetti.length, 1);
      expect(searchSpaghetti.first.name, 'Golden Penny Spaghetti');
    });
  });
}
