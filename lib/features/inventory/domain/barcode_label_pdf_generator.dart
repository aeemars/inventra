import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/entities/product.dart';

/// A single item in the label print queue.
class LabelItem {
  final Product product;
  final int copies;
  const LabelItem({required this.product, required this.copies});
}

/// Pure Dart PDF-building logic for barcode labels.
/// Generates a print-ready grid matching standard 3-across label sheets.
class BarcodeLabelPdfGenerator {
  BarcodeLabelPdfGenerator._();

  /// Builds a print-ready PDF: a grid of labels, 3 columns per row,
  /// each showing the barcode, its code, and the product name.
  static Future<pw.Document> build(List<LabelItem> items) async {
    final doc = pw.Document();
    final barcodeGen = Barcode.code128();

    // Expand each product into N individual label entries based on copies.
    final labels = <Product>[
      for (final item in items)
        for (var i = 0; i < item.copies; i++) item.product,
    ];

    const perPage = 20; // 2 columns × 10 rows
    const columns = 2;

    for (var start = 0; start < labels.length; start += perPage) {
      final pageLabels = labels.skip(start).take(perPage).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return pw.GridView(
              crossAxisCount: columns,
              childAspectRatio: 1.6,
              children: pageLabels.map((product) {
                final code = product.barcode ?? product.sku;
                return pw.Container(
                  margin: const pw.EdgeInsets.all(4),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                        color: PdfColors.grey400, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        product.name,
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 4),
                      pw.BarcodeWidget(
                        barcode: barcodeGen,
                        data: code,
                        width: 170,
                        height: 55,
                        drawText: false,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        code,
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
    }

    return doc;
  }
}
