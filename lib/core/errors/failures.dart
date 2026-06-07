import 'package:equatable/equatable.dart';

/// Base failure class for domain-level error handling
abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure({required this.message, this.code});

  @override
  List<Object?> get props => [message, code];
}

class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code});

  factory AuthFailure.fromCode(String code) {
    switch (code) {
      case 'user-not-found':
        return const AuthFailure(
            message: 'No user found with this email.', code: 'user-not-found');
      case 'wrong-password':
        return const AuthFailure(
            message: 'Incorrect password.', code: 'wrong-password');
      case 'email-already-in-use':
        return const AuthFailure(
            message: 'An account already exists with this email.',
            code: 'email-already-in-use');
      case 'weak-password':
        return const AuthFailure(
            message: 'Password is too weak.', code: 'weak-password');
      case 'invalid-email':
        return const AuthFailure(
            message: 'Invalid email address.', code: 'invalid-email');
      case 'too-many-requests':
        return const AuthFailure(
            message: 'Too many attempts. Please try again later.',
            code: 'too-many-requests');
      case 'invalid-credential':
        return const AuthFailure(
            message: 'Invalid email or password.', code: 'invalid-credential');
      case 'captcha-check-failed':
        return const AuthFailure(
            message: 'Security verification failed. Please try again.',
            code: 'captcha-check-failed');
      case 'app-not-authorized':
        return const AuthFailure(
          message:
              'This app is not authorized for Firebase Authentication in this project.',
          code: 'app-not-authorized',
        );
      case 'operation-not-allowed':
        return const AuthFailure(
          message:
              'Email/password sign-up is currently disabled. Please contact support.',
          code: 'operation-not-allowed',
        );
      default:
        return AuthFailure(message: 'Authentication error: $code', code: code);
    }
  }
}

class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code});
}

class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.code});
}

class NetworkFailure extends Failure {
  const NetworkFailure(
      {super.message = 'No internet connection. Please check your network.',
      super.code});
}

class ValidationFailure extends Failure {
  const ValidationFailure({required super.message, super.code});
}

class StockFailure extends Failure {
  const StockFailure({required super.message, super.code});

  factory StockFailure.outOfStock(String productName) {
    return StockFailure(
      message: '$productName is out of stock.',
      code: 'out-of-stock',
    );
  }

  factory StockFailure.insufficientStock(String productName, int available) {
    return StockFailure(
      message: 'Only $available units of $productName available.',
      code: 'insufficient-stock',
    );
  }
}

class PermissionFailure extends Failure {
  const PermissionFailure({
    super.message = 'You do not have permission to perform this action.',
    super.code,
  });
}

// ── Firestore / Database ──

class FirestoreFailure extends Failure {
  const FirestoreFailure({required super.message, super.code});

  factory FirestoreFailure.fromCode(String code, {String? rawMessage}) {
    switch (code) {
      case 'permission-denied':
        return const FirestoreFailure(
          message: "You don't have permission to perform this action.",
          code: 'permission-denied',
        );
      case 'not-found':
        return const FirestoreFailure(
          message: 'The requested record could not be found.',
          code: 'not-found',
        );
      case 'already-exists':
        return const FirestoreFailure(
          message: 'This record already exists in the database.',
          code: 'already-exists',
        );
      case 'resource-exhausted':
        return const FirestoreFailure(
          message: 'Too many requests. Please wait a moment and try again.',
          code: 'resource-exhausted',
        );
      case 'unauthenticated':
        return const FirestoreFailure(
          message: 'Your session has expired. Please sign in again.',
          code: 'unauthenticated',
        );
      case 'unavailable':
        return const FirestoreFailure(
          message: 'Service is temporarily unavailable. Check your connection and try again.',
          code: 'unavailable',
        );
      case 'deadline-exceeded':
        return const FirestoreFailure(
          message: 'The request timed out. Check your connection and try again.',
          code: 'deadline-exceeded',
        );
      case 'aborted':
        return const FirestoreFailure(
          message: 'The operation was interrupted by a conflict. Please try again.',
          code: 'aborted',
        );
      case 'cancelled':
        return const FirestoreFailure(
          message: 'The operation was cancelled. Please try again.',
          code: 'cancelled',
        );
      case 'data-loss':
        return const FirestoreFailure(
          message: 'A data integrity error occurred. Please contact support.',
          code: 'data-loss',
        );
      case 'internal':
        return const FirestoreFailure(
          message: 'An internal database error occurred. Please try again.',
          code: 'internal',
        );
      case 'invalid-argument':
        return const FirestoreFailure(
          message: 'Invalid data was submitted. Please check your input.',
          code: 'invalid-argument',
        );
      case 'failed-precondition':
        return const FirestoreFailure(
          message: 'The operation could not complete — a required condition was not met.',
          code: 'failed-precondition',
        );
      case 'out-of-range':
        return const FirestoreFailure(
          message: 'A submitted value is outside the allowed range.',
          code: 'out-of-range',
        );
      default:
        return FirestoreFailure(
          message: rawMessage ?? 'A database error occurred. Please try again.',
          code: code,
        );
    }
  }
}

