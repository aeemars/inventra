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
      dependsOnOperationIds: const ['parent-op-1', 'parent-op-2'],
      processingStartedAt: now,
      conflictCategory: SyncConflictCategory.stockConflict,
      conflictExplanation: 'Insufficient server stock',
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
      expect(restored.dependsOnOperationIds, ['parent-op-1', 'parent-op-2']);
      expect(restored.conflictCategory, SyncConflictCategory.stockConflict);
      expect(restored.conflictExplanation, 'Insufficient server stock');
      expect(restored.processingStartedAt, now);
    });

    test('allDependencies merges legacy dependsOnOperationId and dependsOnOperationIds', () {
      final itemWithBoth = SyncQueueItem(
        localId: 'op-child',
        shopId: 'shop-abc',
        userId: 'user-1',
        operationType: SyncOperationType.createSale,
        entityType: 'sale',
        payload: const {},
        createdAt: now,
        updatedAt: now,
        dependsOnOperationId: 'legacy-dep',
        dependsOnOperationIds: const ['dep-1', 'dep-2'],
      );

      final allDeps = itemWithBoth.allDependencies;
      expect(allDeps, contains('legacy-dep'));
      expect(allDeps, contains('dep-1'));
      expect(allDeps, contains('dep-2'));
      expect(allDeps.length, 3);
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

    test('conflict status can be recorded with error description and category', () {
      final conflict = testItem.copyWith(
        status: SyncStatus.conflict,
        conflictCategory: SyncConflictCategory.stockConflict,
        conflictExplanation: 'Insufficient stock on server for requested transaction',
      );

      expect(conflict.status, SyncStatus.conflict);
      expect(conflict.conflictCategory, SyncConflictCategory.stockConflict);
      expect(conflict.conflictExplanation, contains('Insufficient stock'));
    });
  });
}
