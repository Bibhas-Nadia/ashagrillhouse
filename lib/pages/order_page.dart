
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../db_helper.dart';

class OrderPage extends StatefulWidget {
  const OrderPage({Key? key}) : super(key: key);

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  List<Map<String, dynamic>> _currentOrders = [];
  final GlobalKey _printKey = GlobalKey();

  late stt.SpeechToText _speech;
  bool _isListening = false;

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
    _speech = stt.SpeechToText();
    _loadData();
  }

  Future<void> _loadData() async {
    final pending = await DBHelper.getPendingOrders();
    setState(() {
      _currentOrders = pending;
    });
  }

  Future<void> _confirmDelete(int id, String itemName) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove Item"),
        content: Text("Are you sure you want to remove '$itemName'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DBHelper.deleteOrder(id);
      _loadData();
    }
  }

  // Helper dialog to add unit name dynamically with mic support
  Future<String?> _showAddUnitDialog() async {
    TextEditingController unitInputCtrl = TextEditingController();
    bool isUnitListening = false;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add New Unit Name"),
              content: TextField(
                controller: unitInputCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "Enter unit name...",
                  suffixIcon: IconButton(
                    icon: Icon(isUnitListening ? Icons.mic : Icons.mic_none, color: isUnitListening ? Colors.red : Colors.deepPurple),
                    onPressed: () async {
                      if (isUnitListening) {
                        _speech.stop();
                        setDialogState(() => isUnitListening = false);
                      } else {
                        bool available = await _speech.initialize();
                        if (available) {
                          setDialogState(() => isUnitListening = true);
                          _speech.listen(
                            localeId: "bn_IN",
                            onResult: (result) {
                              setDialogState(() {
                                unitInputCtrl.text = result.recognizedWords;
                                if (result.finalResult) isUnitListening = false;
                              });
                            },
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, unitInputCtrl.text.trim());
                  },
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // MAIN ADD ITEM MODAL
  void _showAddItemModal() {
    TextEditingController searchController = TextEditingController();
    TextEditingController customItemController = TextEditingController();
    TextEditingController qtyController = TextEditingController(text: "0");

    String? selectedItemName;
    String selectedUnit = _unitsList.first;
    List<String> filteredItems = List.from(_itemsList);

    bool isCustomItemMode = false;
    bool isListeningSearch = false;
    bool isListeningCustomItem = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 16, right: 16, top: 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 16),

                    if (!isCustomItemMode) ...[
                      // 1. Search Box with Mic
                      TextField(
                        controller: searchController,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          labelText: 'Search predefined list...',
                          prefixIcon: const Icon(Icons.search, color: Colors.deepPurple),
                          suffixIcon: IconButton(
                            icon: Icon(isListeningSearch ? Icons.mic : Icons.mic_none, color: isListeningSearch ? Colors.red : Colors.deepPurple),
                            onPressed: () async {
                              if (isListeningSearch) {
                                _speech.stop();
                                setModalState(() => isListeningSearch = false);
                              } else {
                                bool available = await _speech.initialize();
                                if (available) {
                                  setModalState(() => isListeningSearch = true);
                                  _speech.listen(
                                    localeId: "bn_IN",
                                    onResult: (result) {
                                      setModalState(() {
                                        searchController.text = result.recognizedWords;
                                        filteredItems = _itemsList
                                        .where((item) => item.toLowerCase().contains(result.recognizedWords.toLowerCase()))
                                        .toList();
                                        if (result.finalResult) isListeningSearch = false;
                                      });
                                    },
                                  );
                                }
                              }
                            },
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            filteredItems = _itemsList
                            .where((item) => item.toLowerCase().contains(val.toLowerCase()))
                            .toList();
                          });
                        },
                      ),
                      const SizedBox(height: 8),

                      if (selectedItemName != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Text(
                            "Selected: $selectedItemName",
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),

                        // 2. Scrollable Predefined List View
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12)
                            ),
                            child: ListView.separated(
                              itemCount: filteredItems.length + 1,
                              separatorBuilder: (ctx, idx) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                // Custom "Others" option embedded directly inside the list view
                                if (index == filteredItems.length) {
                                  return ListTile(
                                    tileColor: Colors.deepPurple.shade50,
                                    leading: const Icon(Icons.add_circle, color: Colors.deepPurple),
                                    title: const Text("Others (Custom Item Name)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                    onTap: () {
                                      setModalState(() {
                                        isCustomItemMode = true;
                                        selectedItemName = null;
                                      });
                                    },
                                  );
                                }

                                final currentListItem = filteredItems[index];
                                final isCurrentSelected = selectedItemName == currentListItem;

                                return ListTile(
                                  dense: true,
                                  selected: isCurrentSelected,
                                  selectedTileColor: Colors.deepPurple.shade50,
                                  title: Text(
                                    currentListItem,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: isCurrentSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isCurrentSelected ? Colors.deepPurple : Colors.black87
                                    )
                                  ),
                                  trailing: isCurrentSelected ? const Icon(Icons.check_circle, color: Colors.deepPurple) : null,
                                  onTap: () {
                                    setModalState(() {
                                      selectedItemName = currentListItem;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                    ] else ...[
                      // 3. Alternate "Others" input layout
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Adding Custom Item Mode",
                              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setModalState(() {
                                isCustomItemMode = false;
                                customItemController.clear();
                              });
                            },
                            icon: const Icon(Icons.list, size: 18),
                            label: const Text("Predefined List")
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: customItemController,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          labelText: 'Enter Custom Item Name...',
                          prefixIcon: const Icon(Icons.edit, color: Colors.deepPurple),
                          suffixIcon: IconButton(
                            icon: Icon(isListeningCustomItem ? Icons.mic : Icons.mic_none, color: isListeningCustomItem ? Colors.red : Colors.deepPurple),
                            onPressed: () async {
                              if (isListeningCustomItem) {
                                _speech.stop();
                                setModalState(() => isListeningCustomItem = false);
                              } else {
                                bool available = await _speech.initialize();
                                if (available) {
                                  setModalState(() => isListeningCustomItem = true);
                                  _speech.listen(
                                    localeId: "bn_IN",
                                    onResult: (result) {
                                      setModalState(() {
                                        customItemController.text = result.recognizedWords;
                                        if (result.finalResult) isListeningCustomItem = false;
                                      });
                                    },
                                  );
                                }
                              }
                            },
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                      const Spacer(),
                    ],

                    const SizedBox(height: 12),

                    // 4. Quantity Field (Clears default 0 on tap) & Unit Select Options
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: qtyController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            onTap: () {
                              if (qtyController.text == "0") {
                                qtyController.clear();
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Qty',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        Expanded(
                          flex: 5,
                          child: DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'Unit',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            value: _unitsList.contains(selectedUnit) ? selectedUnit : _unitsList.first,
                            style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold),
                            items: [
                              ..._unitsList.map((String val) {
                                return DropdownMenuItem(
                                  value: val,
                                  child: Text(val),
                                );
                              }),
                              const DropdownMenuItem(
                                value: "ADD_NEW_UNIT_OPTION",
                                child: Text("➕ Others (Add Unit)", style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                              )
                            ],
                            onChanged: (val) async {
                              if (val == "ADD_NEW_UNIT_OPTION") {
                                String? dynamicUnit = await _showAddUnitDialog();
                                if (dynamicUnit != null && dynamicUnit.isNotEmpty) {
                                  setState(() {
                                    if (!_unitsList.contains(dynamicUnit)) {
                                      _unitsList.add(dynamicUnit);
                                    }
                                  });
                                  setModalState(() {
                                    selectedUnit = dynamicUnit;
                                  });
                                }
                              } else if (val != null) {
                                setModalState(() => selectedUnit = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 5. Add to Notepad Action Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        String finalItemName = "";

                        if (isCustomItemMode) {
                          finalItemName = customItemController.text.trim();
                        } else {
                          // Strict list requirement rule
                          if (selectedItemName == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select an item from the list or tap Others.'))
                            );
                            return;
                          }
                          finalItemName = selectedItemName!;
                        }

                        if (finalItemName.isEmpty) return;

                        String finalQty = qtyController.text.trim();
                        if (finalQty.isEmpty || finalQty == "0") finalQty = "0";

                        DateTime now = DateTime.now();
                        String timeString = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour}:${now.minute}";

                        await DBHelper.insertOrder({
                          "item": finalItemName,
                          "qty": finalQty,
                          "unit": selectedUnit,
                          "status": "pending",
                          "date": timeString
                        });

                        _loadData();
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text("Add to Notepad", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendTextToWhatsApp() async {
    Navigator.pop(context);
    String message = "Asha Grill House\n~Biggyan Das|9932134803\n--------------------------\n";
    message += _currentOrders.map((o) => "▪ ${o['item']} - ${o['qty']} ${o['unit']}").join("\n");

    await DBHelper.sendOrders();
    _loadData();

    final Uri url = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(message)}");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open messaging app')));
    }
  }

  Future<void> _shareScreenshot() async {
    Navigator.pop(context);
    try {
      await Future.delayed(const Duration(milliseconds: 200));

      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      File imgFile = File('${directory.path}/order_list.png');
      await imgFile.writeAsBytes(pngBytes);

      await DBHelper.sendOrders();
      _loadData();

      await Share.shareXFiles([XFile(imgFile.path)], text: 'Order from Asha Grill House');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error taking screenshot: $e')));
    }
  }

  void _showSendOptions() {
    if (_currentOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items to send!')));
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 20),
              const Text("Send Order", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: Colors.green.shade50,
                leading: const Icon(Icons.chat, color: Colors.green),
                title: const Text("WhatsApp Text", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                onTap: _sendTextToWhatsApp,
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: Colors.blue.shade50,
                leading: const Icon(Icons.image, color: Colors.blue),
                title: const Text("Share Image", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                onTap: _shareScreenshot,
              ),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        title: const Text('New Order', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OrderHistoryPage())),
            ),
          ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _currentOrders.isEmpty
            ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_note, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text("Notepad is empty", style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                ],
              ),
            )
            : SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: RepaintBoundary(
                key: _printKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade400, width: 1),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade400, width: 2))
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text("Asha Grill House", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black)),
                            Text("~Biggyan Das | 9932134803", style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _currentOrders.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
                        itemBuilder: (context, index) {
                          var order = _currentOrders[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    order['item'],
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black87)
                                  ),
                                ),
                                Text(
                                  "${order['qty']} ${order['unit']}",
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () => _confirmDelete(order['id'], order['item']),
                                  child: const Icon(Icons.close, color: Colors.red, size: 22),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.black12))
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.deepPurple, width: 1.5),
                    ),
                    onPressed: _showAddItemModal,
                    icon: const Icon(Icons.add, color: Colors.deepPurple),
                    label: const Text("Add Item", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _showSendOptions,
                    icon: const Icon(Icons.send),
                    label: const Text("Send", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// =====================================================================
// ORDER HISTORY PAGE
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

  Future<void> _deleteGroup(String date, List<Map<String, dynamic>> items) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete History"),
        content: Text("Delete all ${items.length} orders from $date?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      for (var order in items) {
        await DBHelper.deleteOrder(order['id']);
      }
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("History", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
          elevation: 0,
      ),
      body: _historyOrders.isEmpty
      ? const Center(child: Text("No previous orders found", style: TextStyle(color: Colors.grey)))
      : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _historyOrders.keys.length,
        itemBuilder: (context, index) {
          String date = _historyOrders.keys.elementAt(index);
          List<Map<String, dynamic>> items = _historyOrders[date]!;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.grey.shade200,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
                      GestureDetector(
                        onTap: () => _deleteGroup(date, items),
                        child: const Icon(Icons.delete, color: Colors.red, size: 20),
                      ),
                    ],
                  ),
                ),
                ...items.map((order) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(order['item'], style: const TextStyle(fontSize: 15))),
                        Text("${order['qty']} ${order['unit']}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        },
      ),
    );
  }
}
