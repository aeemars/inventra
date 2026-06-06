import '../entities/product.dart';
import '../entities/category.dart';

/// Product repository contract
abstract class ProductRepository {
  /// Get all products for a shop
  Stream<List<Product>> watchProducts(String shopId);

  /// Get single product
  Future<Product?> getProduct(String shopId, String productId);

  /// Search product by barcode or SKU
  Future<Product?> findByBarcode(String shopId, String barcode);

  /// Add a new product
  Future<Product> addProduct(String shopId, Product product);

  /// Update a product
  Future<void> updateProduct(String shopId, Product product);

  /// Delete a product
  Future<void> deleteProduct(String shopId, String productId);

  /// Update stock quantity atomically
  Future<void> updateStock(String shopId, String productId, int quantityChange);

  /// Restock product with audit movement record
  Future<void> restockWithRecord({
    required String shopId,
    required String productId,
    required String productName,
    required int quantity,
    required String userId,
  });

  /// Search products
  Future<List<Product>> searchProducts(String shopId, String query);

  // ── Categories ──
  Stream<List<Category>> watchCategories(String shopId);
  Future<Category> addCategory(String shopId, Category category);
  Future<void> updateCategory(String shopId, Category category);
  Future<void> deleteCategory(String shopId, String categoryId);
}
