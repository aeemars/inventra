import 'package:flutter_test/flutter_test.dart';
import 'package:inventra/core/sync/sync_models.dart';

void main() {
  group('SyncQueueItem Model & Queue Logic', () {
    final now = DateTime(2026, 9, 2, 12, 0, 0);

    final testItem = SyncQueueItem(
      localId: 'local-op-123',
      shopId: 'shop-abc',
      userId: 'user-xyz',
      operationType: SyncOperationType.createProduct,
      entityType: 'product',
      entityId: 'prod-456',
      payload: {
        'name': 'Offline Widget',
        'sellingPrice': 1500.0,
        'quantity': 25,
      },
      createdAt: now,
      updatedAt: now,
      status: SyncStatus.pending,
      retryCount: 0,
    );

    test('serializes to and from Map correctly', () {
      final map = testItem.toMap();
      final restored = SyncQueueItem.fromMap(map);

      expect(restored.localId, testItem.localId);
      expect(restored.shopId, testItem.shopId);
      expect(restored.userId, testItem.userId);
      expect(restored.operationType, SyncOperationType.createProduct);
      expect(restored.entityType, 'product');
      expect(restored.entityId, 'prod-456');
      expect(restored.payload['name'], 'Offline Widget');
      expect(restored.payload['sellingPrice'], 1500.0);
      expect(restored.status, SyncStatus.pending);
      expect(restored.retryCount, 0);
      expect(restored.createdAt, now);
    });

    test('copyWith updates fields without mutating original', () {
      final processing = testItem.copyWith(
        status: SyncStatus.processing,
        retryCount: 1,
        lastError: 'Temporary network failure',
      );

      expect(processing.status, SyncStatus.processing);
      expect(processing.retryCount, 1);
      expect(processing.lastError, 'Temporary network failure');
      expect(testItem.status, SyncStatus.pending); // original intact
    });

    test('dependency-aware queue sorting prioritizes parent operations', () {
      final productCreate = SyncQueueItem(
        localId: 'op-create-prod',
        shopId: 'shop-abc',
        userId: 'user-xyz',
        operationType: SyncOperationType.createProduct,
        entityType: 'product',
        entityId: 'prod-1',
        payload: {'name': 'Product 1'},
        createdAt: now,
        updatedAt: now,
      );

      final productSale = SyncQueueItem(
        localId: 'op-sale-prod',
        shopId: 'shop-abc',
        userId: 'user-xyz',
        operationType: SyncOperationType.createSale,
        entityType: 'sale',
        entityId: 'tx-1',
        dependsOnOperationId: 'op-create-prod',
        payload: {'items': []},
        createdAt: now.add(const Duration(seconds: 10)),
        updatedAt: now.add(const Duration(seconds: 10)),
      );

      // Unordered list
      final queue = [productSale, productCreate];

      queue.sort((a, b) {
        if (a.dependsOnOperationId != null && a.dependsOnOperationId == b.localId) {
          return 1;
        }
        if (b.dependsOnOperationId != null && b.dependsOnOperationId == a.localId) {
          return -1;
        }
        return a.createdAt.compareTo(b.createdAt);
      });

      expect(queue.first.localId, 'op-create-prod');
      expect(queue.last.localId, 'op-sale-prod');
    });

    test('idempotency key is preserved across retries', () {
      final initial = testItem;
      final retry1 = initial.copyWith(
        retryCount: initial.retryCount + 1,
        status: SyncStatus.pending,
      );
      final retry2 = retry1.copyWith(
        retryCount: retry1.retryCount + 1,
        status: SyncStatus.pending,
      );

      expect(retry2.localId, initial.localId);
      expect(retry2.retryCount, 2);
    });

    test('conflict status can be recorded with error description', () {
      final conflict = testItem.copyWith(
        status: SyncStatus.conflict,
        lastError: 'failed-precondition: Insufficient stock on server',
      );

      expect(conflict.status, SyncStatus.conflict);
      expect(conflict.lastError, contains('Insufficient stock'));
    });
  });
}
