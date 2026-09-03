import 'package:equatable/equatable.dart';

enum SyncOperationType {
  createProduct,
  updateProduct,
  deleteProduct,
  createSale,
  stockAdjustment,
  restock,
  createScan,
  createCategory,
  updateCategory,
  deleteCategory,
}

enum SyncStatus {
  pending,
  processing,
  synced,
  failed,
  conflict,
}

enum SyncEngineState {
  offline,
  idle,
  syncing,
  waitingDependency,
  retryWait,
  error,
  conflict,
}

enum SyncConflictCategory {
  stockConflict,
  productConflict,
  permissionConflict,
  deletedResource,
  validationConflict,
  dependencyConflict,
  duplicateOperation,
  unknownConflict;

  String get label {
    switch (this) {
      case SyncConflictCategory.stockConflict:
        return 'Stock Conflict';
      case SyncConflictCategory.productConflict:
        return 'Product Conflict';
      case SyncConflictCategory.permissionConflict:
        return 'Permission Error';
      case SyncConflictCategory.deletedResource:
        return 'Resource Deleted';
      case SyncConflictCategory.validationConflict:
        return 'Validation Error';
      case SyncConflictCategory.dependencyConflict:
        return 'Dependency Error';
      case SyncConflictCategory.duplicateOperation:
        return 'Duplicate Operation';
      case SyncConflictCategory.unknownConflict:
        return 'Sync Error';
    }
  }
}

/// Represents a single mutation queued for synchronization.
class SyncQueueItem extends Equatable {
  final String localId;
  final String shopId;
  final String userId;
  final SyncOperationType operationType;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus status;
  final int retryCount;
  final String? lastError;
  final String? serverId;
  final String? dependsOnOperationId;
  final List<String> dependsOnOperationIds;
  final DateTime? processingStartedAt;
  final SyncConflictCategory? conflictCategory;
  final String? conflictExplanation;

  const SyncQueueItem({
    required this.localId,
    required this.shopId,
    required this.userId,
    required this.operationType,
    required this.entityType,
    this.entityId,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.lastError,
    this.serverId,
    this.dependsOnOperationId,
    this.dependsOnOperationIds = const [],
    this.processingStartedAt,
    this.conflictCategory,
    this.conflictExplanation,
  });

  /// Set of all prerequisite operation IDs that must complete before this item can execute.
  Set<String> get allDependencies {
    final set = <String>{...dependsOnOperationIds};
    if (dependsOnOperationId != null && dependsOnOperationId!.trim().isNotEmpty) {
      set.add(dependsOnOperationId!.trim());
    }
    return set;
  }

  SyncQueueItem copyWith({
    String? localId,
    String? shopId,
    String? userId,
    SyncOperationType? operationType,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? status,
    int? retryCount,
    String? lastError,
    String? serverId,
    String? dependsOnOperationId,
    List<String>? dependsOnOperationIds,
    DateTime? processingStartedAt,
    bool clearProcessingStartedAt = false,
    SyncConflictCategory? conflictCategory,
    String? conflictExplanation,
  }) {
    return SyncQueueItem(
      localId: localId ?? this.localId,
      shopId: shopId ?? this.shopId,
      userId: userId ?? this.userId,
      operationType: operationType ?? this.operationType,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      serverId: serverId ?? this.serverId,
      dependsOnOperationId: dependsOnOperationId ?? this.dependsOnOperationId,
      dependsOnOperationIds: dependsOnOperationIds ?? this.dependsOnOperationIds,
      processingStartedAt: clearProcessingStartedAt
          ? null
          : (processingStartedAt ?? this.processingStartedAt),
      conflictCategory: conflictCategory ?? this.conflictCategory,
      conflictExplanation: conflictExplanation ?? this.conflictExplanation,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'localId': localId,
      'shopId': shopId,
      'userId': userId,
      'operationType': operationType.name,
      'entityType': entityType,
      'entityId': entityId,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'status': status.name,
      'retryCount': retryCount,
      'lastError': lastError,
      'serverId': serverId,
      'dependsOnOperationId': dependsOnOperationId,
      'dependsOnOperationIds': dependsOnOperationIds,
      'processingStartedAt': processingStartedAt?.toIso8601String(),
      'conflictCategory': conflictCategory?.name,
      'conflictExplanation': conflictExplanation,
    };
  }

  factory SyncQueueItem.fromMap(Map<dynamic, dynamic> map) {
    final rawList = map['dependsOnOperationIds'];
    final List<String> deps = rawList is List
        ? rawList.map((e) => e.toString()).toList()
        : (map['dependsOnOperationId'] != null
            ? [map['dependsOnOperationId'].toString()]
            : const []);

    final conflictCatStr = map['conflictCategory'] as String?;
    SyncConflictCategory? conflictCategory;
    if (conflictCatStr != null) {
      conflictCategory = SyncConflictCategory.values.firstWhere(
        (c) =>
            c.name.toLowerCase() ==
            conflictCatStr.replaceAll('_', '').toLowerCase(),
        orElse: () => SyncConflictCategory.unknownConflict,
      );
    }

    final startedAtStr = map['processingStartedAt'] as String?;
    final processingStartedAt =
        startedAtStr != null ? DateTime.tryParse(startedAtStr) : null;

    return SyncQueueItem(
      localId: map['localId'] as String,
      shopId: map['shopId'] as String,
      userId: map['userId'] as String? ?? '',
      operationType: SyncOperationType.values.firstWhere(
        (e) => e.name == map['operationType'],
        orElse: () => SyncOperationType.createProduct,
      ),
      entityType: map['entityType'] as String? ?? 'product',
      entityId: map['entityId'] as String?,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      status: SyncStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => SyncStatus.pending,
      ),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastError: map['lastError'] as String?,
      serverId: map['serverId'] as String?,
      dependsOnOperationId: map['dependsOnOperationId'] as String?,
      dependsOnOperationIds: deps,
      processingStartedAt: processingStartedAt,
      conflictCategory: conflictCategory,
      conflictExplanation: map['conflictExplanation'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        localId,
        shopId,
        userId,
        operationType,
        entityType,
        entityId,
        status,
        retryCount,
        createdAt,
        updatedAt,
        dependsOnOperationIds,
        processingStartedAt,
        conflictCategory,
      ];
}
