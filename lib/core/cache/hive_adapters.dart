import 'package:hive_ce/hive_ce.dart';
import '../../features/inventory/domain/entities/product.dart';
import '../../features/inventory/domain/entities/category.dart';
import '../../shared/models/stock_movement.dart';
import '../../shared/models/notification_model.dart';
import '../../shared/models/shop_settings_model.dart';

// ── Type IDs ──
// Product         = 0
// Category        = 1
// SaleTransaction = 2
// SaleItem        = 3
// StockMovement   = 4
// AppNotification = 5
// ShopSettings    = 6

/// Register all Hive type adapters for offline caching
void registerHiveAdapters() {
  Hive.registerAdapter(ProductAdapter());
  Hive.registerAdapter(CategoryAdapter());
  Hive.registerAdapter(SaleTransactionAdapter());
  Hive.registerAdapter(SaleItemAdapter());
  Hive.registerAdapter(StockMovementAdapter());
  Hive.registerAdapter(AppNotificationAdapter());
  Hive.registerAdapter(ShopSettingsAdapter());
}

// ═══════════════════════════════════════════
// Product Adapter (TypeId: 0)
// ═══════════════════════════════════════════
class ProductAdapter extends TypeAdapter<Product> {
  @override
  final int typeId = 0;

  @override
  Product read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Product(
      id: fields[0] as String,
      name: fields[1] as String,
      sku: fields[2] as String,
      barcode: fields[3] as String?,
      categoryId: fields[4] as String?,
      categoryName: fields[5] as String?,
      costPrice: fields[6] as double,
      sellingPrice: fields[7] as double,
      quantity: fields[8] as int,
      reorderLevel: fields[9] as int,
      unit: fields[10] as String? ?? 'pcs',
      supplier: fields[11] as String?,
      imageUrl: fields[12] as String?,
      description: fields[13] as String?,
      expiryDate: fields[14] as DateTime?,
      isActive: fields[15] as bool? ?? true,
      searchKeywords: (fields[16] as List?)?.cast<String>() ?? [],
      createdAt: fields[17] as DateTime,
      updatedAt: fields[18] as DateTime,
      createdBy: fields[19] as String,
      updatedBy: fields[20] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer.writeByte(21); // number of fields
    writer
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.name)
      ..writeByte(2)..write(obj.sku)
      ..writeByte(3)..write(obj.barcode)
      ..writeByte(4)..write(obj.categoryId)
      ..writeByte(5)..write(obj.categoryName)
      ..writeByte(6)..write(obj.costPrice)
      ..writeByte(7)..write(obj.sellingPrice)
      ..writeByte(8)..write(obj.quantity)
      ..writeByte(9)..write(obj.reorderLevel)
      ..writeByte(10)..write(obj.unit)
      ..writeByte(11)..write(obj.supplier)
      ..writeByte(12)..write(obj.imageUrl)
      ..writeByte(13)..write(obj.description)
      ..writeByte(14)..write(obj.expiryDate)
      ..writeByte(15)..write(obj.isActive)
      ..writeByte(16)..write(obj.searchKeywords)
      ..writeByte(17)..write(obj.createdAt)
      ..writeByte(18)..write(obj.updatedAt)
      ..writeByte(19)..write(obj.createdBy)
      ..writeByte(20)..write(obj.updatedBy);
  }
}

// ═══════════════════════════════════════════
// Category Adapter (TypeId: 1)
// ═══════════════════════════════════════════
class CategoryAdapter extends TypeAdapter<Category> {
  @override
  final int typeId = 1;

  @override
  Category read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Category(
      id: fields[0] as String,
      name: fields[1] as String,
      description: fields[2] as String?,
      productCount: fields[3] as int? ?? 0,
      createdAt: fields[4] as DateTime,
      updatedAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Category obj) {
    writer.writeByte(6);
    writer
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.name)
      ..writeByte(2)..write(obj.description)
      ..writeByte(3)..write(obj.productCount)
      ..writeByte(4)..write(obj.createdAt)
      ..writeByte(5)..write(obj.updatedAt);
  }
}

// ═══════════════════════════════════════════
// SaleTransaction Adapter (TypeId: 2)
// ═══════════════════════════════════════════
class SaleTransactionAdapter extends TypeAdapter<SaleTransaction> {
  @override
  final int typeId = 2;

  @override
  SaleTransaction read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return SaleTransaction(
      id: fields[0] as String,
      type: fields[1] as String,
      items: (fields[2] as List).cast<SaleItem>(),
      subtotal: fields[3] as double,
      discount: fields[4] as double,
      taxAmount: fields[5] as double,
      total: fields[6] as double,
      paymentMethod: fields[7] as String,
      status: fields[8] as String,
      note: fields[9] as String?,
      createdBy: fields[10] as String,
      createdByName: fields[11] as String,
      createdAt: fields[12] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SaleTransaction obj) {
    writer.writeByte(13);
    writer
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.type)
      ..writeByte(2)..write(obj.items)
      ..writeByte(3)..write(obj.subtotal)
      ..writeByte(4)..write(obj.discount)
      ..writeByte(5)..write(obj.taxAmount)
      ..writeByte(6)..write(obj.total)
      ..writeByte(7)..write(obj.paymentMethod)
      ..writeByte(8)..write(obj.status)
      ..writeByte(9)..write(obj.note)
      ..writeByte(10)..write(obj.createdBy)
      ..writeByte(11)..write(obj.createdByName)
      ..writeByte(12)..write(obj.createdAt);
  }
}

