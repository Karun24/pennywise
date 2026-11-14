import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction_entry.dart';
import '../services/analytics_service.dart';
import '../utils/date_utils.dart';
import '../utils/money.dart';

/// Generates a clean, professional PDF financial statement completely offline.
class PdfStatementService {
  const PdfStatementService();

  Future<File> generateMonthlyStatement({
    required DateTime month,
    required List<TransactionEntry> transactions,
    required List<Category> categories,
    required List<Account> accounts,
    required CurrencyInfo currency,
  }) async {
    final doc = pw.Document();
    final range = DateRange.month(month);
    final summary = AnalyticsService.summarize(transactions, range);
    final monthTxs = transactions
        .where((t) => range.contains(t.date))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final catMap = {for (final c in categories) c.id!: c};
    final acctMap = {for (final a in accounts) a.id!: a};

    final catTotals = AnalyticsService.categoryTotals(transactions, range);

    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    final primaryColor = PdfColor.fromHex('#4F46E5');
    final incomeColor = PdfColor.fromHex('#059669');
    final expenseColor = PdfColor.fromHex('#DC2626');
    final lightBg = PdfColor.fromHex('#F8FAFC');
    final borderColor = PdfColor.fromHex('#E2E8F0');
    final textMuted = PdfColor.fromHex('#64748B');

    String fmt(int minor) => Money.format(minor, currency);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('PENNYWISE',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 22,
                          color: primaryColor,
                          letterSpacing: 1.5,
                        )),
                    pw.SizedBox(height: 2),
                    pw.Text('Monthly Financial Statement',
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: textMuted,
                        )),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(DateUtilsX.monthYear(month),
                        style: pw.TextStyle(font: fontBold, fontSize: 16)),
                    pw.SizedBox(height: 2),
                    pw.Text('Generated on ${DateUtilsX.dayMonthYear(DateTime.now())}',
                        style: pw.TextStyle(fontSize: 9, color: textMuted)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(color: borderColor, thickness: 1),
            pw.SizedBox(height: 16),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('100% Private & Offline · Generated on-device by PennyWise',
                  style: pw.TextStyle(fontSize: 8, color: textMuted)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: textMuted)),
            ],
          ),
        ),
        build: (context) => [
          // 1. Executive Summary Cards
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: lightBg,
                    border: pw.Border.all(color: borderColor),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('TOTAL INCOME',
                          style: pw.TextStyle(fontSize: 8, color: textMuted, font: fontBold)),
                      pw.SizedBox(height: 4),
                      pw.Text(fmt(summary.incomeMinor),
                          style: pw.TextStyle(
                              fontSize: 14, font: fontBold, color: incomeColor)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: lightBg,
                    border: pw.Border.all(color: borderColor),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('TOTAL EXPENSES',
                          style: pw.TextStyle(fontSize: 8, color: textMuted, font: fontBold)),
                      pw.SizedBox(height: 4),
                      pw.Text(fmt(summary.expenseMinor),
                          style: pw.TextStyle(
                              fontSize: 14, font: fontBold, color: expenseColor)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: lightBg,
                    border: pw.Border.all(color: borderColor),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('NET SAVINGS',
                          style: pw.TextStyle(fontSize: 8, color: textMuted, font: fontBold)),
                      pw.SizedBox(height: 4),
                      pw.Text(fmt(summary.netMinor),
                          style: pw.TextStyle(
                              fontSize: 14,
                              font: fontBold,
                              color: summary.netMinor >= 0
                                  ? incomeColor
                                  : expenseColor)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: lightBg,
                    border: pw.Border.all(color: borderColor),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('SAVINGS RATE',
                          style: pw.TextStyle(fontSize: 8, color: textMuted, font: fontBold)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        summary.incomeMinor > 0
                            ? '${((summary.netMinor / summary.incomeMinor) * 100).clamp(0, 100).round()}%'
                            : 'N/A',
                        style: pw.TextStyle(
                            fontSize: 14, font: fontBold, color: primaryColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // 2. Spending by Category Table
          if (catTotals.isNotEmpty) ...[
            pw.Text('Spending by Category',
                style: pw.TextStyle(font: fontBold, fontSize: 12)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: borderColor, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: lightBg),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Category',
                          style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Amount Spent',
                          style: pw.TextStyle(font: fontBold, fontSize: 9),
                          textAlign: pw.TextAlign.right),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Share (%)',
                          style: pw.TextStyle(font: fontBold, fontSize: 9),
                          textAlign: pw.TextAlign.right),
                    ),
                  ],
                ),
                for (final ct in catTotals.take(8))
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          catMap[ct.categoryId]?.name ?? 'Uncategorised',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(fmt(ct.totalMinor),
                            style: const pw.TextStyle(fontSize: 9),
                            textAlign: pw.TextAlign.right),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                            '${(ct.share * 100).toStringAsFixed(1)}%',
                            style: const pw.TextStyle(fontSize: 9),
                            textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 20),
          ],

          // 3. Itemized Transactions Ledger
          pw.Text('Itemized Transactions (${monthTxs.length})',
              style: pw.TextStyle(font: fontBold, fontSize: 12)),
          pw.SizedBox(height: 8),
          if (monthTxs.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 16),
              child: pw.Text('No transactions recorded for this month.',
                  style: pw.TextStyle(color: textMuted, fontSize: 10)),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: borderColor, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: lightBg),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Date',
                          style: pw.TextStyle(font: fontBold, fontSize: 8)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Description',
                          style: pw.TextStyle(font: fontBold, fontSize: 8)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Category / Type',
                          style: pw.TextStyle(font: fontBold, fontSize: 8)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Account',
                          style: pw.TextStyle(font: fontBold, fontSize: 8)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Amount',
                          style: pw.TextStyle(font: fontBold, fontSize: 8),
                          textAlign: pw.TextAlign.right),
                    ),
                  ],
                ),
                for (var i = 0; i < monthTxs.length; i++)
                  _buildTxRow(
                    tx: monthTxs[i],
                    catMap: catMap,
                    acctMap: acctMap,
                    fmt: fmt,
                    isEven: i % 2 == 0,
                    incomeColor: incomeColor,
                    expenseColor: expenseColor,
                    primaryColor: primaryColor,
                  ),
              ],
            ),
        ],
      ),
    );

    final outputDir = await getTemporaryDirectory();
    final fileName =
        'pennywise_statement_${month.year}_${month.month.toString().padLeft(2, '0')}.pdf';
    final file = File(p.join(outputDir.path, fileName));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  pw.TableRow _buildTxRow({
    required TransactionEntry tx,
    required Map<int, Category> catMap,
    required Map<int, Account> acctMap,
    required String Function(int) fmt,
    required bool isEven,
    required PdfColor incomeColor,
    required PdfColor expenseColor,
    required PdfColor primaryColor,
  }) {
    final catName = tx.isTransfer
        ? 'Transfer'
        : (catMap[tx.categoryId]?.name ?? 'Uncategorised');
    final acctName = tx.isTransfer
        ? '${acctMap[tx.accountId]?.name ?? 'Account'} -> ${acctMap[tx.toAccountId]?.name ?? 'Account'}'
        : (acctMap[tx.accountId]?.name ?? '-');

    final amountText = tx.isTransfer
        ? fmt(tx.amountMinor)
        : (tx.isIncome ? '+${fmt(tx.amountMinor)}' : '-${fmt(tx.amountMinor)}');

    final color = tx.isTransfer
        ? primaryColor
        : (tx.isIncome ? incomeColor : expenseColor);

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: isEven ? PdfColors.white : PdfColor.fromHex('#FAFAFA'),
      ),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(DateUtilsX.dayMonth(tx.date),
              style: const pw.TextStyle(fontSize: 8)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            tx.note.isNotEmpty ? tx.note : catName,
            style: const pw.TextStyle(fontSize: 8),
            maxLines: 1,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(catName, style: const pw.TextStyle(fontSize: 8)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(acctName, style: const pw.TextStyle(fontSize: 8)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            amountText,
            style: pw.TextStyle(fontSize: 8, color: color),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }
}
