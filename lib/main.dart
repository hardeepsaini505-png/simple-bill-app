
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const BillApp());

class BillApp extends StatelessWidget {
  const BillApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Simple Bill',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
        ),
        home: const BillHome(),
      );
}

class BillItem {
  String name;
  double qty, rate;

  BillItem({
    required this.name,
    required this.qty,
    required this.rate,
  });

  double get amount => qty * rate;

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        'rate': rate,
      };

  factory BillItem.fromJson(Map<String, dynamic> j) => BillItem(
        name: j['name'] ?? '',
        qty: (j['qty'] as num).toDouble(),
        rate: (j['rate'] as num).toDouble(),
      );
}

class Bill {
  String no, client, date, type;
  int format;
  List<BillItem> items;

  Bill({
    required this.no,
    required this.client,
    required this.date,
    String? type,
    required this.format,
    required this.items,
  }) : type = type ?? 'invoice';

  double get total => items.fold(0, (s, i) => s + i.amount);

  Map<String, dynamic> toJson() => {
        'no': no,
        'client': client,
        'date': date,
        'type': type,
        'format': format,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        no: j['no'] ?? '',
        client: j['client'] ?? '',
        date: j['date'] ?? '',
        type: (j['type'] ?? 'invoice').toString(),
        format: j['format'] ?? 1,
        items: ((j['items'] as List?) ?? const [])
            .map((e) => BillItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class BillHome extends StatefulWidget {
  const BillHome({super.key});

  @override
  State<BillHome> createState() => _BillHomeState();
}

class _BillHomeState extends State<BillHome> {
  String firm = 'My Firm';
  String invoicePrefix = 'INV-';
  String quotationPrefix = 'QTN-';
  String selectedType = 'invoice';
  int nextNo = 1, selectedFormat = 1;
  List<Bill> bills = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    firm = p.getString('firm') ?? 'My Firm';
    invoicePrefix = p.getString('invoicePrefix') ?? p.getString('prefix') ?? 'INV-';
    quotationPrefix = p.getString('quotationPrefix') ?? 'QTN-';
    nextNo = p.getInt('next') ?? 1;
    selectedFormat = p.getInt('format') ?? 1;
    selectedType = p.getString('type') ?? 'invoice';
    final s = p.getString('bills');
    if (s != null) {
      bills = (jsonDecode(s) as List)
          .map((e) => Bill.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    setState(() {});
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('firm', firm);
    await p.setString('invoicePrefix', invoicePrefix);
    await p.setString('quotationPrefix', quotationPrefix);
    await p.setInt('next', nextNo);
    await p.setInt('format', selectedFormat);
    await p.setString('type', selectedType);
    await p.setString(
      'bills',
      jsonEncode(bills.map((e) => e.toJson()).toList()),
    );
  }

  String billNo(String type) {
    final p = type == 'quotation' ? quotationPrefix : invoicePrefix;
    return '$p${nextNo.toString().padLeft(4, '0')}';
  }

  String dateNow() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> settings() async {
    final f = TextEditingController(text: firm);
    final ip = TextEditingController(text: invoicePrefix);
    final qp = TextEditingController(text: quotationPrefix);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Firm & Bill Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: f,
              decoration: const InputDecoration(labelText: 'Firm Name'),
            ),
            TextField(
              controller: ip,
              decoration: const InputDecoration(labelText: 'Invoice No Prefix'),
            ),
            TextField(
              controller: qp,
              decoration: const InputDecoration(labelText: 'Quotation No Prefix'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              firm = f.text.trim().isEmpty ? 'My Firm' : f.text.trim();
              invoicePrefix = ip.text.trim().isEmpty ? 'INV-' : ip.text.trim();
              quotationPrefix = qp.text.trim().isEmpty ? 'QTN-' : qp.text.trim();
              save();
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> newBill() async {
    final client = TextEditingController();
    final items = <BillItem>[];

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditBill(
          firm: firm,
          no: billNo(selectedType),
          type: selectedType,
          client: client,
          date: dateNow(),
          items: items,
          format: selectedFormat,
          onSave: (b) async {
            bills.insert(0, b);
            nextNo++;
            selectedFormat = b.format;
            selectedType = b.type;
            await save();
            setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> editBill(int index) async {
    final old = bills[index];
    final client = TextEditingController(text: old.client);
    final items = old.items
        .map((x) => BillItem(name: x.name, qty: x.qty, rate: x.rate))
        .toList();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditBill(
          firm: firm,
          no: old.no,
          type: old.type,
          client: client,
          date: old.date,
          items: items,
          format: old.format,
          onSave: (updated) async {
            bills[index] = updated;
            selectedFormat = updated.format;
            selectedType = updated.type;
            await save();
            setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> deleteBill(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Bill?'),
        content: Text('Bill ${bills[index].no} delete karna hai?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      bills.removeAt(index);
      await save();
      setState(() {});
    }
  }

  String backupJson() => jsonEncode({
        'firm': firm,
        'invoicePrefix': invoicePrefix,
        'quotationPrefix': quotationPrefix,
        'nextNo': nextNo,
        'format': selectedFormat,
        'type': selectedType,
        'bills': bills.map((e) => e.toJson()).toList(),
      });

  Future<void> backup() async {
    final data = backupJson();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/bill_backup_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(data);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Bill App Backup',
    );
  }

  Future<void> downloadBackup() async {
    final data = backupJson();
    final bytes = utf8.encode(data);
    final name =
        'bill_backup_${DateTime.now().millisecondsSinceEpoch}.json';

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Download Backup',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path == null ? 'Backup download cancel ho gaya' : 'Backup save ho gaya',
        ),
      ),
    );
  }

  Future<void> restore() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (r == null) return;

    final bytes =
        r.files.single.bytes ?? await File(r.files.single.path!).readAsBytes();
    final j = jsonDecode(utf8.decode(bytes));

    firm = j['firm'] ?? 'My Firm';
    invoicePrefix = j['invoicePrefix'] ?? j['prefix'] ?? 'INV-';
    quotationPrefix = j['quotationPrefix'] ?? 'QTN-';
    nextNo = j['nextNo'] ?? 1;
    selectedFormat = j['format'] ?? 1;
    selectedType = j['type'] ?? 'invoice';
    bills = (j['bills'] as List)
        .map((e) => Bill.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    await save();
    setState(() {});
  }

  Future<void> makePdf(Bill b, {required bool share}) async {
    final doc = pw.Document();
    final formatNo = ((b.format - 1) % 50) + 1;
    final isQuotation = b.type == 'quotation';
    final title = isQuotation ? 'QUOTATION' : 'INVOICE';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => _buildProfessionalPdf(
          b,
          formatNo: formatNo,
          title: title,
        ),
      ),
    );

    final bytes = await doc.save();

    if (share) {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${b.no}.pdf');
      await f.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(f.path)],
        text: '${title} ${b.no}',
      );
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }

  pw.Widget _buildProfessionalPdf(
    Bill b, {
    required int formatNo,
    required String title,
  }) {
    final accent = PdfColors.blueGrey;
    final light = PdfColors.grey200;
    final dark = PdfColors.grey800;

    pw.Widget totalLine() => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12),
            child: pw.Text(
              'Grand Total: ₹${b.total.toStringAsFixed(2)}',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );

    pw.Widget itemsTable({
      bool compact = false,
      bool showIndex = false,
      bool shadedHeader = true,
    }) {
      final headers = <String>[
        if (showIndex) '#',
        'Item',
        'Qty',
        'Rate',
        'Amount',
      ];
      final data = b.items.asMap().entries.map((e) {
        final x = e.value;
        return <String>[
          if (showIndex) '${e.key + 1}',
          x.name,
          x.qty.toString(),
          x.rate.toStringAsFixed(2),
          x.amount.toStringAsFixed(2),
        ];
      }).toList();

      return pw.Table.fromTextArray(
        headers: headers,
        data: data,
        border: pw.TableBorder.all(
          color: PdfColors.grey500,
          width: compact ? .45 : .7,
        ),
        headerDecoration:
            shadedHeader ? pw.BoxDecoration(color: light) : null,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellPadding: pw.EdgeInsets.all(compact ? 5 : 7),
        cellStyle: pw.TextStyle(fontSize: compact ? 9 : 10),
      );
    }

    pw.Widget titleBlock({
      bool centered = false,
      bool boxed = false,
      bool underline = false,
      double size = 22,
    }) {
      final child = pw.Column(
        crossAxisAlignment: centered
            ? pw.CrossAxisAlignment.center
            : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            firm,
            style: pw.TextStyle(
              fontSize: size,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (underline)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 6),
              height: 2,
              width: centered ? 120 : 180,
              color: accent,
            ),
        ],
      );

      if (!boxed) return child;
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: accent, width: 1),
        ),
        child: child,
      );
    }

