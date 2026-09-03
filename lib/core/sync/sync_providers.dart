import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/firebase_providers.dart';
import '../cache/local_database.dart';
import '../connectivity/connectivity_service.dart';
import 'sync_models.dart';
import 'sync_processor.dart';

final syncProcessorProvider = Provider<SyncProcessor>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  final currentShopId = ref.watch(currentShopIdProvider);
  final processor = SyncProcessor(
    localDb: LocalDatabase.instance,
    connectivity: connectivity,
    initialShopId: currentShopId,
  );
  processor.initialize();

  ref.listen<String?>(currentShopIdProvider, (previous, next) {
    processor.setActiveShop(next);
  });

  ref.onDispose(() => processor.dispose());
  return processor;
});

final syncStatusProvider = StreamProvider<SyncEngineState>((ref) {
  final processor = ref.watch(syncProcessorProvider);
  return Stream<SyncEngineState>.multi((controller) {
    controller.add(processor.currentState);
    final sub = processor.onStateChanged.listen(controller.add);
    controller.onCancel = () => sub.cancel();
  });
});

final syncQueueItemsProvider = StreamProvider<List<SyncQueueItem>>((ref) {
  final localDb = LocalDatabase.instance;
  if (!localDb.isInitialized) return Stream.value([]);

  final box = localDb.syncQueueBox;
  return Stream<List<SyncQueueItem>>.multi((controller) {
    controller.add(box.values.toList());
    final sub = box.watch().listen((_) {
      controller.add(box.values.toList());
    });
    controller.onCancel = () => sub.cancel();
  });
});

final pendingSyncCountProvider = Provider<int>((ref) {
  final itemsAsync = ref.watch(syncQueueItemsProvider);
  return itemsAsync.when(
    data: (items) => items
        .where((i) =>
            i.status == SyncStatus.pending ||
            i.status == SyncStatus.processing ||
            i.status == SyncStatus.conflict)
        .length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

final conflictSyncCountProvider = Provider<int>((ref) {
  final itemsAsync = ref.watch(syncQueueItemsProvider);
  return itemsAsync.when(
    data: (items) =>
        items.where((i) => i.status == SyncStatus.conflict).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

final syncMetadataProvider = StreamProvider<SyncMetadata?>((ref) {
  final processor = ref.watch(syncProcessorProvider);
  final currentShopId = ref.watch(currentShopIdProvider);
  return Stream<SyncMetadata?>.multi((controller) {
    controller.add(processor.getSyncMetadata(currentShopId));
    final sub = processor.onMetadataChanged.listen((meta) {
      if (currentShopId == null || meta?.shopId == currentShopId) {
        controller.add(meta);
      }
    });
    controller.onCancel = () => sub.cancel();
  });
});
