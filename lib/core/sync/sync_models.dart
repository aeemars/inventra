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
  });

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
    };
  }

  factory SyncQueueItem.fromMap(Map<dynamic, dynamic> map) {
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
      ];
}
