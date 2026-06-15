import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../core/router/scanner_route_access.dart';
import '../../../../core/utils/debouncer.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../inventory/presentation/controllers/inventory_controller.dart';
import '../../../inventory/domain/entities/product.dart';
import '../controllers/scanner_controller.dart';

/// Scanner screen with live camera barcode scanning:
/// - Camera permission handling
/// - Flashlight toggle
/// - Manual barcode entry
/// - Debounced scan detection
/// - Product lookup (cache-first via Firestore offline)
/// - Inline quick-sell and restock flows with atomic transactions
/// - Scan history persistence
class ScannerScreen extends ConsumerStatefulWidget {
  final String? reason;

  const ScannerScreen({super.key, this.reason});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _cameraController;
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 400));
  bool _isProcessing = false;
  bool _torchEnabled = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  ScanIntent? _selectedIntent;

  // ── Consensus-based multi-read scanning ──
  static const int _consensusThreshold = 2;
  final Map<String, int> _scanConsensus = {};
  DateTime? _lastConsensusReset;

  // Camera permission state
  _CameraPermState _permState = _CameraPermState.checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkCameraPermission();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.reason == 'restricted') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Use scanner flow to open Add Product or New Sale pages.'),
            backgroundColor: AppColors.warning,
          ),
        );
        context.replace('/scanner');
      }

      if (mounted && _selectedIntent == null) {
        _selectScanIntent();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permission when returning from settings
    if (state == AppLifecycleState.resumed &&
        _permState == _CameraPermState.permanentlyDenied) {
      _checkCameraPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debouncer.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _checkCameraPermission() async {
    setState(() => _permState = _CameraPermState.checking);

    var status = await Permission.camera.status;

    if (status.isGranted) {
      _initCamera();
      return;
    }

    if (status.isPermanentlyDenied) {
      setState(() => _permState = _CameraPermState.permanentlyDenied);
      return;
    }

    // Request permission
    status = await Permission.camera.request();

    if (status.isGranted) {
      _initCamera();
    } else if (status.isPermanentlyDenied) {
      setState(() => _permState = _CameraPermState.permanentlyDenied);
    } else {
      setState(() => _permState = _CameraPermState.denied);
    }
  }

  void _initCamera() {
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.qrCode,
      ],
    );
    setState(() => _permState = _CameraPermState.granted);
  }

  // ── Barcode extraction & validation helpers ──

  /// Extract the most reliable string from a Barcode object.
  /// Prefers rawBytes decoded as UTF-8 (bypasses platform string mangling),
  /// then falls back to rawValue / displayValue.
  String? _extractBarcodeValue(Barcode barcode) {
    // Try rawDecodedBytes first — the actual binary data from the scanner
    final barcodeBytes = barcode.rawDecodedBytes;
    if (barcodeBytes != null) {
      try {
        // BarcodeBytes is a sealed class — extract the Uint8List from the subtype
        final List<int>? bytes = switch (barcodeBytes) {
          DecodedBarcodeBytes(:final bytes) => bytes,
          DecodedVisionBarcodeBytes(:final bytes) => bytes,
        };
        if (bytes != null && bytes.isNotEmpty) {
          final decoded = utf8.decode(bytes, allowMalformed: false).trim();
          if (decoded.isNotEmpty) return decoded;
        }
      } catch (_) {
        // Fall through to string properties
      }
    }
    return (barcode.rawValue ?? barcode.displayValue)?.trim();
  }

  /// Normalize UPC-A ↔ EAN-13 so the same physical barcode always produces
  /// the same string regardless of platform.
  /// Convention: always store as EAN-13 (13 digits with leading 0 if needed).
  String _normalizeBarcode(String code, BarcodeFormat? format) {
    // Only normalize pure-digit codes of length 12 or 13
    if (!RegExp(r'^\d{12,13}$').hasMatch(code)) return code;

    if (code.length == 12) {
      // UPC-A → EAN-13: prepend leading zero
      return '0$code';
    }
    return code;
  }

  /// Validate the check digit for EAN-8 / EAN-13 / UPC-A barcodes.
  /// Returns true for non-EAN codes (no validation needed) or valid check digits.
  bool _validateEanCheckDigit(String code) {
    // Only validate pure-digit codes of standard lengths
    if (!RegExp(r'^\d+$').hasMatch(code)) return true;
    if (code.length != 8 && code.length != 12 && code.length != 13) return true;

    // Standard EAN/UPC check digit algorithm
    final digits = code.split('').map(int.parse).toList();
    final payload = digits.sublist(0, digits.length - 1);
    final expectedCheck = digits.last;

    int sum = 0;
    for (int i = 0; i < payload.length; i++) {
      final weight = (payload.length - i).isOdd ? 3 : 1;
      sum += payload[i] * weight;
    }
    final calculatedCheck = (10 - (sum % 10)) % 10;
    return calculatedCheck == expectedCheck;
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing || _selectedIntent == null) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawCode = _extractBarcodeValue(barcodes.first);
    if (rawCode == null || rawCode.isEmpty) return;

    // Cooldown: ignore all detections for 400ms after a successful scan
    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 400) {
      return;
    }

    // Dedup: don't re-process the same code until reset
    if (rawCode == _lastScannedCode) return;

    // Validate EAN/UPC check digit — reject misreads immediately
    if (!_validateEanCheckDigit(rawCode)) return;

    // Normalize UPC-A ↔ EAN-13
    final code = _normalizeBarcode(rawCode, barcodes.first.format);

    // Auto-reset consensus if we haven't seen any detection for 2 seconds
    if (_lastConsensusReset != null &&
        now.difference(_lastConsensusReset!).inSeconds >= 2) {
      _scanConsensus.clear();
    }
    _lastConsensusReset = now;

    // Increment consensus counter for this code
    _scanConsensus[code] = (_scanConsensus[code] ?? 0) + 1;

    // Only accept once consensus threshold is reached
    if (_scanConsensus[code]! < _consensusThreshold) return;

    // Consensus reached — process
    _scanConsensus.clear();
    _lastScanTime = now;
    _processBarcode(code);
  }

  Future<void> _processBarcode(String barcode) async {
    if (_isProcessing) return;

    final selectedIntent = _selectedIntent;
    if (selectedIntent == null) {
      _showIntentRequiredSnackBar();
      return;
    }

    setState(() {
      _isProcessing = true;
      _lastScannedCode = barcode;
    });

    if (selectedIntent == ScanIntent.addProduct) {
      final shopId = ref.read(currentShopIdProvider);
      if (shopId == null) {
        setState(() => _isProcessing = false);
        return;
      }

      try {
        final product = await ref
            .read(productRepositoryProvider)
            .findByBarcode(shopId, barcode);

        if (!mounted) {
          _isProcessing = false;
          return;
        }

        ref.read(scannerControllerProvider.notifier).saveScanEntry(
              barcodeValue: barcode,
              scanIntent: 'addProduct',
              matchedProductId: product?.id,
              matchedProductName: product?.name,
            );

        if (product != null) {
          // Product exists — show restock sheet; do NOT navigate to add screen
          _showAddUnitsSheet(product);
        } else {
          // Not found by scanner's lookup — navigate to add screen.
          // If the add screen's own (fresher) lookup finds a duplicate, it pops
          // immediately with the Product, and we show the sheet here instead.
          ref
              .read(scannerRouteAccessProvider.notifier)
              .grant(ScannerProtectedRoute.addProduct);
          final result = await context.push<Product?>('/inventory/add?barcode=$barcode');
          if (mounted) {
            setState(() {
              _lastScannedCode = null;
              _scanConsensus.clear();
            });
          }
          if (result != null && mounted) {
            _showAddUnitsSheet(result);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lookup error: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
      return;
    }

    // Sale intent: look up product
    final shopId = ref.read(currentShopIdProvider);
    if (shopId == null) {
      setState(() => _isProcessing = false);
      return;
    }

    try {
      final product = await ref
          .read(productRepositoryProvider)
          .findByBarcode(shopId, barcode);

      if (!mounted) {
        _isProcessing = false;
        return;
      }

      // Save scan history
      ref.read(scannerControllerProvider.notifier).saveScanEntry(
            barcodeValue: barcode,
            scanIntent: 'sale',
            matchedProductId: product?.id,
            matchedProductName: product?.name,
          );

      if (product != null) {
        _showQuickSellSheet(product);
      } else {
        _showProductNotFoundSheet(barcode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Lookup error: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Product Not Found Sheet ──

  void _showProductNotFoundSheet(String barcode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(AppSizes.xxl),
        decoration: BoxDecoration(
          color: ctx.appSurfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.appDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSizes.xxl),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.search_off_rounded,
                  color: AppColors.warning, size: 32),
            ),
            const SizedBox(height: AppSizes.lg),
            Text('Product Not Found', style: AppTypography.h4.copyWith(color: ctx.appTextPrimary)),
            const SizedBox(height: AppSizes.sm),
            Text(
              'No product matches barcode:\n$barcode',
              style: AppTypography.bodyMedium
                  .copyWith(color: ctx.appTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSizes.xxl),
            AppButton(
              label: 'Create New Product',
              icon: Icons.add_rounded,
              onPressed: () {
                Navigator.pop(ctx);
                ref
                    .read(scannerRouteAccessProvider.notifier)
                    .grant(ScannerProtectedRoute.addProduct);
                context.push('/inventory/add?barcode=$barcode');
              },
            ),
            const SizedBox(height: AppSizes.md),
            AppButton(
              label: 'Scan Again',
              isOutlined: true,
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _lastScannedCode = null;
                  _scanConsensus.clear();
                });
              },
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    ).whenComplete(() {
      // Reset when sheet is dismissed by any means (swipe, back, button)
      if (mounted) {
        setState(() {
          _lastScannedCode = null;
          _scanConsensus.clear();
        });
      }
    });
  }

  void _showAddUnitsSheet(Product product) {
    int qty = 1;
    final qtyController = TextEditingController(text: '1');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(AppSizes.xxl),
            decoration: BoxDecoration(
              color: ctx.appSurfaceRaised,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: ctx.appDivider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                // Product found badge
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.inventory_2_rounded,
                      color: AppColors.success, size: 28),
                ),
                const SizedBox(height: AppSizes.md),
                Text('Product Found',
                    style: AppTypography.h4.copyWith(color: ctx.appTextPrimary)),
                const SizedBox(height: AppSizes.sm),
                Text(
                  product.name,
                  style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600, color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Current stock: ${product.quantity} ${product.unit}',
                  style: AppTypography.bodySmall
                      .copyWith(color: ctx.appTextSecondary),
                ),
                const SizedBox(height: AppSizes.xxl),
                // Quantity selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () {
                        if (qty > 1) {
                          setSheetState(() {
                            qty--;
                            qtyController.text = '$qty';
                          });
                        }
                      },
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      color: AppColors.primary,
                      iconSize: 32,
                    ),
                    const SizedBox(width: AppSizes.md),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: AppTypography.h2.copyWith(color: ctx.appTextPrimary),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            setSheetState(() => qty = parsed);
                          }
                        },
                        onTap: () => qtyController.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: qtyController.text.length,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    IconButton(
                      onPressed: () {
                        setSheetState(() {
                          qty++;
                          qtyController.text = '$qty';
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: AppColors.primary,
                      iconSize: 32,
                    ),
                  ],
                ),
                Text(
                  'Units to add',
                  style: AppTypography.bodySmall
                      .copyWith(color: ctx.appTextTertiary),
                ),
                const SizedBox(height: AppSizes.xxl),
                AppButton(
                  label: 'Confirm Restock',
                  icon: Icons.add_rounded,
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final success = await ref
                        .read(inventoryControllerProvider.notifier)
                        .adjustStock(
                          product.id,
                          qty,
                          productName: product.name,
                        );
                    if (mounted) {
                      _showResultSnackBar(
                        success
                            ? 'Added $qty ${product.unit} to ${product.name}'
                            : 'Restock failed. Please try again.',
                        success,
                      );
                      setState(() {
                        _lastScannedCode = null;
                        _scanConsensus.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSizes.md),
                // Escape hatch: create a separate product entry anyway
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref
                          .read(scannerRouteAccessProvider.notifier)
                          .grant(ScannerProtectedRoute.addProduct);
                      context.push(
                          '/inventory/add?barcode=${product.barcode ?? product.sku}&forceNew=true');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ctx.appTextPrimary,
                      side: BorderSide(color: ctx.appCardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                    ),
                    child: Text(
                      'Add as New Product Instead',
                      style: AppTypography.labelLarge.copyWith(
                        color: ctx.appTextPrimary,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      qtyController.dispose();
      if (mounted) {
        setState(() {
          _lastScannedCode = null;
          _scanConsensus.clear();
        });
      }
    });
  }

  // ── Quick Sell Sheet ──

  void _showQuickSellSheet(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuickSellSheet(
        product: product,
        onConfirm: (quantity) async {
          Navigator.pop(ctx);
          final success =
              await ref.read(scannerControllerProvider.notifier).sellProduct(
                    productId: product.id,
                    productName: product.name,
                    productSku: product.sku,
                    unitPrice: product.sellingPrice,
                    quantity: quantity,
                  );
          if (mounted) {
            final state = ref.read(scannerControllerProvider);
            _showResultSnackBar(state.message ?? '', success);
            ref.read(scannerControllerProvider.notifier).reset();
            setState(() {
              _lastScannedCode = null;
              _scanConsensus.clear();
            });
            if (success) {
              context.go('/dashboard');
            }
          }
        },
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _lastScannedCode = null;
          _scanConsensus.clear();
        });
      }
    });
  }

  // ── Manual Entry Dialog ──

  void _showManualEntry() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Entry'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Barcode / SKU',
            hintText: 'Enter barcode or SKU',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = controller.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(ctx);
                _processBarcode(code);
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  // ── Intent Selection ──

  Future<void> _selectScanIntent() async {
    final selected = await showModalBottomSheet<ScanIntent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScanIntentSheet(initialIntent: _selectedIntent),
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedIntent = selected;
        _lastScannedCode = null;
        _scanConsensus.clear();
      });
    }
  }

  void _showIntentRequiredSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select scan purpose first: Add Product or New Sale.'),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  void _showResultSnackBar(String message, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Permission states
    if (_permState == _CameraPermState.checking) {
      return const Scaffold(
        backgroundColor: AppColors.scannerDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight),
        ),
      );
    }

    if (_permState == _CameraPermState.denied ||
        _permState == _CameraPermState.permanentlyDenied) {
      return _CameraPermissionView(
        isPermanent: _permState == _CameraPermState.permanentlyDenied,
        onRequestPermission: _checkCameraPermission,
        onOpenSettings: () => openAppSettings(),
        onBack: () => context.go('/dashboard'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scannerDark,
      body: Stack(
        children: [
          // ── Camera View ──
          if (_cameraController != null)
            MobileScanner(
              controller: _cameraController!,
              onDetect: _onBarcodeDetected,
            ),

          // ── Scan Overlay ──
          _ScanOverlay(isProcessing: _isProcessing),

          // ── Top Bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.lg, vertical: AppSizes.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.white, size: 28),
                      onPressed: () => context.go('/dashboard'),
                    ),
                    Text(
                        _selectedIntent == ScanIntent.addProduct
                            ? 'Scan for New Product'
                            : _selectedIntent == ScanIntent.newSale
                                ? 'Scan for New Sale'
                                : 'Select Scan Purpose',
                        style:
                            AppTypography.h4.copyWith(color: AppColors.white)),
                    IconButton(
                      icon: Icon(
                        _torchEnabled
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: AppColors.white,
                        size: 28,
                      ),
                      onPressed: () {
                        _cameraController?.toggleTorch();
                        setState(() => _torchEnabled = !_torchEnabled);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Processing indicator ──
          if (_isProcessing)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryLight,
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),

          // ── Bottom Panel ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  AppSizes.xxl,
                  AppSizes.xxl,
                  AppSizes.xxl,
                  MediaQuery.of(context).padding.bottom + AppSizes.xl),
              decoration: BoxDecoration(
                color: AppColors.scannerDark.withValues(alpha: 0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedIntent == ScanIntent.addProduct
                        ? 'Scanned code will open New Product form'
                        : _selectedIntent == ScanIntent.newSale
                            ? 'Identify Product for a New Sale'
                            : 'Choose what this scan is for',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.md),

                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: _selectedIntent == null
                          ? 'Select Scan Purpose'
                          : 'Change Scan Purpose',
                      icon: Icons.swap_horiz_rounded,
                      isOutlined: true,
                      onPressed: _selectScanIntent,
                    ),
                  ),
                  const SizedBox(height: AppSizes.lg),

                  // ── Action Buttons ──
                  Row(
                    children: [
                      Expanded(
                        child: _BottomActionButton(
                          icon: Icons.keyboard_rounded,
                          label: 'Manual Entry',
                          onTap: _showManualEntry,
                        ),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: _BottomActionButton(
                          icon: Icons.history_rounded,
                          label: 'Scan History',
                          onTap: () => context.push('/scan-history'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),

                  Row(
                    children: [
                      Expanded(
                        child: _BottomActionButton(
                          icon: Icons.add_box_rounded,
                          label: 'Add Product',
                          isActive: _selectedIntent == ScanIntent.addProduct,
                          onTap: () {
                            setState(() {
                              _selectedIntent = ScanIntent.addProduct;
                              _lastScannedCode = null;
                              _scanConsensus.clear();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: _BottomActionButton(
                          icon: Icons.point_of_sale_rounded,
                          label: 'New Sale',
                          isActive: _selectedIntent == ScanIntent.newSale,
                          onTap: () {
                            setState(() {
                              _selectedIntent = ScanIntent.newSale;
                              _lastScannedCode = null;
                              _scanConsensus.clear();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Camera Permission State
// ═══════════════════════════════════════════════════════════════

enum _CameraPermState { checking, granted, denied, permanentlyDenied }

class _CameraPermissionView extends StatelessWidget {
  final bool isPermanent;
  final VoidCallback onRequestPermission;
  final VoidCallback onOpenSettings;
  final VoidCallback onBack;

  const _CameraPermissionView({
    required this.isPermanent,
    required this.onRequestPermission,
    required this.onOpenSettings,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scannerDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.camera_alt_outlined,
                    color: AppColors.warning, size: 40),
              ),
              const SizedBox(height: AppSizes.xxl),
              Text(
                'Camera Permission Required',
                style: AppTypography.h3.copyWith(color: AppColors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                isPermanent
                    ? 'Camera access has been permanently denied. Please enable it in your device settings to use the scanner.'
                    : 'Inventra needs camera access to scan barcodes and QR codes for product identification.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.white.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSizes.xxxl),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: isPermanent ? 'Open Settings' : 'Grant Permission',
                  icon: isPermanent
                      ? Icons.settings_rounded
                      : Icons.check_circle_outline_rounded,
                  onPressed: isPermanent ? onOpenSettings : onRequestPermission,
                ),
              ),
              const SizedBox(height: AppSizes.md),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: 'Go Back',
                  isOutlined: true,
                  foregroundColor: AppColors.white,
                  onPressed: onBack,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Scan Intent
// ═══════════════════════════════════════════════════════════════

enum ScanIntent { addProduct, newSale }

class _ScanIntentSheet extends StatelessWidget {
  final ScanIntent? initialIntent;

  const _ScanIntentSheet({this.initialIntent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.xxl),
      decoration: BoxDecoration(
        color: context.appSurfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Text('What is this scan for?', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Choose one option before scanning.',
            style: AppTypography.bodyMedium
                .copyWith(color: context.appTextSecondary),
          ),
          const SizedBox(height: AppSizes.xl),
          _IntentOptionTile(
            icon: Icons.add_box_rounded,
            title: 'Add New Product',
            subtitle: 'Open product form with scanned barcode pre-filled.',
            isActive: initialIntent == ScanIntent.addProduct,
            onTap: () => Navigator.pop(context, ScanIntent.addProduct),
          ),
          const SizedBox(height: AppSizes.md),
          _IntentOptionTile(
            icon: Icons.point_of_sale_rounded,
            title: 'Create New Sale',
            subtitle: 'Lookup product and continue to sale flow.',
            isActive: initialIntent == ScanIntent.newSale,
            onTap: () => Navigator.pop(context, ScanIntent.newSale),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

class _IntentOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;

  const _IntentOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? AppColors.primary : context.appDivider,
              width: isActive ? 1.8 : 1,
            ),
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.08)
                : context.appSurfaceRaised,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary.withValues(alpha: 0.16)
                      : context.appInputFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isActive ? AppColors.primary : context.appTextPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: context.appTextSecondary),
                    ),
                  ],
                ),
              ),
              if (isActive)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Scan Overlay
// ═══════════════════════════════════════════════════════════════

class _ScanOverlay extends StatelessWidget {
  final bool isProcessing;

  const _ScanOverlay({required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanOverlayPainter(isProcessing: isProcessing),
      child: const SizedBox.expand(),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final bool isProcessing;

  _ScanOverlayPainter({required this.isProcessing});

  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.85;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2 - 40;
    final scanRect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    // Dim overlay
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), overlayPaint);
    canvas.drawRect(Rect.fromLTWH(0, top, left, scanAreaSize), overlayPaint);
    canvas.drawRect(Rect.fromLTWH(left + scanAreaSize, top, left, scanAreaSize),
        overlayPaint);
    canvas.drawRect(
        Rect.fromLTWH(0, top + scanAreaSize, size.width,
            size.height - top - scanAreaSize),
        overlayPaint);

    // Scan frame corners
    const cornerLength = 30.0;
    final paint = Paint()
      ..color = isProcessing ? AppColors.primaryLight : AppColors.scannerBlue
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(scanRect.topLeft,
        scanRect.topLeft + const Offset(cornerLength, 0), paint);
    canvas.drawLine(scanRect.topLeft,
        scanRect.topLeft + const Offset(0, cornerLength), paint);

    // Top-right
    canvas.drawLine(scanRect.topRight,
        scanRect.topRight + const Offset(-cornerLength, 0), paint);
    canvas.drawLine(scanRect.topRight,
        scanRect.topRight + const Offset(0, cornerLength), paint);

    // Bottom-left
    canvas.drawLine(scanRect.bottomLeft,
        scanRect.bottomLeft + const Offset(cornerLength, 0), paint);
    canvas.drawLine(scanRect.bottomLeft,
        scanRect.bottomLeft + const Offset(0, -cornerLength), paint);

    // Bottom-right
    canvas.drawLine(scanRect.bottomRight,
        scanRect.bottomRight + const Offset(-cornerLength, 0), paint);
    canvas.drawLine(scanRect.bottomRight,
        scanRect.bottomRight + const Offset(0, -cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) =>
      oldDelegate.isProcessing != isProcessing;
}

// ═══════════════════════════════════════════════════════════════
// Quick Sell Sheet
// ═══════════════════════════════════════════════════════════════

class _QuickSellSheet extends StatefulWidget {
  final Product product;
  final Future<void> Function(int quantity) onConfirm;

  const _QuickSellSheet({
    required this.product,
    required this.onConfirm,
  });

  @override
  State<_QuickSellSheet> createState() => _QuickSellSheetState();
}

class _QuickSellSheetState extends State<_QuickSellSheet> {
  final _quantityController = TextEditingController(text: '1');
  bool _isProcessing = false;

  int get _quantity => int.tryParse(_quantityController.text.trim()) ?? 0;

  bool get _canSell => _quantity <= widget.product.quantity && _quantity > 0;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.product.sellingPrice * _quantity;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSizes.xxl,
        AppSizes.xxl,
        AppSizes.xxl,
        bottomInset + MediaQuery.of(context).padding.bottom + AppSizes.lg,
      ),
      decoration: BoxDecoration(
        color: context.appSurfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSizes.xl),

            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.coral.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.point_of_sale_rounded,
                      color: AppColors.coral, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Sale', style: AppTypography.h4.copyWith(color: context.appTextPrimary)),
                      Text('Enter quantity to complete sale',
                          style: AppTypography.bodySmall
                              .copyWith(color: context.appTextSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.lg),

            // Product details required for operator confirmation
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.appInputFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Product Name',
                      style: AppTypography.bodySmall
                          .copyWith(color: context.appTextSecondary)),
                  const SizedBox(height: 2),
                  Text(widget.product.name, style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary)),
                  const SizedBox(height: 8),
                  Text('Product ID',
                      style: AppTypography.bodySmall
                          .copyWith(color: context.appTextSecondary)),
                  const SizedBox(height: 2),
                  Text(widget.product.id, style: AppTypography.bodyMedium.copyWith(color: context.appTextPrimary)),
                  const SizedBox(height: 8),
                  Text('Selling Price',
                      style: AppTypography.bodySmall
                          .copyWith(color: context.appTextSecondary)),
                  const SizedBox(height: 2),
                  Text(Formatters.currency(widget.product.sellingPrice),
                      style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary)),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.lg),

            // Stock info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: context.appInputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Available Stock',
                      style: AppTypography.bodyMedium
                          .copyWith(color: context.appTextSecondary)),
                  Text('${widget.product.quantity} ${widget.product.unit}',
                      style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary)),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.lg),

            // Quantity input
            Text('Quantity', style: AppTypography.labelLarge.copyWith(color: context.appTextPrimary)),
            const SizedBox(height: AppSizes.sm),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: context.appTextPrimary, fontSize: 14),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Enter quantity',
                hintStyle: TextStyle(color: context.appTextTertiary, fontSize: 14),
                helperText: 'Unit: ${widget.product.unit}',
                helperStyle: TextStyle(color: context.appTextSecondary, fontSize: 11),
                filled: true,
                fillColor: context.appInputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),

            // Insufficient stock warning
            if (_quantity <= 0 && _quantityController.text.trim().isNotEmpty) ...[
              const SizedBox(height: AppSizes.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_rounded,
                      color: AppColors.error, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Enter a valid quantity',
                    style:
                        AppTypography.bodySmall.copyWith(color: AppColors.error),
                  ),
                ],
              ),
            ] else if (!_canSell && _quantity > 0) ...[
              const SizedBox(height: AppSizes.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_rounded,
                      color: AppColors.error, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Exceeds available stock',
                    style:
                        AppTypography.bodySmall.copyWith(color: AppColors.error),
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSizes.xxl),

            // Price summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.isDark
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Unit Price',
                          style: AppTypography.bodyMedium
                              .copyWith(color: context.appTextPrimary)),
                      Text(Formatters.currency(widget.product.sellingPrice),
                          style: AppTypography.labelMedium
                              .copyWith(color: context.appTextPrimary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Quantity',
                          style: AppTypography.bodyMedium
                              .copyWith(color: context.appTextPrimary)),
                      Text('×$_quantity',
                          style: AppTypography.labelMedium
                              .copyWith(color: context.appTextPrimary)),
                    ],
                  ),
                  Divider(height: 20, color: context.appDivider),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total',
                          style: AppTypography.h4.copyWith(
                              color: context.isDark
                                  ? AppColors.primaryLight
                                  : AppColors.primaryDark)),
                      Text(Formatters.currency(total),
                          style: AppTypography.h3.copyWith(
                              color: context.isDark
                                  ? AppColors.primaryLight
                                  : AppColors.primaryDark)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.xl),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: _isProcessing
                    ? 'Processing...'
                    : 'Confirm Sale — ${Formatters.currency(total)}',
                icon: Icons.check_circle_outline_rounded,
                isLoading: _isProcessing,
                onPressed: _canSell && !_isProcessing
                    ? () async {
                        setState(() => _isProcessing = true);
                        await widget.onConfirm(_quantity);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Bottom Action Button
// ═══════════════════════════════════════════════════════════════

class _BottomActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _BottomActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isActive ? AppColors.primaryLight : AppColors.white,
                size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? AppColors.primaryLight : AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
