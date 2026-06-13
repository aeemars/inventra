import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/entities/product.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../controllers/inventory_controller.dart';
import '../../../../core/widgets/edit_pin_guard.dart';

class AddEditProductScreen extends ConsumerStatefulWidget {
  final String? productId;
  final String? initialBarcode;

  const AddEditProductScreen({super.key, this.productId, this.initialBarcode});

  @override
  ConsumerState<AddEditProductScreen> createState() =>
      _AddEditProductScreenState();
}

class _AddEditProductScreenState extends ConsumerState<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _upcController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _reorderLevelController = TextEditingController();
  final _unitController = TextEditingController(text: 'pcs');
  final _supplierController = TextEditingController();
  final _descriptionController = TextEditingController();

  // New details fields matching wireframe
  final _categoryController = TextEditingController();
  final _expiryController = TextEditingController();

  int _quantity = 1;
  Product? _existingProduct;
  Timer? _upcDebounce;
  String? _dismissedBarcode;
  bool _masterDataExpanded = false;
  bool _isLookingUp = false;

  bool get isEditing => widget.productId != null;

  bool get _isScannedExistingProduct =>
      !isEditing && _existingProduct != null;

  String get _displayProductName => _isScannedExistingProduct
      ? _existingProduct!.name
      : (_nameController.text.isEmpty ? 'Product Name' : _nameController.text);

  String get _verificationLabel =>
      _isScannedExistingProduct ? 'Product Verified' : 'New Product Draft';

  Color get _verificationColor =>
      _isScannedExistingProduct ? AppColors.success : Colors.orange.shade700;

  void _onHeaderFieldsChanged() {
    if (mounted) setState(() {});
  }

  void _onUpcFieldChanged() {
    _upcDebounce?.cancel();
    final text = _upcController.text.trim();
    if (text.length < 3) return; // don't search on very short input
    _upcDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _lookupBarcode(text);
    });
  }

  @override
  void initState() {
    super.initState();
    if (!isEditing && widget.initialBarcode != null) {
      _barcodeController.text = widget.initialBarcode!;
      _upcController.text = widget.initialBarcode!;
      _isLookingUp = true; // guard against first-render flash
      _lookupBarcode(widget.initialBarcode!);
    }
    // Only activate for new products not coming from scanner
    if (!isEditing && widget.initialBarcode == null) {
      _upcController.addListener(_onUpcFieldChanged);
    }
    if (isEditing) {
      _loadProduct();
    }
    _nameController.addListener(_onHeaderFieldsChanged);
    _categoryController.addListener(_onHeaderFieldsChanged);
    _upcController.addListener(_onHeaderFieldsChanged);
  }

  /// Look up an existing product by barcode and pre-populate fields if found.
  Future<void> _lookupBarcode(String barcode) async {
    if (barcode == _dismissedBarcode) return;
    final shopId = ref.read(currentShopIdProvider);
    if (shopId == null) return;

    try {
      final product = await ref
          .read(productRepositoryProvider)
          .findByBarcode(shopId, barcode);

      if (product != null && mounted) {
        setState(() {
          _existingProduct = product;
          _nameController.text = product.name;
          _costPriceController.text = product.costPrice.toString();
          _sellingPriceController.text = product.sellingPrice.toString();
          _reorderLevelController.text = product.reorderLevel.toString();
          _unitController.text = product.unit;
          _supplierController.text = product.supplier ?? '';
          _descriptionController.text = product.description ?? '';
          _categoryController.text = product.categoryName ?? product.categoryId ?? '';
          _expiryController.text = _formatDateForInput(product.expiryDate);
        });

        // Show dialog regardless of whether barcode came from scanner or manual entry
        if (!isEditing && mounted) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Product already exists'),
              content: Text(
                '"${product.name}" is already in your inventory with '
                '${product.quantity} ${product.unit} in stock.\n\n'
                'How many units would you like to add?',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _existingProduct = null;
                      _dismissedBarcode = barcode;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Create new anyway'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _nameController.text = product.name;
                    setState(() {});
                  },
                  child: const Text('Add units'),
                ),
              ],
            ),
          );
        }
      }
    } finally {
      // Always clear the loading guard — even if product was not found
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  Future<void> _loadProduct() async {
    final shopId = ref.read(currentShopIdProvider);
    if (shopId == null) return;

    final product = await ref
        .read(productRepositoryProvider)
        .getProduct(shopId, widget.productId!);

    if (product != null && mounted) {
      setState(() {
        _existingProduct = product;
        _nameController.text = product.name;
        _upcController.text = product.sku;
        _barcodeController.text = product.barcode ?? '';
        _costPriceController.text = product.costPrice.toString();
        _sellingPriceController.text = product.sellingPrice.toString();
        _quantity = product.quantity > 0 ? product.quantity : 1;
        _reorderLevelController.text = product.reorderLevel.toString();
        _unitController.text = product.unit;
        _supplierController.text = product.supplier ?? '';
        _descriptionController.text = product.description ?? '';
        _categoryController.text = product.categoryName ?? product.categoryId ?? '';
        _expiryController.text = _formatDateForInput(product.expiryDate);
      });
    }
  }

  @override
  void dispose() {
    _upcDebounce?.cancel();
    _nameController.removeListener(_onHeaderFieldsChanged);
    _categoryController.removeListener(_onHeaderFieldsChanged);
    _upcController.removeListener(_onHeaderFieldsChanged);

    _nameController.dispose();
    _upcController.dispose();
    _barcodeController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _reorderLevelController.dispose();
    _unitController.dispose();
    _supplierController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) {
      if (!_masterDataExpanded) {
        setState(() => _masterDataExpanded = true);
      }
      if (_nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Product name is required — expand "Master Data" to fill it in'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
      return;
    }

    // ── Pre-flight guards ──
    final shopId = ref.read(currentShopIdProvider);
    if (shopId == null || shopId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account has no shop linked. Please re-login or contact support.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final userId = ref.read(currentUserProvider)?.uid ?? '';
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired. Please sign in again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    // ── end guards ──

    final now = DateTime.now();

    final product = Product(
      id: _existingProduct?.id ?? '',
      name: _nameController.text.trim(),
      sku: _upcController.text.trim().isNotEmpty
          ? _upcController.text.trim()
          : 'INV-${DateTime.now().millisecondsSinceEpoch}',
      barcode: _barcodeController.text.trim().isEmpty
          ? null
          : _barcodeController.text.trim(),
      categoryId: _categoryController.text.trim().isEmpty
          ? null
          : _categoryController.text.trim(),
      categoryName: _categoryController.text.trim().isEmpty
          ? null
          : _categoryController.text.trim(),
      costPrice: double.tryParse(_costPriceController.text) ?? 0,
      sellingPrice: double.tryParse(_sellingPriceController.text) ?? 0,
      quantity: _quantity,
      reorderLevel: int.tryParse(_reorderLevelController.text) ?? 5,
      unit: _unitController.text.trim(),
      supplier: _supplierController.text.trim().isEmpty
          ? null
          : _supplierController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      expiryDate: _parseExpiryDate(_expiryController.text),
      createdAt: _existingProduct?.createdAt ?? now,
      updatedAt: now,
      createdBy: _existingProduct?.createdBy ?? userId,
      updatedBy: userId,
    );

    bool success;
    if (isEditing || _isScannedExistingProduct) {
      // For scanned existing products, update stock rather than creating a duplicate
      if (_isScannedExistingProduct) {
        success = await ref
            .read(inventoryControllerProvider.notifier)
            .adjustStock(
              _existingProduct!.id,
              _quantity,
              productName: _existingProduct!.name,
            );
      } else {
        success = await ref
            .read(inventoryControllerProvider.notifier)
            .updateProduct(product);
      }
    } else {
      final result = await ref
          .read(inventoryControllerProvider.notifier)
          .addProduct(product);
      success = result != null;
    }

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? 'Product updated!' : 'Product added!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/inventory');
    }
  }

  void _incrementQty() => setState(() => _quantity++);
  void _decrementQty() {
    if (_quantity > 1) setState(() => _quantity--);
  }

  String _formatDateForInput(DateTime? date) {
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
  }

  DateTime? _parseExpiryDate(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final slashMatch =
        RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (slashMatch != null) {
      final month = int.tryParse(slashMatch.group(1)!);
      final day = int.tryParse(slashMatch.group(2)!);
      final year = int.tryParse(slashMatch.group(3)!);
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return DateTime.tryParse(text);
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(inventoryControllerProvider);

    ref.listen<InventoryState>(inventoryControllerProvider, (_, state) {
      if (state.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.error!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    if (_isLookingUp) {
      return Scaffold(
        backgroundColor: context.appBackground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: AppSizes.md),
              Text(
                'Checking inventory...',
                style: AppTypography.bodyMedium
                    .copyWith(color: context.appTextSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final scaffold = Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.appTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? 'Edit Product' : 'New Product',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: context.appTextPrimary)),
            if (isEditing || _upcController.text.isNotEmpty)
              Text(
                  'ID: #${_upcController.text.isEmpty ? 'UPC-NEW' : _upcController.text}',
                  style: TextStyle(
                      color: context.appTextSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: context.appTextPrimary),
            onPressed: () {},
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSizes.screenPaddingH,
                  AppSizes.md, AppSizes.screenPaddingH, 110),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // IDENTIFIED PRODUCT CARD
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Graphic placeholder
                          Container(
                            width: 48,
                            height: 64,
                            decoration: BoxDecoration(
                              color: context.appInputFill,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _existingProduct?.imageUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                        _existingProduct!.imageUrl!,
                                        fit: BoxFit.cover))
                                : const Icon(Icons.local_drink_rounded,
                                    color: Colors.orange, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _displayProductName,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: context.appTextPrimary,
                                            height: 1.2),
                                      ),
                                    ),
                                    if (_isScannedExistingProduct) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color:
                                              AppColors.success.withAlpha(38),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text('IN\nSTOCK',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: AppColors.success,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                height: 1.1)),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Category: ${_categoryController.text.isEmpty ? 'Various' : _categoryController.text} | UPC: ${_upcController.text.isEmpty ? '...' : _upcController.text}',
                                  style: TextStyle(
                                      color: context.appTextSecondary, fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.check_circle_outline_rounded,
                                        color: _verificationColor, size: 16),
                                    const SizedBox(width: 4),
                                    Text(_verificationLabel,
                                        style: TextStyle(
                                            color: _verificationColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    // QUANTITY TO ADD
                    Text('Quantity to Add',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16, color: context.appTextPrimary)),
                    const SizedBox(height: AppSizes.md),
                    AppCard(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Minus button
                          GestureDetector(
                            onTap: _decrementQty,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: context.appInputFill,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.remove_rounded,
                                  color: context.appTextPrimary, size: 28),
                            ),
                          ),
                          // Value text
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$_quantity',
                                  style: TextStyle(
                                      fontSize: 24,
                                      color: context.appTextPrimary,
                                      fontWeight: FontWeight.w800)),
                              Text('units',
                                  style: TextStyle(
                                      fontSize: 12, color: context.appTextSecondary)),
                            ],
                          ),
                          // Plus button
                          GestureDetector(
                            onTap: _incrementQty,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.add_rounded,
                                  color: Colors.white, size: 28),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    // DETAILS
                    Text('Details',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16, color: context.appTextPrimary)),
                    const SizedBox(height: AppSizes.md),

                    _buildWireframeInput(
                      label: 'Category',
                      hint: 'e.g. Beverages, Soda',
                      controller: _categoryController,
                      icon: Icons.category_rounded,
                    ),
                    const SizedBox(height: AppSizes.lg),

                    _buildWireframeInput(
                      label: 'Expiration Date (Optional)',
                      hint: 'mm/dd/yyyy',
                      controller: _expiryController,
                      icon: Icons.calendar_today_rounded, // calendar
                    ),

                    // Essential master fields below so we don't break functionality
                    const SizedBox(height: AppSizes.xl),
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        iconColor: context.appTextPrimary,
                        collapsedIconColor: context.appTextPrimary,
                        initiallyExpanded: _masterDataExpanded,
                        onExpansionChanged: (expanded) {
                          _masterDataExpanded = expanded;
                        },
                        title: Text('Master Data (Edit Product Info)',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14, color: context.appTextPrimary)),
                        children: [
                          _buildWireframeInput(
                              label: 'Name',
                              hint: 'Product Name',
                              controller: _nameController,
                              isRequired: true),
                          const SizedBox(height: AppSizes.md),
                          _buildWireframeInput(
                              label: 'UPC',
                              hint: 'Auto-generated if left blank',
                              controller: _upcController),
                          const SizedBox(height: AppSizes.md),
                          Row(
                            children: [
                              Expanded(
                                  child: _buildWireframeInput(
                                      label: 'Selling Price (₦)',
                                      hint: '0.00',
                                      controller: _sellingPriceController)),
                              const SizedBox(width: AppSizes.md),
                              Expanded(
                                  child: _buildWireframeInput(
                                      label: 'Cost Price (₦)',
                                      hint: '0.00',
                                      controller: _costPriceController)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // BOTTOM CONFIRMATION SHEET
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(context).padding.bottom + 8),
              decoration: BoxDecoration(
                color: context.appSurfaceRaised,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 10,
                      offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total items adding:',
                          style:
                              TextStyle(color: context.appTextSecondary, fontSize: 13)),
                      Text('$_quantity Unit${_quantity > 1 ? 's' : ''}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15, color: context.appTextPrimary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: controllerState.isLoading ? null : _onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: controllerState.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                          _isScannedExistingProduct
                              ? 'Confirm Restock'
                              : 'Confirm Addition',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isEditing) {
      return EditPinGuard(child: scaffold);
    }
    return scaffold;
  }

  Widget _buildWireframeInput({
    required String label,
    required String hint,
    required TextEditingController controller,
    IconData? icon,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.crop_free_rounded,
                size: 14, color: context.appTextTertiary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: context.appTextSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: TextStyle(color: context.appTextPrimary, fontSize: 14),
          validator: isRequired ? (v) => v!.isEmpty ? 'Required' : null : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.appTextTertiary, fontSize: 14),
            suffixIcon: icon != null
                ? Icon(icon, color: context.appTextTertiary, size: 20)
                : null,
            filled: true,
            fillColor: context.appInputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.appCardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.appCardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
