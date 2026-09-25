import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Note: Adjust the import path to match where your db_helper.dart is located.
import '../db_helper.dart';

class OrderPage extends StatefulWidget {
  const OrderPage({Key? key}) : super(key: key);

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  List<Map<String, dynamic>> _currentOrders = [];
  final GlobalKey _printKey = GlobalKey(); // Used to capture the screenshot

  final List<String> _itemsList = [
    "10 এর বার", "12 এর বার", "16 এর বার", "25 এর বার", "40 এর বার",
    "18/5 পাতি", "18/5.5 পাতি", "25/5 পাতি", "19/3 পাতি", "25/3 পাতি",
    "30/5 পাতি", "35/5 পাতি", "32/5 পাতি", "40/6 পাতি", "50/5 পাতি",
    "40/12 পাতি", "25/12 পাতি", "Z অ্যাঙ্গেল", "19/3 অ্যাঙ্গেল", "25/3 অ্যাঙ্গেল",
    "25/5 অ্যাঙ্গেল", "30/5 অ্যাঙ্গেল", "35/5 অ্যাঙ্গেল", "40/6 অ্যাঙ্গেল",
    "50/5 অ্যাঙ্গেল", "3/8 শিট 18 গেজ", "3/8 শিট 16 গেজ", "4/8 শিট 18 গেজ",
    "4/8 শিট 16 গেজ", "1 মিটার শিট", "3 মিটার শিট", "3/6 ফুট শিট",
    "2 সুতো রড", "5/8 সুতো রড", "1.5 ইঞ্চি গোল পাইপ", "1.5/1.5 ইঞ্চি চৌকো পাইপ",
    "1 ইঞ্চি চৌকো পাইপ", "1/2 ইঞ্চি চৌকো পাইপ", "1/1.5 ইঞ্চি চৌকো পাইপ",
    "ঝালাই কাটি", "বক্স কব্জা", "পেন্সিল কব্জা", "সোল্ডার কব্জা", "T ফোল্ড কব্জা",
    "3 ফোল্ড কব্জা", "1 ইঞ্চি হাফ বল", "1.5 ইঞ্চি হাফ বল", "স্প্রিং",
    "4 ইঞ্চি স্প্রিং", "5 ইঞ্চি স্প্রিং", "12 ফুট চ্যানেল", "13 ফুট চ্যানেল",
    "14 ফুট চ্যানেল", "15 ফুট চ্যানেল", "4 ইঞ্চি কাটটিং উইল", "5 ইঞ্চি কাটটিং উইল",
    "14 ইঞ্চি কাটটিং উইল", "রিপিট", "সকেট", "শাটার লক", "12 ফুট প্রোফাইল",
    "13 ফুট প্রোফাইল", "14 ফুট প্রোফাইল", "15 ফুট প্রোফাইল", "ওয়াসার",
    "বড়ো ফুল", "ছোট ফুল", "সূর্যমুখী ফুল", "বেগুন পাতা", "পাতা", "ফুল"
  ];

  final List<String> _unitsList = [
    "Kg", "Ton", "টা", "টো", "টে", "কৌটো", "প্যাকেট", "বাক্স"
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final pending = await DBHelper.getPendingOrders();
    setState(() {
      _currentOrders = pending;
    });
  }

  Future<void> _deleteOrder(int id) async {
    await DBHelper.deleteOrder(id);
    _loadData();
  }

  Future<void> _clearHistory() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear History"),
        content: const Text("Are you sure you want to permanently delete all previous orders?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ??
    false;

    if (confirm) {
      await DBHelper.clearOrderHistory();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order history cleared!')));
    }
  }

  void _showAddItemModal() {
    String selectedItem = _itemsList.first;
    String enteredQty = "1"; // Default qty
    String selectedUnit = _unitsList.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16, right: 16, top: 24, // Increased top padding
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Add New Item",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.deepPurple), // Much bigger title
                    textAlign: TextAlign.center
                  ),
                  const SizedBox(height: 24),

