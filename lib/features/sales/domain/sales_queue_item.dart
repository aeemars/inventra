import 'package:equatable/equatable.dart';
import '../../inventory/domain/entities/product.dart';

class SalesQueueItem extends Equatable {
  final Product product;
  final int quantity;

  const SalesQueueItem({required this.product, required this.quantity});

  double get lineTotal => product.sellingPrice * quantity;

  SalesQueueItem copyWith({int? quantity}) => SalesQueueItem(
        product: product,
        quantity: quantity ?? this.quantity,
      );

  @override
  List<Object?> get props => [product.id, quantity];
}