// ═══════════════════════════════════════════
// SaleItem Adapter (TypeId: 3)
// ═══════════════════════════════════════════
class SaleItemAdapter extends TypeAdapter<SaleItem> {
  @override
  final int typeId = 3;

  @override
  SaleItem read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return SaleItem(
      productId: fields[0] as String,
      productName: fields[1] as String,
      sku: fields[2] as String,
      quantity: fields[3] as int,
      unitPrice: fields[4] as double,
      totalPrice: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, SaleItem obj) {
    writer.writeByte(6);
    writer
      ..writeByte(0)..write(obj.productId)
      ..writeByte(1)..write(obj.productName)
      ..writeByte(2)..write(obj.sku)
      ..writeByte(3)..write(obj.quantity)
      ..writeByte(4)..write(obj.unitPrice)
      ..writeByte(5)..write(obj.totalPrice);
  }
}

// ═══════════════════════════════════════════
// StockMovement Adapter (TypeId: 4)
// ═══════════════════════════════════════════
class StockMovementAdapter extends TypeAdapter<StockMovement> {
  @override
  final int typeId = 4;

  @override
  StockMovement read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return StockMovement(
      id: fields[0] as String,
      productId: fields[1] as String,
      productName: fields[2] as String,
      type: fields[3] as String,
      quantityChange: fields[4] as int,
      quantityBefore: fields[5] as int,
      quantityAfter: fields[6] as int,
      reason: fields[7] as String?,
      reference: fields[8] as String?,
      userId: fields[9] as String,
      userName: fields[10] as String,
      source: fields[11] as String,
      createdAt: fields[12] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, StockMovement obj) {
    writer.writeByte(13);
    writer
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.productId)
      ..writeByte(2)..write(obj.productName)
      ..writeByte(3)..write(obj.type)
      ..writeByte(4)..write(obj.quantityChange)
      ..writeByte(5)..write(obj.quantityBefore)
      ..writeByte(6)..write(obj.quantityAfter)
      ..writeByte(7)..write(obj.reason)
      ..writeByte(8)..write(obj.reference)
      ..writeByte(9)..write(obj.userId)
      ..writeByte(10)..write(obj.userName)
      ..writeByte(11)..write(obj.source)
      ..writeByte(12)..write(obj.createdAt);
  }
}

// ═══════════════════════════════════════════
// AppNotification Adapter (TypeId: 5)
// ═══════════════════════════════════════════
class AppNotificationAdapter extends TypeAdapter<AppNotification> {
  @override
  final int typeId = 5;

  @override
  AppNotification read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return AppNotification(
      id: fields[0] as String,
      type: NotificationType.fromString(fields[1] as String?),
      title: fields[2] as String,
      body: fields[3] as String,
      read: fields[4] as bool? ?? false,
      userId: fields[5] as String?,
      createdAt: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, AppNotification obj) {
    writer.writeByte(7);
    writer
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.type.firestoreValue)
      ..writeByte(2)..write(obj.title)
      ..writeByte(3)..write(obj.body)
      ..writeByte(4)..write(obj.read)
      ..writeByte(5)..write(obj.userId)
      ..writeByte(6)..write(obj.createdAt);
  }
}

// ═══════════════════════════════════════════
// ShopSettings Adapter (TypeId: 6)
// ═══════════════════════════════════════════
class ShopSettingsAdapter extends TypeAdapter<ShopSettings> {
  @override
  final int typeId = 6;

  @override
  ShopSettings read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return ShopSettings(
      lowStockThreshold: fields[0] as int? ?? 5,
      currency: fields[1] as String? ?? 'NGN',
      currencySymbol: fields[2] as String? ?? '₦',
      taxRate: fields[3] as double? ?? 0.0,
      receiptFooter: fields[4] as String?,
      enableNotifications: fields[5] as bool? ?? true,
      enableExpiryAlerts: fields[6] as bool? ?? true,
      expiryAlertDays: fields[7] as int? ?? 30,
      updatedAt: fields[8] as DateTime,
      updatedBy: fields[9] as String,
      taxThresholdNotifiedYear: fields[10] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, ShopSettings obj) {
    writer.writeByte(11);
    writer
      ..writeByte(0)..write(obj.lowStockThreshold)
      ..writeByte(1)..write(obj.currency)
      ..writeByte(2)..write(obj.currencySymbol)
      ..writeByte(3)..write(obj.taxRate)
      ..writeByte(4)..write(obj.receiptFooter)
      ..writeByte(5)..write(obj.enableNotifications)
      ..writeByte(6)..write(obj.enableExpiryAlerts)
      ..writeByte(7)..write(obj.expiryAlertDays)
      ..writeByte(8)..write(obj.updatedAt)
      ..writeByte(9)..write(obj.updatedBy)
      ..writeByte(10)..write(obj.taxThresholdNotifiedYear);
  }
}