                  // ==============================
                  // HUGE ITEM DROPDOWN
                  // ==============================
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Select Item',
                      labelStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.deepPurple), // Bigger Label
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20), // Taller input
                    ),
                    value: selectedItem,
                    isExpanded: true,
                    menuMaxHeight: 400,
                    style: const TextStyle(fontSize: 24, color: Colors.black, fontWeight: FontWeight.bold), // Huge selected text
                    items: _itemsList.map((String val) => DropdownMenuItem(
                      value: val,
                      child: Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)) // Huge menu text
                    )).toList(),
                    onChanged: (val) => setModalState(() => selectedItem = val!),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      // ==============================
                      // HUGE QTY FIELD
                      // ==============================
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          initialValue: enteredQty,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 24, color: Colors.black, fontWeight: FontWeight.bold), // Huge input text
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            labelStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.deepPurple), // Bigger Label
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20), // Taller input
                          ),
                          onChanged: (val) {
                            enteredQty = val;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // ==============================
                      // HUGE UNIT DROPDOWN
                      // ==============================
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Unit',
                            labelStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.deepPurple), // Bigger Label
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20), // Taller input
                          ),
                          value: selectedUnit,
                          style: const TextStyle(fontSize: 22, color: Colors.black, fontWeight: FontWeight.bold), // Huge selected text
                          items: _unitsList.map((String val) => DropdownMenuItem(
                            value: val,
                            child: Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)) // Huge menu text
                          )).toList(),
                          onChanged: (val) => setModalState(() => selectedUnit = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18), // Taller button
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), // Bigger Text
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18), // Taller button
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          onPressed: () async {
                            if(enteredQty.isEmpty) enteredQty = "1";
                            DateTime now = DateTime.now();
                            String timeString = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour}:${now.minute}";

                            await DBHelper.insertOrder({
                              "item": selectedItem,
                              "qty": enteredQty,
                              "unit": selectedUnit,
                              "status": "pending",
                              "date": timeString
                            });
                            _loadData();
                            if(mounted) Navigator.pop(context);
                          },
                          child: const Text("Add", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), // Bigger Text
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 1. Send as WhatsApp Text
  Future<void> _sendTextToWhatsApp() async {
    Navigator.pop(context); // Close the options bottom sheet
    String message = "Asha Grill House\n~Biggyan Das|9932134803\n--------------------------\n";
    message += _currentOrders.map((o) => "${o['item']} ---- ${o['qty']} ${o['unit']}").join("\n");

    await DBHelper.sendOrders();
    _loadData();

    final Uri url = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(message)}");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  }

  // 2. Capture Screenshot and Share
  Future<void> _shareScreenshot() async {
    Navigator.pop(context); // Close the options bottom sheet
    try {
      await Future.delayed(const Duration(milliseconds: 200));

      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      File imgFile = File('${directory.path}/order_list.png');
      await imgFile.writeAsBytes(pngBytes);

      await DBHelper.sendOrders();
      _loadData();

      await Share.shareXFiles([XFile(imgFile.path)], text: 'Order from Asha Grill House');
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error taking screenshot: $e')));
    }
  }

  // Opens a bottom sheet giving the user the 2 send options
  void _showSendOptions() {
    if (_currentOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items to send!')));
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("How do you want to send this?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.chat, color: Colors.green, size: 32),
                title: const Text("Send as Text (WhatsApp)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                onTap: _sendTextToWhatsApp,
              ),
              const Divider(thickness: 1.0),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.blue, size: 32),
                title: const Text("Share as Image (Screenshot)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                onTap: _shareScreenshot,
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Current Orders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'history') {
                  // Ensure this pushes to the OrderHistoryPage
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const OrderHistoryPage()));
                } else if (value == 'clear') {
                  _clearHistory();
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<String>(
                    value: 'history',
                    child: Row(children: [Icon(Icons.history, color: Colors.deepPurple, size: 24), SizedBox(width: 8), Text("Show History", style: TextStyle(fontSize: 18))]),
                  ),
                  const PopupMenuItem<String>(
                    value: 'clear',
                    child: Row(children: [Icon(Icons.delete_forever, color: Colors.red, size: 24), SizedBox(width: 8), Text("Delete Previous", style: TextStyle(fontSize: 18))]),
                  ),
                ];
              },
            ),
          ],
      ),
      body: Column(
        children: [
          // ==============================
          // BIGGER "ADD" BUTTON AT TOP
          // ==============================
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60), // Taller Button
                backgroundColor: Colors.deepPurple.shade50,
                foregroundColor: Colors.deepPurple,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.deepPurple.shade200, width: 2.0)),
              ),
              onPressed: _showAddItemModal,
              icon: const Icon(Icons.add_circle, size: 28), // Bigger icon
              label: const Text("Add New Order Item", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), // Bigger Text
            ),
          ),

          Expanded(
            child: _currentOrders.isEmpty
            ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text("No items added yet", style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                ],
              ),
            )
            // WRAPPED IN REPAINT BOUNDARY FOR SCREENSHOT
            : SingleChildScrollView(
              child: RepaintBoundary(
                key: _printKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // SCREENSHOT HEADER
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.deepPurple.shade200, width: 1.0)
                        ),
                        child: const Column(
                          children: [
                            Text("Asha Grill House", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                            SizedBox(height: 4),
                            Text("~Biggyan Das | 9932134803", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
                          ],
                        ),
                      ),

                      // LIST OF ITEMS
                      ..._currentOrders.map((order) {
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            leading: CircleAvatar(
                              radius: 24, // Bigger avatar
                              backgroundColor: Colors.deepPurple.shade100,
                              child: const Icon(Icons.shopping_bag, color: Colors.deepPurple, size: 24),
                            ),
                            title: Text(order['item'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), // Bigger title
                            subtitle: Text("${order['qty']} ${order['unit']}", style: TextStyle(color: Colors.grey.shade800, fontSize: 16, fontWeight: FontWeight.w600)), // Bigger subtitle
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28),
                              onPressed: () => _deleteOrder(order['id']),
                            ),
                          ),
                        );
                      }).toList(),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // SEND BUTTON FIXED AT THE BOTTOM
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -4))]),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60), // Taller Button
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showSendOptions,
              icon: const Icon(Icons.send, size: 28),
              label: const Text("Send Order", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), // Bigger Text
            ),
          )
        ],
      ),
    );
  }
}

