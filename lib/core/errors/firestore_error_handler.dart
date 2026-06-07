import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/scanner/data/scanner_repository.dart';
import 'failures.dart';

/// Maps any caught exception to a [Failure] subclass.
/// [context] is a short label like 'add product' or 'perform sale' used
/// in the fallback message when no specific code is matched.
Failure handleFirestoreException(Object e, {required String context}) {
  if (e is Failure) return e; // already typed — pass through

  if (e is FirebaseException) {
    return FirestoreFailure.fromCode(
      e.code,
      rawMessage: e.message,
    );
  }

  if (e is InsufficientStockException) {
    // InsufficientStockException is defined in scanner_repository.dart —
    // import it there rather than here. This branch is reached only if
    // the repo re-throws it after wrapping; leave it unhandled here so
    // the caller's specific catch clause runs first.
    return FirestoreFailure(
      message: e.toString(),
      code: 'insufficient-stock',
    );
  }

  // Generic / unexpected
  final raw = e.toString();
  // Strip internal Dart/Firebase noise that leaks raw class names
  final isVerbose = raw.contains('Exception:') ||
      raw.contains('FirebaseException') ||
      raw.contains('PlatformException');

  return FirestoreFailure(
    message: isVerbose
        ? 'An unexpected error occurred while trying to $context. Please try again.'
        : raw,
    code: 'unknown',
  );
}
