
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: const BillHome(),
  );
}

class BillItem {
  String name;
  double qty, rate;
  BillItem({required this.name, required this.qty, required this.rate});
  double get amount => qty * rate;
  Map<String,dynamic> toJson()=>{'name':name,'qty':qty,'rate':rate};
  factory BillItem.fromJson(Map<String,dynamic> j)=>BillItem(
    name: j['name'] ?? '', qty: (j['qty'] as num).toDouble(), rate: (j['rate'] as num).toDouble());
}

class Bill {
  String no, client, date;
  int format;
  List<BillItem> items;
  Bill({required this.no,required this.client,required this.date,required this.format,required this.items});
  double get total=>items.fold(0,(s,i)=>s+i.amount);
  Map<String,dynamic> toJson()=>{'no':no,'client':client,'date':date,'format':format,'items':items.map((e)=>e.toJson()).toList()};
  factory Bill.fromJson(Map<String,dynamic> j)=>Bill(
    no:j['no']??'',client:j['client']??'',date:j['date']??'',format:j['format']??1,
    items:(j['items'] as List).map((e)=>BillItem.fromJson(Map<String,dynamic>.from(e))).toList());
}

class BillHome extends StatefulWidget {
  const BillHome({super.key});
  @override State<BillHome> createState()=>_BillHomeState();
}

class _BillHomeState extends State<BillHome> {
  String firm='My Firm', prefix='INV-';
  int nextNo=1, selectedFormat=1;
  List<Bill> bills=[];
  final client=TextEditingController();

  @override void initState(){super.initState(); load();}
  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    firm=p.getString('firm')??'My Firm'; prefix=p.getString('prefix')??'INV-';
    nextNo=p.getInt('next')??1; selectedFormat=p.getInt('format')??1;
    final s=p.getString('bills');
    if(s!=null) bills=(jsonDecode(s) as List).map((e)=>Bill.fromJson(Map<String,dynamic>.from(e))).toList();
    setState((){});
  }
  Future<void> save() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('firm',firm); await p.setString('prefix',prefix);
    await p.setInt('next',nextNo); await p.setInt('format',selectedFormat);
    await p.setString('bills',jsonEncode(bills.map((e)=>e.toJson()).toList()));
  }
  String billNo()=> '$prefix${nextNo.toString().padLeft(4,'0')}';

  Future<void> settings() async {
    final f=TextEditingController(text:firm), pr=TextEditingController(text:prefix);
    await showDialog(context:context,builder:(_)=>AlertDialog(
      title:const Text('Firm & Bill Settings'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:f,decoration:const InputDecoration(labelText:'Firm Name')),
        TextField(controller:pr,decoration:const InputDecoration(labelText:'Bill No Prefix')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
        FilledButton(onPressed:(){firm=f.text.trim().isEmpty?'My Firm':f.text.trim();prefix=pr.text;save();setState((){});Navigator.pop(context);},child:const Text('Save'))],
    ));
  }

  Future<void> newBill() async {
    client.clear(); final items=<BillItem>[];
    int fmt=selectedFormat;
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>EditBill(
      firm:firm,no:billNo(),client:client,date:dateNow(),items:items,format:fmt,
      onSave:(b)async{bills.insert(0,b);nextNo++;selectedFormat=b.format;await save();setState((){});},
    )));
  }
  String dateNow()=>DateTime.now().toIso8601String().substring(0,10);

  Future<void> backup() async {
    final data=jsonEncode({'firm':firm,'prefix':prefix,'nextNo':nextNo,'format':selectedFormat,'bills':bills.map((e)=>e.toJson()).toList()});
    final dir=await getApplicationDocumentsDirectory();
    final file=File('${dir.path}/bill_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(data);
    await Share.shareXFiles([XFile(file.path)],text:'Bill App Backup');
  }
  Future<void> restore() async {
    final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json'],withData:true);
    if(r==null) return;
    final bytes=r.files.single.bytes ?? await File(r.files.single.path!).readAsBytes();
    final j=jsonDecode(utf8.decode(bytes));
    firm=j['firm']??'My Firm';prefix=j['prefix']??'INV-';nextNo=j['nextNo']??1;selectedFormat=j['format']??1;
    bills=(j['bills'] as List).map((e)=>Bill.fromJson(Map<String,dynamic>.from(e))).toList();
    await save();setState((){});
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Simple Bill'),actions:[
      IconButton(onPressed:settings,icon:const Icon(Icons.settings)),
      PopupMenuButton<String>(onSelected:(v){if(v=='backup')backup();if(v=='restore')restore();},itemBuilder:(_)=>[
        const PopupMenuItem(value:'backup',child:Text('Backup / Share')),
        const PopupMenuItem(value:'restore',child:Text('Restore Backup')),
      ])
    ]),
    floatingActionButton:FloatingActionButton.extended(onPressed:newBill,icon:const Icon(Icons.add),label:const Text('New Bill')),
    body:bills.isEmpty?const Center(child:Text('Abhi koi bill nahi hai')):ListView.builder(
      padding:const EdgeInsets.all(12),itemCount:bills.length,itemBuilder:(_,i){
        final b=bills[i]; return Card(child:ListTile(
          title:Text('${b.no}  •  ${b.client}',style:const TextStyle(fontWeight:FontWeight.bold)),
          subtitle:Text('${b.date}   |   Total: ₹${b.total.toStringAsFixed(2)}'),
          trailing:Wrap(children:[
            IconButton(icon:const Icon(Icons.picture_as_pdf),onPressed:()=>makePdf(b,share:false)),
            IconButton(icon:const Icon(Icons.share),onPressed:()=>makePdf(b,share:true)),
            IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{bills.removeAt(i);await save();setState((){});}),
          ]),
        ));
      }),
  );

  Future<void> makePdf(Bill b,{required bool share}) async {
    final doc=pw.Document();
    doc.addPage(pw.Page(pageFormat:PdfPageFormat.a4,build:(_){
      final title=b.format==1?'INVOICE':b.format==2?'BILL':'SALES BILL';
      return pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
        pw.Center(child:pw.Text(firm,style:pw.TextStyle(fontSize:24,fontWeight:pw.FontWeight.bold))),
        pw.SizedBox(height:8),
        pw.Center(child:pw.Text(title,style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold))),
        pw.SizedBox(height:15),
        pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('Bill No: ${b.no}'),pw.Text('Date: ${b.date}')]),
        pw.SizedBox(height:8),pw.Text('Client: ${b.client}',style:pw.TextStyle(fontSize:14)),
        pw.SizedBox(height:15),
        pw.Table.fromTextArray(headers:['Item','Qty','Rate','Amount'],data:b.items.map((x)=>[x.name,x.qty.toString(),x.rate.toStringAsFixed(2),x.amount.toStringAsFixed(2)]).toList()),
        pw.SizedBox(height:15),
        pw.Align(alignment:pw.Alignment.centerRight,child:pw.Text('Grand Total: ₹${b.total.toStringAsFixed(2)}',style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold))),
      ]);
    }));
    final bytes=await doc.save();
    if(share){
      final dir=await getTemporaryDirectory();final f=File('${dir.path}/${b.no}.pdf');await f.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(f.path)],text:'Bill ${b.no}');
    } else { await Printing.layoutPdf(onLayout:(_)=>bytes); }
  }
}