// =====================================================================
// ORDER HISTORY PAGE (NEW DESIGN - GROUPED BY DATE)
// =====================================================================

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({Key? key}) : super(key: key);

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  Map<String, List<Map<String, dynamic>>> _historyOrders = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // Fetch and group history by date
  Future<void> _loadHistory() async {
    final history = await DBHelper.getHistoryOrders();

    Map<String, List<Map<String, dynamic>>> groupedHistory = {};
    for (var item in history) {
      String date = item['date'] ?? 'Unknown Date';
      if (!groupedHistory.containsKey(date)) {
        groupedHistory[date] = [];
      }
      groupedHistory[date]!.add(item);
    }

    setState(() {
      _historyOrders = groupedHistory;
    });
  }

  // Delete a single item
  Future<void> _deleteSingleOrder(int id) async {
    await DBHelper.deleteOrder(id);
    _loadHistory();
  }

  // Delete an entire section by looping through their IDs
  Future<void> _deleteGroup(String date, List<Map<String, dynamic>> items) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Order Group", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Text(
          "Are you sure you want to delete all ${items.length} orders from:\n\n$date?",
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(fontSize: 16))
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete All", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ??
    false;

    if (confirm) {
      // Loop through all items in this section and delete them by ID
      for (var order in items) {
        await DBHelper.deleteOrder(order['id']);
      }

      _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order group deleted successfully!')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        title: const Text("Order History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
          elevation: 0,
      ),
      body: _historyOrders.isEmpty
      ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text("No previous orders found", style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          ],
        ),
      )
      : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _historyOrders.keys.length,
        itemBuilder: (context, index) {
          String date = _historyOrders.keys.elementAt(index);
          List<Map<String, dynamic>> items = _historyOrders[date]!;

          return Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ==========================================
                // SECTION HEADER (Date/Time & Group Delete)
                // ==========================================
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    border: Border(bottom: BorderSide(color: Colors.deepPurple.shade100, width: 1.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month, color: Colors.deepPurple, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                date,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 🔴 DELETE ENTIRE GROUP BUTTON
                      IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 26),
                        tooltip: "Delete entire group",
                        onPressed: () => _deleteGroup(date, items),
                      ),
                    ],
                  ),
                ),

                // ==========================================
                // LIST OF ITEMS FOR THIS DATE
                // ==========================================
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: items.map((order) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          title: Text(order['item'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            "${order['qty']} ${order['unit']}",
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                            onPressed: () => _deleteSingleOrder(order['id']),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
