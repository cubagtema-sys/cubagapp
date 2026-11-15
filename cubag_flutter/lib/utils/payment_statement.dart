import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One paid item on a year statement.
class StatementLine {
  final DateTime date;
  final String description;
  final String reference;
  final double amount;
  const StatementLine(this.date, this.description, this.reference, this.amount);
}

/// Paid payments in [year], oldest first. Anything not marked paid is left out.
List<StatementLine> statementLines(List<dynamic> payments, int year) {
  final lines = <StatementLine>[];
  for (final raw in payments) {
    if (raw is! Map) continue;
    if ((raw['status']?.toString().toLowerCase() ?? '') != 'paid') continue;
    final d = DateTime.tryParse(raw['created_at']?.toString() ?? '')?.toLocal();
    if (d == null || d.year != year) continue;
    lines.add(StatementLine(
      d,
      (raw['description']?.toString().trim().isNotEmpty ?? false) ? raw['description'].toString().trim() : 'CUBAG payment',
      raw['payment_ref']?.toString() ?? '',
      double.tryParse(raw['amount']?.toString() ?? '') ?? 0,
    ));
  }
  lines.sort((a, b) => a.date.compareTo(b.date));
  return lines;
}

/// Years that have at least one paid payment, newest first.
List<int> statementYears(List<dynamic> payments) {
  final years = <int>{};
  for (final raw in payments) {
    if (raw is! Map || (raw['status']?.toString().toLowerCase() ?? '') != 'paid') continue;
    final d = DateTime.tryParse(raw['created_at']?.toString() ?? '');
    if (d != null) years.add(d.toLocal().year);
  }
  return years.toList()..sort((a, b) => b.compareTo(a));
}

String _money(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return 'GH₵ $whole.${parts[1]}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// A one-page (or longer) PDF statement of what a member paid in [year].
Future<Uint8List> buildYearStatement({
  required int year,
  required List<StatementLine> lines,
  required String name,
  required String company,
  required String licenceNumber,
  DateTime? issued,
}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-400.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-700.ttf'));
  final cocoa = PdfColor.fromHex('#5C3421');
  final muted = PdfColor.fromHex('#6E625B');
  final line = PdfColor.fromHex('#E9E2DB');
  final total = lines.fold<double>(0, (s, l) => s + l.amount);
  final now = issued ?? DateTime.now();

  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Customs Brokers Association of Ghana', style: pw.TextStyle(color: cocoa, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Statement of payments, $year', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 14),
        ],
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Issued from the CUBAG app on ${_day(now)}. Each receipt can be checked with its reference.',
              style: pw.TextStyle(fontSize: 8, color: muted)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8, color: muted)),
        ],
      ),
      build: (_) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(name.isEmpty ? 'Member' : name, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    if (company.isNotEmpty) pw.Text(company, style: pw.TextStyle(color: muted)),
                    if (licenceNumber.isNotEmpty) pw.Text('Licence $licenceNumber', style: pw.TextStyle(color: muted)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Total paid in $year', style: pw.TextStyle(color: muted)),
                  pw.Text(_money(total), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: cocoa)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        if (lines.isEmpty)
          pw.Text('No paid payments in $year.', style: pw.TextStyle(color: muted))
        else
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'What for', 'Reference', 'Amount'],
            data: [
              for (final l in lines) [_day(l.date), l.description, l.reference, _money(l.amount)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#F7F4F1')),
            border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5), bottom: pw.BorderSide(color: line)),
            cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft, 3: pw.Alignment.centerRight},
            columnWidths: {0: const pw.FixedColumnWidth(80), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(2), 3: const pw.FixedColumnWidth(90)},
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          ),
        if (lines.isNotEmpty)
          pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.only(top: 8, right: 6),
            child: pw.Text('Total  ${_money(total)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
      ],
    ),
  );
  return doc.save();
}