class EditBill extends StatefulWidget {
  final String firm,no; final TextEditingController client; final String date;
  final List<BillItem> items; final int format; final Future<void> Function(Bill) onSave;
  const EditBill({super.key,required this.firm,required this.no,required this.client,required this.date,required this.items,required this.format,required this.onSave});
  @override State<EditBill> createState()=>_EditBillState();
}
class _EditBillState extends State<EditBill>{
  late String date; late int format; late List<BillItem> items;
  @override void initState(){super.initState();date=widget.date;format=widget.format;items=List.from(widget.items);}
  double get total=>items.fold(0,(s,i)=>s+i.amount);

  Future<void> addItem([BillItem? old]) async {
    final n=TextEditingController(text:old?.name??''),q=TextEditingController(text:old==null?'1':old.qty.toString()),r=TextEditingController(text:old?.rate.toString()??'');
    await showDialog(context:context,builder:(_)=>AlertDialog(title:Text(old==null?'Add Item':'Edit Item'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:n,decoration:const InputDecoration(labelText:'Item Name')),
      TextField(controller:q,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Qty')),
      TextField(controller:r,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Rate')),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:(){
      final x=BillItem(name:n.text,qty:double.tryParse(q.text)??0,rate:double.tryParse(r.text)??0);
      setState(()=>old==null?items.add(x):items[items.indexOf(old)]=x);Navigator.pop(context);
    },child:const Text('Save'))]));
  }
  Future<void> chooseDate() async {
    final d=await showDatePicker(context:context,initialDate:DateTime.tryParse(date)??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime(2100));
    if(d!=null)setState(()=>date=d.toIso8601String().substring(0,10));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.no)),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Date: $date')),
                TextButton(onPressed: chooseDate, child: const Text('Change')),
              ],
            ),
            DropdownButtonFormField<int>(
              value: format,
              decoration: const InputDecoration(labelText: 'Bill Format'),
              items: List.generate(
                50,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('Format ${i + 1}'),
                ),
              ),
              onChanged: (v) => setState(() => format = v ?? 1),
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
                                  onPressed: () => setState(() => items.removeAt(i)),
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                      const SnackBar(content: Text('Client name likho')),
                    );
                    return;
                  }
                  if (items.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kam se kam 1 item add karo')),
                    );
                    return;
                  }
                  await widget.onSave(
                    Bill(
                      no: widget.no,
                      client: widget.client.text.trim(),
                      date: date,
                      format: format,
                      items: items,
                    ),
                  );
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Bill'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
