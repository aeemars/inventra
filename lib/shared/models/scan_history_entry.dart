import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a single barcode scan event for audit trail
class ScanHistoryEntry extends Equatable {
  final String id;
  final String barcodeValue;
  final String? matchedProductId;
  final String? matchedProductName;
  final ScanMatchStatus status;
  final String scanIntent; // 'addProduct' or 'sale'
  final String scannedBy;
  final String scannedByName;
  final DateTime timestamp;
  final String shopId;

  const ScanHistoryEntry({
    required this.id,
    required this.barcodeValue,
    this.matchedProductId,
    this.matchedProductName,
    required this.status,
    required this.scanIntent,
    required this.scannedBy,
    required this.scannedByName,
    required this.timestamp,
    this.shopId = '',
  });

  bool get isMatched => status == ScanMatchStatus.matched;

  Map<String, dynamic> toFirestore() {
    return {
      'barcodeValue': barcodeValue,
      'matchedProductId': matchedProductId,
      'matchedProductName': matchedProductName,
      'status': status.name,
      'scanIntent': scanIntent,
      'scannedBy': scannedBy,
      'scannedByName': scannedByName,
      'timestamp': FieldValue.serverTimestamp(),
      if (shopId.isNotEmpty) 'shopId': shopId,
    };
  }

  factory ScanHistoryEntry.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc, [String? explicitShopId]) {
    final data = doc.data()!;
    final resolvedShopId = explicitShopId ??
        data['shopId'] as String? ??
        (doc.reference.parent.parent != null
            ? doc.reference.parent.parent!.id
            : '');

    return ScanHistoryEntry(
      id: doc.id,
      barcodeValue: data['barcodeValue'] as String? ?? '',
      matchedProductId: data['matchedProductId'] as String?,
      matchedProductName: data['matchedProductName'] as String?,
      status: ScanMatchStatus.values.firstWhere(
        (e) => e.name == (data['status'] as String?),
        orElse: () => ScanMatchStatus.unmatched,
      ),
      scanIntent: data['scanIntent'] as String? ?? 'sale',
      scannedBy: data['scannedBy'] as String? ?? '',
      scannedByName: data['scannedByName'] as String? ?? '',
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      shopId: resolvedShopId,
    );
  }

  @override
  List<Object?> get props => [id, barcodeValue, status, timestamp, shopId];
}

enum ScanMatchStatus { matched, unmatched }