    pw.Widget infoRow({bool box = false, bool reverse = false}) {
      final row = pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Bill No: ${b.no}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Client: ${b.client}'),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Date: ${b.date}'),
              pw.SizedBox(height: 4),
              pw.Text(b.type == 'quotation' ? 'Quotation' : 'Invoice'),
            ],
          ),
        ],
      );

      if (!box) return row;
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey400),
        ),
        child: row,
      );
    }

    pw.Widget signature() => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(children: [
              pw.SizedBox(height: 30),
              pw.Container(width: 120, height: .7, color: dark),
              pw.SizedBox(height: 4),
              pw.Text('Customer Signature'),
            ]),
            pw.Column(children: [
              pw.SizedBox(height: 30),
              pw.Container(width: 120, height: .7, color: dark),
              pw.SizedBox(height: 4),
              pw.Text('Authorized Signature'),
            ]),
          ],
        );

    // Each number below is a different professional composition.
    switch (formatNo) {
      case 1:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          titleBlock(boxed: true),
          pw.SizedBox(height: 16), infoRow(), pw.SizedBox(height: 16),
          itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 2:
        return pw.Column(children: [
          titleBlock(centered: true, underline: true, size: 25),
          pw.SizedBox(height: 14), infoRow(box: true), pw.SizedBox(height: 14),
          itemsTable(showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 3:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            titleBlock(size: 21),
            pw.Container(padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: accent)),
              child: pw.Column(children: [pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 4), pw.Text(b.no)])),
          ]),
          pw.SizedBox(height: 18), infoRow(), pw.Divider(), itemsTable(), totalLine(),
        ]);
      case 4:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Container(width: 70, height: 70, decoration: pw.BoxDecoration(border: pw.Border.all(color: accent)), child: pw.Center(child: pw.Text('LOGO'))),
            pw.SizedBox(width: 12), titleBlock(size: 20),
          ]),
          pw.SizedBox(height: 16), infoRow(box: true), pw.SizedBox(height: 12),
          itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 5:
        return pw.Column(children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: light),
            child: titleBlock(centered: true, size: 24)),
          pw.SizedBox(height: 14), infoRow(), pw.SizedBox(height: 12),
          itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 6:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4), pw.Text(firm, style: const pw.TextStyle(fontSize: 14)),
          pw.Divider(thickness: 2), pw.SizedBox(height: 10), infoRow(),
          pw.SizedBox(height: 15), itemsTable(showIndex: true, compact: true), totalLine(),
          pw.Spacer(), signature(),
        ]);
      case 7:
        return pw.Column(children: [
          titleBlock(centered: true, size: 23), pw.SizedBox(height: 8),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
            pw.Text('No: ${b.no}'), pw.SizedBox(width: 30), pw.Text('Date: ${b.date}')
          ]),
          pw.SizedBox(height: 15), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 8:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.only(bottom: 10),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 2))),
            child: titleBlock(size: 22)),
          pw.SizedBox(height: 14), infoRow(), pw.SizedBox(height: 14),
          itemsTable(shadedHeader: false), totalLine(), pw.Spacer(), signature(),
        ]);
      case 9:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(firm, style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold)), pw.Text('Professional Billing Statement')]),
            pw.Text(title, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 18), infoRow(box: true), pw.SizedBox(height: 12),
          itemsTable(compact: true, showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 10:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: titleBlock(centered: true, size: 24)), pw.SizedBox(height: 12),
          pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(border: pw.Border.all(color: dark)),
            child: infoRow()),
          pw.SizedBox(height: 14), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 11:
        return pw.Column(children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            titleBlock(size: 20),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Text('DOCUMENT', style: pw.TextStyle(fontSize: 9)), pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))]),
          ]),
          pw.SizedBox(height: 12), pw.Divider(), infoRow(), pw.SizedBox(height: 14),
          itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 12:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: accent), borderRadius: pw.BorderRadius.circular(6)),
            child: titleBlock(centered: true, boxed: false, size: 22)),
          pw.SizedBox(height: 15), infoRow(), pw.SizedBox(height: 15), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 13:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [pw.Container(width: 5, height: 55, color: accent), pw.SizedBox(width: 10), titleBlock(size: 22)]),
          pw.SizedBox(height: 18), infoRow(), pw.SizedBox(height: 14), itemsTable(showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 14:
        return pw.Column(children: [
          pw.Text(firm, style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3), pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 15), pw.Row(children: [
            pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(color: light), child: pw.Text('CLIENT\n${b.client}'))),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(color: light), child: pw.Text('DOCUMENT\n${b.no}\n${b.date}'))),
          ]),
          pw.SizedBox(height: 14), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 15:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          titleBlock(underline: true, size: 23), pw.SizedBox(height: 15),
          pw.Text('BILL TO', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text(b.client, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12), pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text('No: ${b.no}   '), pw.Text('Date: ${b.date}')]),
          pw.SizedBox(height: 12), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 16:
        return pw.Column(children: [
          titleBlock(centered: true, size: 22), pw.SizedBox(height: 14),
          pw.Row(children: [
            pw.Expanded(child: pw.Text('CLIENT\n${b.client}')),
            pw.Expanded(child: pw.Text('DATE\n${b.date}')),
            pw.Expanded(child: pw.Text('NUMBER\n${b.no}')),
          ]),
          pw.SizedBox(height: 14), pw.Divider(), itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 17:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(firm, style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2), pw.Text(title, style: pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 18), infoRow(box: true), pw.SizedBox(height: 16),
          itemsTable(shadedHeader: false, showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 18:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.Text(firm, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 14), pw.Divider(), infoRow(), pw.SizedBox(height: 14),
          itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 19:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: dark)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(firm, style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold)),
              pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ])),
          pw.SizedBox(height: 12), infoRow(), pw.SizedBox(height: 12), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 20:
        return pw.Column(children: [
          titleBlock(centered: true, underline: true, size: 23), pw.SizedBox(height: 18),
          pw.Text('Prepared for ${b.client}', style: pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 12), itemsTable(showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 21:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(firm, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            pw.Text('Ref: ${b.no}'),
          ]),
          pw.Divider(), pw.Text('Client: ${b.client}   Date: ${b.date}'), pw.SizedBox(height: 14),
          itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 22:
        return pw.Column(children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.symmetric(vertical: 12),
            child: titleBlock(centered: true, size: 24)),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
            pw.Text('No. ${b.no}'), pw.Text(b.date), pw.Text(b.client),
          ]),
          pw.SizedBox(height: 15), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 23:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: titleBlock(size: 21)),
            pw.Container(padding: const pw.EdgeInsets.all(9), decoration: pw.BoxDecoration(color: light),
              child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          ]),
          pw.SizedBox(height: 14), infoRow(box: true), pw.SizedBox(height: 14),
          itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 24:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 27, fontWeight: pw.FontWeight.bold)),
          pw.Text(firm, style: const pw.TextStyle(fontSize: 13)), pw.SizedBox(height: 12),
          pw.Container(height: 3, width: double.infinity, color: accent), pw.SizedBox(height: 15),
          infoRow(), pw.SizedBox(height: 15), itemsTable(showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 25:
        return pw.Column(children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: accent)),
            child: pw.Column(children: [
              pw.Text(firm, style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4), pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ])),
          pw.SizedBox(height: 14), pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Client: ${b.client}'), pw.Text('No: ${b.no}'), pw.Text('Date: ${b.date}')
          ]),
          pw.SizedBox(height: 14), itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 26:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          titleBlock(size: 22), pw.SizedBox(height: 10), pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12), pw.Container(height: .8, width: double.infinity, color: dark),
          pw.SizedBox(height: 12), infoRow(), pw.SizedBox(height: 16), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 27:
        return pw.Column(children: [
          pw.Row(children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(firm, style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold)),
              pw.Text('Business Document'),
            ])),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold)),
              pw.Text(b.no),
            ]),
          ]),
          pw.SizedBox(height: 16), infoRow(), pw.SizedBox(height: 12), itemsTable(showIndex: true, compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 28:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: pw.Text(firm, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
          pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 16), pw.Row(children: [
            pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)), child: pw.Text('CLIENT\n${b.client}'))),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)), child: pw.Text('BILL DATE\n${b.date}'))),
          ]),
          pw.SizedBox(height: 12), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 29:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(firm, style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3), pw.Text('Official ${title.toLowerCase()} document'),
          pw.SizedBox(height: 14), infoRow(box: true), pw.SizedBox(height: 14),
          itemsTable(shadedHeader: false), totalLine(), pw.Spacer(), signature(),
        ]);
      case 30:
        return pw.Column(children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold)),
            pw.Text(firm, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 8), pw.Text('Document No. ${b.no}   |   ${b.date}'),
          pw.SizedBox(height: 14), itemsTable(compact: true, showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 31:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1))),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(firm, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.Text(title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            ])),
          pw.SizedBox(height: 13), pw.Text('Customer: ${b.client}'), pw.Text('Document: ${b.no}    Date: ${b.date}'),
          pw.SizedBox(height: 13), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 32:
        return pw.Column(children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: light),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(firm, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text(title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            ])),
          pw.SizedBox(height: 12), infoRow(), pw.SizedBox(height: 12), itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 33:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Expanded(child: titleBlock(size: 20)),
            pw.Container(width: 80, height: 45, decoration: pw.BoxDecoration(border: pw.Border.all(color: accent)),
              child: pw.Center(child: pw.Text('REF\n${b.no}', textAlign: pw.TextAlign.center))),
          ]),
          pw.SizedBox(height: 15), pw.Text('Client: ${b.client}'), pw.Text('Date: ${b.date}'),
          pw.SizedBox(height: 14), itemsTable(showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 34:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 27, fontWeight: pw.FontWeight.bold))),
          pw.Center(child: pw.Text(firm, style: pw.TextStyle(fontSize: 15))),
          pw.SizedBox(height: 15), infoRow(box: true), pw.SizedBox(height: 14), itemsTable(compact: true),
          totalLine(), pw.Spacer(), signature(),
        ]);
      case 35:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(firm, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.Text(title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 15), pw.Row(children: [
            pw.Expanded(child: pw.Text('Bill To\n${b.client}')),
            pw.Expanded(child: pw.Text('Bill No\n${b.no}')),
            pw.Expanded(child: pw.Text('Date\n${b.date}')),
          ]),
          pw.SizedBox(height: 16), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 36:
        return pw.Column(children: [
          titleBlock(centered: true, boxed: true, size: 22), pw.SizedBox(height: 14),
          pw.Text('${b.client} • ${b.no} • ${b.date}'), pw.SizedBox(height: 14),
          itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 37:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            titleBlock(size: 20), pw.Text(b.no, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 8), pw.Text('Issued: ${b.date}'), pw.Text('Prepared for: ${b.client}'),
          pw.SizedBox(height: 14), itemsTable(shadedHeader: false, compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 38:
        return pw.Column(children: [
          pw.Text(firm, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3), pw.Text(title, style: pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 12), pw.Container(height: 1, width: double.infinity, color: accent),
          pw.SizedBox(height: 12), infoRow(), pw.SizedBox(height: 12), itemsTable(showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 39:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: dark), borderRadius: pw.BorderRadius.circular(2)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(firm, style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold)),
              pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ])),
          pw.SizedBox(height: 14), infoRow(), pw.SizedBox(height: 14), itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 40:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('DOCUMENT', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text(title, style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
          pw.Text(firm, style: const pw.TextStyle(fontSize: 14)), pw.SizedBox(height: 14),
          infoRow(box: true), pw.SizedBox(height: 14), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 41:
        return pw.Column(children: [
          pw.Row(children: [
            pw.Expanded(child: titleBlock(size: 21)),
            pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(color: light), child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          ]),
          pw.SizedBox(height: 13), pw.Divider(), pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Client: ${b.client}'), pw.Text('${b.no} / ${b.date}')
          ]),
          pw.SizedBox(height: 13), itemsTable(compact: true, showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 42:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: pw.Text(firm, style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold))),
          pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 14))),
          pw.SizedBox(height: 16), pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Client: ${b.client}'), pw.Text('Date: ${b.date}'), pw.Text('No: ${b.no}')
          ]),
          pw.SizedBox(height: 12), pw.Divider(), itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 43:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(firm, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.Text('Tax / Commercial Document'),
            ]),
            pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 16), infoRow(box: true), pw.SizedBox(height: 14), itemsTable(compact: true),
          totalLine(), pw.Spacer(), signature(),
        ]);
      case 44:
        return pw.Column(children: [
          pw.Text(firm, style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3), pw.Text(title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 14), pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: accent)),
            child: pw.Text('CLIENT: ${b.client}    NO: ${b.no}    DATE: ${b.date}')),
          pw.SizedBox(height: 13), itemsTable(showIndex: true, compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 45:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          titleBlock(underline: true, size: 24), pw.SizedBox(height: 13),
          pw.Text('To: ${b.client}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Reference: ${b.no} | Date: ${b.date}'), pw.SizedBox(height: 14),
          itemsTable(), totalLine(), pw.Spacer(), signature(),
        ]);
      case 46:
        return pw.Column(children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(firm, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
              pw.Text(b.no), pw.Text(b.date),
            ]),
          ]),
          pw.SizedBox(height: 15), pw.Text('Customer: ${b.client}'), pw.SizedBox(height: 12),
          itemsTable(shadedHeader: false, compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 47:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: light),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold)),
              pw.Text(firm, style: const pw.TextStyle(fontSize: 13)),
            ])),
          pw.SizedBox(height: 14), infoRow(), pw.SizedBox(height: 14), itemsTable(showIndex: true),
          totalLine(), pw.Spacer(), signature(),
        ]);
      case 48:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold))),
          pw.Center(child: pw.Text(firm, style: pw.TextStyle(fontSize: 14))),
          pw.SizedBox(height: 14), pw.Divider(), infoRow(), pw.SizedBox(height: 14),
          itemsTable(compact: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 49:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            titleBlock(size: 22),
            pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(border: pw.Border.all(color: accent)),
              child: pw.Text('${b.no}\n${b.date}', textAlign: pw.TextAlign.center)),
          ]),
          pw.SizedBox(height: 14), pw.Text('Customer / Client: ${b.client}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12), itemsTable(compact: true, showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
      case 50:
      default:
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: dark, width: 1.2)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(firm, style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4), pw.Text(title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(b.no, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(b.date),
              ]),
            ])),
          pw.SizedBox(height: 15), pw.Text('Bill To: ${b.client}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12), itemsTable(showIndex: true), totalLine(), pw.Spacer(), signature(),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Simple Bill'),
          actions: [
            IconButton(
              onPressed: settings,
              icon: const Icon(Icons.settings),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'backup') backup();
                if (v == 'download') downloadBackup();
                if (v == 'restore') restore();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'backup',
                  child: Text('Backup / Share'),
                ),
                PopupMenuItem(
                  value: 'download',
                  child: Text('Download Backup'),
                ),
                PopupMenuItem(
                  value: 'restore',
                  child: Text('Restore Backup'),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: newBill,
          icon: const Icon(Icons.add),
          label: const Text('New Bill'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'invoice',
                    icon: Icon(Icons.receipt_long),
                    label: Text('Invoice'),
                  ),
                  ButtonSegment(
                    value: 'quotation',
                    icon: Icon(Icons.request_quote),
                    label: Text('Quotation'),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (v) async {
                  setState(() => selectedType = v.first);
                  await save();
                },
              ),
            ),
            Expanded(
              child: bills.isEmpty
                  ? const Center(child: Text('Abhi koi bill nahi hai'))
                  : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: bills.length,
                itemBuilder: (_, i) {
                  final b = bills[i];

                  return Card(
                    child: ListTile(
                      title: Text(
                        '${b.no}  •  ${b.client}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${b.date}   |   Total: ₹${b.total.toStringAsFixed(2)}',
                      ),
                      onTap: () => editBill(i),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Edit / Update',
                            icon: const Icon(Icons.edit),
                            onPressed: () => editBill(i),
                          ),
                          IconButton(
                            tooltip: 'PDF',
                            icon: const Icon(Icons.picture_as_pdf),
                            onPressed: () => makePdf(b, share: false),
                          ),
                          IconButton(
                            tooltip: 'WhatsApp / Share',
                            icon: const Icon(Icons.share),
                            onPressed: () => makePdf(b, share: true),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => deleteBill(i),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class EditBill extends StatefulWidget {
  final String firm, no, type;
  final TextEditingController client;
  final String date;
  final List<BillItem> items;
  final int format;
  final Future<void> Function(Bill) onSave;

  const EditBill({
    super.key,
    required this.firm,
    required this.no,
    required this.type,
    required this.client,
    required this.date,
    required this.items,
    required this.format,
    required this.onSave,
  });

  @override
  State<EditBill> createState() => _EditBillState();
}

class _EditBillState extends State<EditBill> {
  late String date;
  late String type;
  late int format;
  late List<BillItem> items;

  @override
  void initState() {
    super.initState();
    date = widget.date;
    type = widget.type;
    format = widget.format;
    items = List.from(widget.items);
  }

  double get total => items.fold(0, (s, i) => s + i.amount);

  Future<void> addItem([BillItem? old]) async {
    final n = TextEditingController(text: old?.name ?? '');
    final q = TextEditingController(
      text: old == null ? '1' : old.qty.toString(),
    );
    final r = TextEditingController(
      text: old?.rate.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(old == null ? 'Add Item' : 'Edit Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: n,
              decoration: const InputDecoration(labelText: 'Item Name'),
            ),
            TextField(
              controller: q,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Qty'),
            ),
            TextField(
              controller: r,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Rate'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final x = BillItem(
                name: n.text.trim(),
                qty: double.tryParse(q.text) ?? 0,
                rate: double.tryParse(r.text) ?? 0,
              );

              if (old == null) {
                setState(() => items.add(x));
              } else {
                final index = items.indexOf(old);
                if (index >= 0) {
                  setState(() => items[index] = x);
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> chooseDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (d != null) {
      setState(() => date = d.toIso8601String().substring(0, 10));
    }
  }

  void showFormatPreview() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${type == 'quotation' ? 'Quotation' : 'Invoice'} • Format $format Preview'),
        content: SizedBox(
          width: 360,
          child: BillPreview(
            firm: widget.firm,
            no: widget.no,
            client: widget.client.text.isEmpty
                ? 'Client Name'
                : widget.client.text,
            date: date,
            type: type,
            format: format,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.no),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: widget.client,
              decoration: const InputDecoration(
                labelText: 'Client Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'invoice',
                  icon: Icon(Icons.receipt_long),
                  label: Text('Invoice'),
                ),
                ButtonSegment(
                  value: 'quotation',
                  icon: Icon(Icons.request_quote),
                  label: Text('Quotation'),
                ),
              ],
              selected: {type},
              onSelectionChanged: (v) {
                setState(() => type = v.first);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Date: $date')),
                TextButton(
                  onPressed: chooseDate,
                  child: const Text('Change'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: format,
                    decoration: const InputDecoration(
                      labelText: 'Bill Format',
                    ),
                    items: List.generate(
                      50,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('Format ${i + 1}'),
                      ),
                    ),
                    onChanged: (v) {
                      setState(() => format = v ?? 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: showFormatPreview,
                  child: const Text('Preview'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Add items'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final x = items[i];

                        return Card(
                          child: ListTile(
                            title: Text(x.name),
                            subtitle: Text(
                              'Qty ${x.qty} × ₹${x.rate.toStringAsFixed(2)} = ₹${x.amount.toStringAsFixed(2)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => addItem(x),
                                  icon: const Icon(Icons.edit),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() => items.removeAt(i));
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: () => addItem(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                ),
                Text(
                  'Grand Total: ₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  if (widget.client.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Client name likho'),
                      ),
                    );
                    return;
                  }

                  if (items.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kam se kam 1 item add karo'),
                      ),
                    );
                    return;
                  }

                  await widget.onSave(
                    Bill(
                      no: widget.no,
                      client: widget.client.text.trim(),
                      date: date,
                      type: type,
                      format: format,
                      items: items,
                    ),
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Save / Update Bill'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BillPreview extends StatelessWidget {
  final String firm, no, client, date, type;
  final int format;

  const BillPreview({
    super.key,
    required this.firm,
    required this.no,
    required this.client,
    required this.date,
    required this.type,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final centered = format % 2 == 1;
    final double headerSize = format % 4 == 0 ? 20 : 24;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          width: format % 5 == 0 ? 3 : 1,
        ),
        borderRadius: BorderRadius.circular(
          format % 6 == 0 ? 14 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(
            firm,
            style: TextStyle(
              fontSize: headerSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            type == 'quotation' ? 'QUOTATION' : 'INVOICE',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('No: $no'),
              Text(date),
            ],
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Client: $client'),
          ),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(),
            children: const [
              TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.all(5),
                    child: Text(
                      'Item',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(5),
                    child: Text(
                      'Qty',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(5),
                    child: Text(
                      'Rate',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.all(5),
                    child: Text('Sample Item'),
                  ),
                  Padding(
                    padding: EdgeInsets.all(5),
                    child: Text('2'),
                  ),
                  Padding(
                    padding: EdgeInsets.all(5),
                    child: Text('100'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Grand Total: ₹200.00',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
