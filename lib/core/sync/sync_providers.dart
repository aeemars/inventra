import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cache/local_database.dart';
import '../connectivity/connectivity_service.dart';
import 'sync_models.dart';
import 'sync_processor.dart';

final syncProcessorProvider = Provider<SyncProcessor>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  final processor = SyncProcessor(
    localDb: LocalDatabase.instance,
    connectivity: connectivity,
  );
  processor.initialize();
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