// ── Inventory / Product ──

class InventoryFailure extends Failure {
  const InventoryFailure({required super.message, super.code});

  factory InventoryFailure.productNotFound() => const InventoryFailure(
        message: 'Product not found. It may have been deleted.',
        code: 'product-not-found',
      );

  factory InventoryFailure.insufficientStock(int available) => InventoryFailure(
        message: 'Insufficient stock — only $available unit${available == 1 ? '' : 's'} available.',
        code: 'insufficient-stock',
      );

  factory InventoryFailure.noShop() => const InventoryFailure(
        message: 'No shop is linked to your account. Please contact support.',
        code: 'no-shop',
      );

  factory InventoryFailure.addFailed() => const InventoryFailure(
        message: 'Failed to add product. Please try again.',
        code: 'add-failed',
      );

  factory InventoryFailure.updateFailed() => const InventoryFailure(
        message: 'Failed to update product. Please try again.',
        code: 'update-failed',
      );

  factory InventoryFailure.deleteFailed() => const InventoryFailure(
        message: 'Failed to delete product. Please try again.',
        code: 'delete-failed',
      );

  factory InventoryFailure.stockUpdateFailed() => const InventoryFailure(
        message: 'Failed to update stock level. Please try again.',
        code: 'stock-update-failed',
      );
}

// ── Scanner / Transactions ──

class ScannerFailure extends Failure {
  const ScannerFailure({required super.message, super.code});

  factory ScannerFailure.noShop() => const ScannerFailure(
        message: 'No shop is configured for this account. Please contact support.',
        code: 'no-shop',
      );

  factory ScannerFailure.productNotFound() => const ScannerFailure(
        message: 'Product not found. Try a different barcode or add it manually.',
        code: 'product-not-found',
      );

  factory ScannerFailure.saleFailed() => const ScannerFailure(
        message: 'Sale could not be completed. Please try again.',
        code: 'sale-failed',
      );

  factory ScannerFailure.restockFailed() => const ScannerFailure(
        message: 'Restock could not be completed. Please try again.',
        code: 'restock-failed',
      );

  factory ScannerFailure.adjustmentFailed() => const ScannerFailure(
        message: 'Stock adjustment failed. Please try again.',
        code: 'adjustment-failed',
      );

  factory ScannerFailure.insufficientStock(int available, int requested) =>
      ScannerFailure(
        message:
            'Not enough stock — $available unit${available == 1 ? '' : 's'} available, $requested requested.',
        code: 'insufficient-stock',
      );
}

// ── In-Demand ──

class InDemandFailure extends Failure {
  const InDemandFailure({required super.message, super.code});

  factory InDemandFailure.addFailed() => const InDemandFailure(
        message: 'Could not add item to the in-demand list. Please try again.',
        code: 'add-failed',
      );

  factory InDemandFailure.incrementFailed() => const InDemandFailure(
        message: 'Could not update the request count. Please try again.',
        code: 'increment-failed',
      );
}
