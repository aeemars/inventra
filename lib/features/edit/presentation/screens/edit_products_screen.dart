import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/presentation/controllers/inventory_controller.dart';
import '../../../../core/widgets/edit_pin_guard.dart';

class EditProductsScreen extends ConsumerStatefulWidget {
  const EditProductsScreen({super.key});

  @override
  ConsumerState<EditProductsScreen> createState() => _EditProductsScreenState();
}

class _EditProductsScreenState extends ConsumerState<EditProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _isLaunchingScanner = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filterProducts(List<Product> products) {
    final lowerQuery = _query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return products;

    return products.where((p) {
      return p.name.toLowerCase().contains(lowerQuery) ||
          p.sku.toLowerCase().contains(lowerQuery) ||
          (p.barcode?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  Future<void> _showQuickEditDialog(Product product) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _QuickEditDialog(product: product),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$mm/$dd/${date.year}';
  }

  Future<void> _scanBarcodeForSearch() async {
    if (_isLaunchingScanner) return;
    setState(() => _isLaunchingScanner = true);

    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }

      if (!mounted) return;

      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.isPermanentlyDenied
                  ? 'Camera permission is blocked. Enable it from app settings.'
                  : 'Camera permission is required to scan barcodes.',
            ),
            backgroundColor: AppColors.warning,
            action: status.isPermanentlyDenied
                ? SnackBarAction(
                    label: 'Settings',
                    textColor: Colors.white,
                    onPressed: openAppSettings,
                  )
                : null,
          ),
        );
        return;
      }

      final scannedCode = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const _BarcodeSearchScannerScreen(),
        ),
      );

      if (!mounted || scannedCode == null || scannedCode.isEmpty) return;

      _searchController.text = scannedCode;
      setState(() => _query = scannedCode);
    } finally {
      if (mounted) {
        setState(() => _isLaunchingScanner = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return EditPinGuard(
      child: Scaffold(
        backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Edit Products',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: context.appTextPrimary,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPaddingH,
          AppSizes.md,
          AppSizes.screenPaddingH,
          AppSizes.lg,
        ),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search by product name, SKU, or barcode',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: context.appSurfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.appCardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.appCardBorder),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _isLaunchingScanner ? null : _scanBarcodeForSearch,
                icon: _isLaunchingScanner
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.qr_code_scanner_rounded),
                label: Text(_isLaunchingScanner
                    ? 'Opening scanner...'
                    : 'Scan barcode'),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Expanded(
              child: productsAsync.when(
                data: (products) {
                  final activeProducts = _filterProducts(
                      products.where((p) => p.isActive).toList());

                  if (activeProducts.isEmpty) {
                    return Center(
                      child: Text(
                        'No products available for editing.',
                        style: TextStyle(color: context.appTextSecondary),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: activeProducts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final product = activeProducts[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.appCardBorder),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          title: Text(
                            product.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Price: ₦${product.sellingPrice.toStringAsFixed(2)}\n'
                              'Expiry: ${_formatDate(product.expiryDate).isEmpty ? 'Not set' : _formatDate(product.expiryDate)}',
                              style: TextStyle(
                                color: context.appTextSecondary,
                              ),
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            iconColor: context.appTextPrimary,
                            onSelected: (value) {
                              if (value == 'quick') {
                                _showQuickEditDialog(product);
                              }
                              if (value == 'full') {
                                context.push('/inventory/${product.id}/edit');
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'quick',
                                child: Text('Quick Edit'),
                              ),
                              PopupMenuItem(
                                value: 'full',
                                child: Text('Open Full Editor'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (err, _) => Center(
                  child: Text(
                    'Failed to load products: $err',
                    style: const TextStyle(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

class _BarcodeSearchScannerScreen extends StatefulWidget {
  const _BarcodeSearchScannerScreen();

  @override
  State<_BarcodeSearchScannerScreen> createState() =>
      _BarcodeSearchScannerScreenState();
}

class _BarcodeSearchScannerScreenState
    extends State<_BarcodeSearchScannerScreen> {
  late final MobileScannerController _controller;
  bool _hasResult = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_hasResult) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue ?? barcode.displayValue;
      if (code == null || code.isEmpty) {
        continue;
      }

      _hasResult = true;
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
          ),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xB3000000),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Align the barcode in the frame. The code will be applied automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickEditDialog extends ConsumerStatefulWidget {
  final Product product;

  const _QuickEditDialog({
    required this.product,
  });

  @override
  ConsumerState<_QuickEditDialog> createState() => _QuickEditDialogState();
}

class _QuickEditDialogState extends ConsumerState<_QuickEditDialog> {
  late final TextEditingController _priceController;
  late final TextEditingController _expiryController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.product.sellingPrice.toStringAsFixed(2),
    );
    _expiryController = TextEditingController(
      text: _formatDate(widget.product.expiryDate),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$mm/$dd/${date.year}';
  }

  DateTime? _parseDate(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (match == null) return null;

    final month = int.tryParse(match.group(1)!);
    final day = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);

    if (month == null || day == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    return DateTime(year, month, day);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.product.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _priceController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Selling Price',
              hintText: 'e.g. 12.99',
              prefixText: '₦ ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _expiryController,
            decoration: const InputDecoration(
              labelText: 'Expiry Date',
              hintText: 'mm/dd/yyyy (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final newPrice = double.tryParse(_priceController.text.trim());
    if (newPrice == null || newPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid price.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final parsedExpiry = _parseDate(_expiryController.text);
    if (_expiryController.text.trim().isNotEmpty &&
        parsedExpiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use date format mm/dd/yyyy.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = ref.read(currentUserProvider)?.uid ?? '';
      final updated = widget.product.copyWith(
        sellingPrice: newPrice,
        expiryDate: parsedExpiry,
        updatedAt: DateTime.now(),
        updatedBy: userId,
      );

      final success = await ref
          .read(inventoryControllerProvider.notifier)
          .updateProduct(updated);

      if (!mounted) return;

      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product updated.'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update product.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
