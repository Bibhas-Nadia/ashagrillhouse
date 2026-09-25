
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sqflite/sqflite.dart';
import '../db_helper.dart';
import '../models/customer.dart';
import '../models/receipt_item.dart';
import '../utils/sms_helper.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../backup_service.dart'; // Adjust path if needed

class CustomerReceiptPage extends StatefulWidget {
  final Customer customer;

  const CustomerReceiptPage({Key? key, required this.customer}) : super(key: key);

  @override
  _CustomerReceiptPageState createState() => _CustomerReceiptPageState();
}

class _CustomerReceiptPageState extends State<CustomerReceiptPage> {
  final ScrollController _scrollController = ScrollController();

  List<ReceiptItem> _appData = [];
  List<Map<String, dynamic>> _savedBills = [];
  String? _editingBillId;
  String _editingBillDate = "";

  bool _isWorkspaceOpen = false;
  bool _isLoading = true;
  bool _sendSmsOnSave = true;

  int _itemIdCounter = 1;
  int _currentTabIndex = 0;
  bool _isFabVisible = true;
  bool _isExporting = false;
  late stt.SpeechToText _speech;
  bool _isListening = false;

  final Map<String, Map<String, dynamic>> _unitDB = {
    'Ton(টন)': {'cat': 'weight', 'factorToKG': 1000.0},
    'Kg(কেজি)': {'cat': 'weight', 'factorToKG': 1.0},
    'G(গ্রাম)': {'cat': 'weight', 'factorToKG': 0.001},
    'Piece(টা/টি)': {'cat': 'count'},
    'Packet(প্যাকেট)': {'cat': 'count'},
    'Box(বাক্স)': {'cat': 'count'},
    'Foot(ফুট)': {'cat': 'count'},
    'SquareFoot(স্কোয়ার ফুট)': {'cat': 'count'},
    'Day(দিন)': {'cat': 'count'},
    '--': {'cat': '--'}
  };

  final List<String> _itemNames = [
    "Grill(পুরোনো গ্রিল)", "Wages(মজুরি)", "Iron(লোহা)", "Sheet(শিট)", "Bar(বার)",
    "Pipe(পাইপ)", "Tin(টিন)", "Net(নেট)", "Flower(ফুল)", "Leaf(পাতা)", "Ball(বল)",
    "Cone(কোন)", "Handel(হ্যান্ডেল)","Design(ডিজাইন)", "Hinges(কব্জা)", "Others(অন্যান্য)"
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadSavedCalculation();
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isFabVisible) setState(() => _isFabVisible = false);
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_isFabVisible) setState(() => _isFabVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCalculation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<Map<String, dynamic>> dbRecords = await DBHelper.getCustomerCalculations(widget.customer.id!);

      _savedBills = [];
      _appData = [];

      if (dbRecords.isNotEmpty) {
        for (var record in dbRecords) {
          String jsonStr = record['calculationJson'];
          var decoded = jsonDecode(jsonStr);

          bool isDraft = false;
          List decodedList = [];

          // Check if this is the new explicit format or old format fallback
          if (decoded is Map && decoded.containsKey('type')) {
            isDraft = (decoded['type'] == 'draft');
            decodedList = decoded['items'] ?? [];
          } else if (decoded is List) {
            decodedList = decoded;
            // Fallback for older legacy bills before this fix
            isDraft = decodedList.any((item) => item['status'] == 'rough');
          }

          // If it's explicitly a draft, assign it as the current active workspace
          if (isDraft && _appData.isEmpty) {
            _editingBillId = record['id'].toString();
            _editingBillDate = record['datetime'];
            _appData = decodedList.map((e) => ReceiptItem.fromMap(e)).toList();

            if (_appData.isNotEmpty) {
              _itemIdCounter = _appData.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
            }
          } else {
            // Otherwise, it is a finalized bill. Add it to the saved bills list.
            _savedBills.add({
              "billId": record['id'].toString(),
              "date": record['datetime'],
              "items": decodedList,
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading calculation history: $e");
    }

    double realLiveDue = 0.0;
    try {
      final dbClient = await DBHelper.db;
      final List<Map<String, dynamic>> res = await dbClient.query(
        "customers",
        columns: ["due"],
        where: "id = ?",
        whereArgs: [widget.customer.id],
      );
      if (res.isNotEmpty && res.first['due'] != null) {
        realLiveDue = double.tryParse(res.first['due'].toString()) ?? 0.0;
      } else {
        realLiveDue = double.tryParse(widget.customer.due.toString()) ?? 0.0;
      }
    } catch (e) {
      realLiveDue = double.tryParse(widget.customer.due.toString()) ?? 0.0;
    }

    setState(() {
      if (_savedBills.isEmpty && _appData.isEmpty) {
        _isWorkspaceOpen = true;
        _isFabVisible = true;

        if (realLiveDue > 0) {
          _appData.add(ReceiptItem(
            id: _itemIdCounter++,
            name: "পূর্বের বকেয়া (Previous Due)",
            originalUnit: "Rupees",
            currentUnit: "Rupees",
            qty: realLiveDue,
            prePriceQty: realLiveDue,
            rate: 1,
            totalPrice: realLiveDue,
            history: "আগের বাকি টাকা",
            status: "billed"
          ));
        }
      } else {
        _isWorkspaceOpen = false;
      }

      widget.customer.due = realLiveDue.toString();
      _isLoading = false;
    });
  }





  String _formatDisplayDate(String dateStr) {
    if (dateStr.isEmpty) return "";

    DateTime? dt = DateTime.tryParse(dateStr);

    // Fallback for custom formats like "07-09-2026 01:11pm"
    if (dt == null) {
      try {
        List<String> parts = dateStr.split(" ");
        if (parts.length >= 2) {
          List<String> dateParts = parts[0].split("-");
          if (dateParts.length == 3) {
            int day = int.parse(dateParts[0]);
            int month = int.parse(dateParts[1]);
            int year = int.parse(dateParts[2]);
            dt = DateTime(year, month, day);
          }
        }
      } catch (_) {}
    }

    if (dt != null) {
      List<String> months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];

      String day = dt.day.toString().padLeft(2, '0');
      String monthStr = months[dt.month - 1];
      String yearStr = dt.year.toString().substring(2);

      int hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      String minuteStr = dt.minute.toString().padLeft(2, '0');
      String amPm = dt.hour >= 12 ? 'pm' : 'am';

      return "$day $monthStr $yearStr, $hour12:$minuteStr $amPm";
    }

    return dateStr;
  }




  // Future<void> _persistCurrentState() async {
  //   Map<String, dynamic> outputWrapper = {
  //     "currentDraft": _appData.map((e) => e.toMap()).toList(),
  //     "savedBills": _savedBills,
  //   };
  //   String jsonStr = jsonEncode(outputWrapper);
  //   await DBHelper.saveReceiptCalculation(widget.customer.id!, jsonStr);
  // }


  Future<void> _persistCurrentState() async {
    // Prevent empty row creation
    if (_appData.isEmpty && _editingBillId == null) {
      return;
    }

    // Wrap the items in a map to explicitly declare this as an unfinished DRAFT
    Map<String, dynamic> wrapper = {
      "type": "draft",
      "items": _appData.map((e) => e.toMap()).toList()
    };
    String jsonStr = jsonEncode(wrapper);

    if (_editingBillId != null) {
      // Update existing database row
      await DBHelper.updateReceiptCalculation(int.parse(_editingBillId!), jsonStr);
    } else {
      // Create new draft row
      int newId = await DBHelper.insertReceiptCalculation(widget.customer.id!, jsonStr);
      _editingBillId = newId.toString();
    }
  }








  Future<bool> _confirmAction(String title, String content) async {
    return await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        content: Text(content, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("ক্যান্সেল (Cancel)", style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("হ্যাঁ (Confirm)", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      )
    ) ?? false;
  }

  Widget _showBillManagerDashboardInline() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 3,
            ),
            icon: const Icon(Icons.add_circle_outline, size: 26),
            label: const Text("নতুন বিল তৈরি করুন", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            onPressed: () async {
              if (_appData.isNotEmpty) {
                bool confirm = await _confirmAction("নতুন বিল?", "আপনার বর্তমান কাজ মুছে যাবে। আপনি কি নতুন বিল তৈরি করতে চান?");
                if (!confirm) return;
              }

              double realLiveDue = double.tryParse(widget.customer.due.toString()) ?? 0.0;

              setState(() {
                _appData = [];
                _editingBillId = null;
                _editingBillDate = "";
                _itemIdCounter = 1;

                if (realLiveDue > 0) {
                  _appData.add(ReceiptItem(
                    id: _itemIdCounter++,
                    name: "পূর্বের বকেয়া (Previous Due)",
                    originalUnit: "Rupees",
                    currentUnit: "Rupees",
                    qty: realLiveDue,
                    prePriceQty: realLiveDue,
                    rate: 1,
                    totalPrice: realLiveDue,
                    history: "আগের বাকি টাকা",
                    status: "billed"
                  ));
                }

                _isWorkspaceOpen = true;
                _currentTabIndex = 0;
                _isFabVisible = true;
              });
              await _persistCurrentState();
            },
          ),
          const SizedBox(height: 24),

          if (_appData.isNotEmpty) ...[
            Text("বর্তমান অসম্পূর্ণ বিল (DRAFT)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700, fontSize: 13, letterSpacing: 1.0)),
            const SizedBox(height: 8),
            Card(
              color: Colors.orange.shade50,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orange.shade300, width: 1.5)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.edit_document, color: Colors.orange.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "চলতি কাজ (Active)",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange.shade900),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text("${_appData.length} টি আইটেম প্যাডে আছে।", style: TextStyle(color: Colors.grey.shade800, fontSize: 14)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text("কাজ চালিয়ে যান (Resume)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: () {
                        setState(() {
                          _isWorkspaceOpen = true;
                          _isFabVisible = true;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          Text("আগের বিলের তালিকা ( ${_savedBills.length})", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700, fontSize: 13, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          if (_savedBills.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text("কোনো সেভ করা বিল নেই।", style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _savedBills.length,
                itemBuilder: (context, index) {
                  final bill = _savedBills[index];
                  List<dynamic> itemsRaw = bill['items'] ?? [];

                  double billTotal = 0.0;
                  for (var item in itemsRaw) {
                    if (item['status'] == 'billed') {
                      billTotal += (item['totalPrice'] as num).toDouble();
                    }
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Text(bill['date'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                //
                                Text(
                                  _formatDisplayDate(bill['date'] ?? ""),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis
                                ),

                                const SizedBox(height: 4),
                                Text("${itemsRaw.length} টি আইটেম", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
                            child: Text("₹ ${billTotal.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green.shade800, fontSize: 13)),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                tooltip: "আপডেট (Update)",
                                onPressed: () async {
                                  if (_appData.isNotEmpty) {
                                    bool confirm = await _confirmAction("বিল লোড করবেন?", "এই বিলটি আপনার বর্তমান কাজ মুছে ফেলবে। লোড করবেন?");
                                    if (!confirm) return;
                                  }
                                  setState(() {
                                    _editingBillId = bill['billId'].toString();
                                    _editingBillDate = bill['date'] ?? "";
                                    _appData = itemsRaw.map((e) {
                                      var item = ReceiptItem.fromMap(e);
                                      item.status = "rough";
                                      return item;
                                    }).toList();

                                    if (_appData.isNotEmpty) {
                                      _itemIdCounter = _appData.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
                                    }
                                    _isWorkspaceOpen = true;
                                    _currentTabIndex = 0;
                                    _isFabVisible = true;
                                  });
                                  await _persistCurrentState();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                tooltip: "ডিলিট (Delete)",
                                onPressed: () async {
                                  bool confirm = await _confirmAction(
                                                                                          "আগের বিল ডিলিট করবেন?",
                                                                                          "এই বিলটি চিরতরে মুছে যাবে এবং আর ফিরে পাওয়া যাবে না। আপনি কি নিশ্চিত?",
                                  );

                                  if (confirm) {
                                    String billIdToDelete = bill['billId'].toString();
                                    int? billIntId = int.tryParse(billIdToDelete);

                                    // 1. Delete from receipt_calculations table in Database
                                    if (billIntId != null) {
                                      await DBHelper.deleteReceiptCalculation(billIntId);
                                    }

                                    // 2. Remove the specific <receipt> tag safely using Regex
                                    String currentImages = widget.customer.images;

                                    // Matches <receipt> exactly with this ID, followed by &, until </receipt>
                                    RegExp regex = RegExp('<receipt>$billIdToDelete&.*?</receipt>');
                                    currentImages = currentImages.replaceAll(regex, '');

                                    // Clean up any stray or double commas left behind
                                    currentImages = currentImages.replaceAll(RegExp(r',+'), ',');
                                    if (currentImages.startsWith(',')) currentImages = currentImages.substring(1);
                                    if (currentImages.endsWith(',')) currentImages = currentImages.substring(0, currentImages.length - 1);

                                    // Save the cleaned string back to the database
                                    await DBHelper.updateCustomerImages(widget.customer.id!, currentImages);
                                    widget.customer.images = currentImages;

                                    // 3. Update local state
                                    setState(() {
                                      _savedBills.removeAt(index);
                                      if (_editingBillId == billIdToDelete) {
                                        _editingBillId = null;
                                        _editingBillDate = "";
                                        _appData = [];
                                      }
                                    });

                                    await _persistCurrentState();

                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("বিলটি সফলভাবে মুছে ফেলা হয়েছে।"),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),




                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }

  void _executeMath(ReceiptItem target, double rawVal, String? sourceName, String sourceUnit, String operator) {
    double valToAddOrSub = rawVal;
    String conversionNote = "";

    if ((operator == '+' || operator == '-') && _unitDB.containsKey(sourceUnit) && _unitDB.containsKey(target.currentUnit)) {
      var sInfo = _unitDB[sourceUnit]!;
      var tInfo = _unitDB[target.currentUnit]!;

      if (sInfo['cat'] == tInfo['cat'] && sInfo['factorToKG'] != null && tInfo['factorToKG'] != null) {
        double valInBase = rawVal * sInfo['factorToKG'];
        valToAddOrSub = valInBase / tInfo['factorToKG'];
        if (valToAddOrSub != rawVal) {
          conversionNote = " [Auto]";
        }
      }
    }

    setState(() {
      String logText = sourceName != null
      ? "\n$operator $rawVal $sourceUnit $sourceName$conversionNote"
      : "\n$operator $rawVal ${sourceUnit == "Rupees" ? "₹" : (sourceUnit == "একই (Same)" ? "" : sourceUnit)}";

      if (operator == '+') {
        target.qty += valToAddOrSub;
        target.history += logText;
      } else if (operator == '-') {
        target.qty -= valToAddOrSub;
        target.history += logText;
      } else if (operator == '/') {
        if (rawVal != 0) {
          target.qty /= rawVal;
          target.history += logText;
        }
      } else if (operator == '*') {
        if (sourceUnit == "Rupees") {
          target.prePriceQty = target.qty;
          target.originalUnit = target.currentUnit;
          target.rate = rawVal;
          target.totalPrice = target.qty * rawVal;
          target.qty = target.totalPrice;
          target.currentUnit = "Rupees";
          target.history += "\n× $rawVal টাকা";
        } else {
          target.qty *= rawVal;
          if (sourceUnit != "একই (Same)") {
            target.currentUnit = sourceUnit;
          }
          target.history += logText;
        }
      }
      target.qty = double.parse(target.qty.toStringAsFixed(3));
    });
    _persistCurrentState();
  }

  void _showAddItemSheet() {
    String selectedItem = 'Iron(লোহা)';
    String selectedUnit = 'Kg(কেজি)';
    TextEditingController qtyController = TextEditingController();
    TextEditingController customNameController = TextEditingController();
    bool isCustom = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 24, left: 20, right: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("প্যাডে যোগ করুন (Add to Pad)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey), textAlign: TextAlign.center),
                      const SizedBox(height: 20),

                      DropdownButtonFormField<String>(
                        value: selectedItem,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: "মালপত্র/কাজের নাম (Item)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        items: _itemNames.map((String val) => DropdownMenuItem(value: val, child: Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))).toList(),
                        onChanged: (val) {
                          selectedItem = val!;
                          if (selectedItem == 'Others(অন্যান্য)') {
                            isCustom = true;
                            selectedUnit = 'Piece(টা/টি)';
                          } else {
                            isCustom = false;
                            if (['Iron(লোহা)', 'Sheet(শিট)', 'Tin(টিন)', 'Pipe(পাইপ)', 'Grill(পুরোনো গ্রিল)'].contains(selectedItem)) {
                              selectedUnit = 'Kg(কেজি)';
                            } else if (['Wages(মজুরি)'].contains(selectedItem)) {
                              selectedUnit = 'Day(দিন)';
                            } else {
                              selectedUnit = 'Piece(টা/টি)';
                            }
                          }
                          setModalState((){});
                        },
                      ),

                      if (isCustom) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: customNameController,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: "আইটেমের নাম লিখুন (Custom Name)",
                            hintText: "নিজের মতো নাম লিখুন",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isListening ? Icons.mic : Icons.mic_none,
                                color: _isListening ? Colors.redAccent : Colors.grey.shade400,
                                size: 26,
                              ),
                              onPressed: () async {
                                if (_isListening) {
                                  _speech.stop();
                                  setModalState(() => _isListening = false);
                                } else {
                                  bool available = await _speech.initialize();
                                  if (available) {
                                    setModalState(() => _isListening = true);
                                    _speech.listen(
                                      localeId: "bn_IN",
                                      onResult: (result) {
                                        setModalState(() {
                                          customNameController.text = result.recognizedWords;
                                          if (result.finalResult) {
                                            _isListening = false;
                                          }
                                        });
                                      },
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: TextField(
                              controller: qtyController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(labelText: "পরিমাণ (Qty)", hintText: "0.0", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              value: selectedUnit,
                              isExpanded: true,
                              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                              items: _unitDB.keys.map((String val) => DropdownMenuItem(value: val, child: Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)))).toList(),
                              onChanged: (val) => setModalState(() => selectedUnit = val!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () {
                          double? qty = double.tryParse(qtyController.text);
                          if (qty != null) {
                            String finalName = isCustom && customNameController.text.trim().isNotEmpty
                            ? customNameController.text.trim()
                            : selectedItem;

                            setState(() {
                              _appData.add(ReceiptItem(id: _itemIdCounter++, name: finalName, originalUnit: selectedUnit, currentUnit: selectedUnit, qty: qty, prePriceQty: qty, rate: 0, totalPrice: 0, history: "$qty $selectedUnit", status: "rough"));
                            });
                            _persistCurrentState();
                            Navigator.pop(context);
                          }
                        },
                        child: const Text("যোগ করুন (ADD)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _showMathSheet(ReceiptItem target, String operatorStr) {
    TextEditingController valController = TextEditingController();
    String targetCat = _unitDB[target.currentUnit]?['cat'] ?? '';
    List<String> unitsAllowed = [];

    if (operatorStr == '+' || operatorStr == '-') {
      unitsAllowed = _unitDB.keys.where((k) => _unitDB[k]?['cat'] == targetCat).toList();
    } else if (operatorStr == '*') {
      unitsAllowed = ['Rupees', 'একই (Same)', ..._unitDB.keys];
    } else {
      unitsAllowed = ['একই (Same)'];
    }

    String selectedUnit = unitsAllowed.first;
    List<ReceiptItem> compatibleCards = _appData.where((i) => i.id != target.id && i.status == "rough" && (operatorStr == '*' || _unitDB[i.currentUnit]?['cat'] == targetCat)).toList();

    setState(() => _isFabVisible = false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 24, left: 20, right: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text("হিসাব করুন: [ $operatorStr ] ${target.name}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey), textAlign: TextAlign.center),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextField(
                                    controller: valController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(labelText: "পরিমাণ লিখুন", hintText: "0.0", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 4,
                                  child: DropdownButtonFormField<String>(
                                    value: selectedUnit,
                                    isExpanded: true,
                                    decoration: InputDecoration(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                                    items: unitsAllowed.map((String val) => DropdownMenuItem(value: val, child: Text(val == 'Rupees' ? 'টাকা (₹)' : val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)))).toList(),
                                    onChanged: (val) => setModalState(() => selectedUnit = val!),
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                              onPressed: () {
                                double? v = double.tryParse(valController.text);
                                if (v != null) {
                                  _executeMath(target, v, null, selectedUnit, operatorStr);
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text("হিসাব করুন (APPLY)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            )
                          ],
                        ),
                      ),

                      if (compatibleCards.isNotEmpty && (operatorStr == '+' || operatorStr == '-')) ...[
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: Text("অথবা অন্য আইটেমের ওজন নিন:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey), textAlign: TextAlign.center)),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: compatibleCards.map((srcCard) {
                            return ActionChip(
                              backgroundColor: Colors.green.shade50,
                              side: BorderSide(color: Colors.green.shade300, width: 1.5),
                              padding: const EdgeInsets.all(10),
                              label: Text("${srcCard.name} (${srcCard.qty} ${srcCard.currentUnit})", style: TextStyle(fontSize: 14, color: Colors.green.shade900, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                _executeMath(target, srcCard.qty, srcCard.name, srcCard.currentUnit, operatorStr);
                                Navigator.pop(context);
                              },
                            );
                          }).toList(),
                        )
                      ]
                    ],
                  ),
                ),
              ),
            );
          }
        );
      }
    ).then((_) {
      setState(() => _isFabVisible = true);
    });
  }

  void _showChangeUnitSheet(ReceiptItem card) {
    String selectedUnit = card.currentUnit;
    String targetCat = _unitDB[card.currentUnit]?['cat'] ?? '';
    List<String> unitsAllowed = _unitDB.keys.where((k) => _unitDB[k]?['cat'] == targetCat).toList();

    if (unitsAllowed.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, top: 20, left: 20, right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("ইউনিট পরিবর্তন: ${card.name}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: selectedUnit,
                isExpanded: true,
                decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                items: [
                  for (final val in unitsAllowed)
                    DropdownMenuItem(value: val, child: Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))
                ],
                onChanged: (val) => selectedUnit = val!,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  setState(() {
                    if (card.currentUnit != selectedUnit) {
                      var oldInfo = _unitDB[card.currentUnit]!;
                      var newInfo = _unitDB[selectedUnit]!;
                      double valInKG = card.qty * oldInfo['factorToKG'];
                      card.qty = valInKG / newInfo['factorToKG'];
                      card.currentUnit = selectedUnit;
                      card.history += "\n[Manual Swap -> $selectedUnit]";
                    }
                  });
                  _persistCurrentState();
                  Navigator.pop(context);
                },
                child: const Text("সেভ করুন (CONFIRM)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              )
            ],
          ),
        );
      }
    );
  }

  void _showAdvanceMoneySheet() async {
    final db = await DBHelper.db;
    List<Map<String, dynamic>> transactions = await db.query('transactions', where: 'customerId = ?', whereArgs: [widget.customer.id]);

    List<Map<String, dynamic>> modifiableTransactions = List<Map<String, dynamic>>.from(transactions);

    double currentDue = double.tryParse(widget.customer.due) ?? 0.0;
    if (currentDue < 0) {
      double advanceAmount = currentDue.abs();

      modifiableTransactions.insert(0, {
        "id": -999,
        "customerId": widget.customer.id,
        "amount": advanceAmount.toString(),
        "date": "বর্তমান জমা (Current Advance)",
        "note": "অ্যাডভান্স জমা থেকে কাটা হবে"
      });
    }

    if (transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("কোনো জমার রেকর্ড নেই!")));
      return;
    }

    List<Map<String, dynamic>> selectedTxs = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            double selectedTotal = selectedTxs.fold(0.0, (sum, tx) => sum + (double.tryParse(tx['amount'].toString()) ?? 0.0));

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("অ্যাডভান্স টাকা বেছে নিন", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const Text("ফাইনাল বিল থেকে বাদ দেওয়ার জন্য সিলেক্ট করুন।", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  const Divider(),

                  Expanded(
                    child: ListView.builder(
                      itemCount: modifiableTransactions.length,
                      itemBuilder: (context, index) {
                        var tx = modifiableTransactions[index];
                        bool isSelected = selectedTxs.any((element) => element['id'] == tx['id']);

                        return CheckboxListTile(
                          title: Text("অ্যাডভান্স: ₹ ${tx['amount']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                          subtitle: Text("তারিখ: ${tx['date']}\nনোট: ${tx['note']}"),
                          value: isSelected,
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                if (!selectedTxs.any((element) => element['id'] == tx['id'])) {
                                  selectedTxs.add(tx);
                                }
                              } else {
                                selectedTxs.removeWhere((element) => element['id'] == tx['id']);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("মোট বাদ যাবে:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("₹ ${selectedTotal.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.red)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: selectedTotal <= 0 ? null : () {
                      setState(() {
                        _appData.add(ReceiptItem(
                          id: _itemIdCounter++,
                          name: "Advance Paid Deducted",
                          originalUnit: "Rupees",
                          currentUnit: "Rupees",
                          qty: -selectedTotal,
                          prePriceQty: -selectedTotal,
                          rate: 1,
                          totalPrice: -selectedTotal,
                          history: "${selectedTxs.length} ট্রানজাকশন থেকে",
                          status: "billed"
                        ));
                      });
                      _persistCurrentState();
                      Navigator.pop(context);
                    },
                    child: const Text("অ্যাডভান্স বাদ দিন", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  // Future<void> _exportAndSaveFinalReceipt() async {
  //   FocusScope.of(context).unfocus();
  //
  //   setState(() {
  //     _currentTabIndex = 1;
  //     _isExporting = true;
  //   });
  //
  //   showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
  //
  //   try {
  //     // --- LOGIC: CREATE SIMPLE ID (1, 2, 3...) ---
  //     String newBillId = _editingBillId ?? "";
  //     if (newBillId.isEmpty) {
  //       int maxId = 0;
  //       for (var bill in _savedBills) {
  //         int currentId = int.tryParse(bill['billId']?.toString() ?? "0") ?? 0;
  //         if (currentId > maxId) {
  //           maxId = currentId;
  //         }
  //       }
  //       newBillId = (maxId + 1).toString(); // Increments simply 1, 2, 3...
  //     }
  //
  //     DateTime timeNow = DateTime.now();
  //     String customDateStamp = "${timeNow.day.toString().padLeft(2, '0')}-${timeNow.month.toString().padLeft(2, '0')}-${timeNow.year} ${timeNow.hour.toString().padLeft(2, '0')}:${timeNow.minute.toString().padLeft(2, '0')}";
  //
  //     // --- LOGIC: ONLY SAVING TEXT TAG, NO IMAGE FILE ---
  //     String receiptTag = "<receipt>$newBillId&$customDateStamp</receipt>";
  //
  //     List<String> userImages = widget.customer.images.split(",").where((s) => s.trim().isNotEmpty).toList();
  //     userImages.add(receiptTag);
  //     // WE NO LONGER ADD filePath HERE!
  //
  //     await DBHelper.updateCustomerImages(widget.customer.id!, userImages.join(","));
  //     widget.customer.images = userImages.join(",");
  //
  //     // --- SAVE NEW DUE TO DATABASE ---
  //     double finalDue = _getGrandTotal();
  //     await DBHelper.updateCustomerDue(widget.customer.id!, finalDue);
  //     widget.customer.due = finalDue.toString();
  //
  //     // --- SEND SMS AND LOG TO DB ---
  //     if (_sendSmsOnSave && widget.customer.phone.isNotEmpty && finalDue > 0) {
  //       try {
  //         String? status = await DBHelper.getStatus();
  //         String msg;
  //
  //         if (status == "active") {
  //           msg = "Dear ${widget.customer.name}\nYour bill is generated. "
  //           "Your current due is Rs. ${finalDue.toStringAsFixed(2)}. "
  //           "If any queries, contact us.\n\n- Asha Grill House\n"
  //           "View details: https://ashagrillhouse.github.io/site/receipt.html?q=${widget.customer.phone.replaceAll(RegExp(r'\D'), '').substring(widget.customer.phone.replaceAll(RegExp(r'\D'), '').length - 10)}";
  //         }
  //         else {
  //           msg = "Dear ${widget.customer.name}\nYour bill is generated. "
  //           "Your current due is Rs. ${finalDue.toStringAsFixed(2)}. "
  //           "If any queries, contact us.\n\n- Asha Grill House";
  //         }
  //
  //         await SmsHelper.sendSMS(
  //           phone: widget.customer.phone,
  //           message: msg,
  //         );
  //
  //         String nowStr = "${timeNow.day}-${timeNow.month}-${timeNow.year} ${timeNow.hour}:${timeNow.minute}";
  //         await DBHelper.insertMessage(widget.customer.id!, msg, nowStr);
  //       } catch (smsError) {
  //         debugPrint("SMS Error: $smsError");
  //       }
  //     }
  //
  //     // --- UPDATE JSON HISTORY LOG ---
  //     List<ReceiptItem> finalizedItems = _appData.where((e) => e.status == "billed").toList();
  //     if (finalizedItems.isEmpty) throw Exception("Cannot compile empty invoice.");
  //
  //     Map<String, dynamic> completeBillObj = {
  //       "billId": newBillId,
  //       "date": _editingBillId != null ? _editingBillDate : customDateStamp,
  //       "items": finalizedItems.map((e) => e.toMap()).toList(),
  //     };
  //
  //     if (_editingBillId != null) {
  //       int originalIdx = _savedBills.indexWhere((b) => b['billId'].toString() == _editingBillId);
  //       if (originalIdx != -1) {
  //         _savedBills[originalIdx] = completeBillObj;
  //       } else {
  //         _savedBills.add(completeBillObj);
  //       }
  //     } else {
  //       _savedBills.add(completeBillObj);
  //     }
  //
  //     _appData = [];
  //     _editingBillId = null;
  //     _editingBillDate = "";
  //     _itemIdCounter = 1;
  //
  //     await _persistCurrentState();
  //
  //     Navigator.pop(context); // Close loading dialog
  //     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("বিল সেভ হয়েছে এবং বকেয়া আপডেট করা হয়েছে!"), backgroundColor: Colors.green));
  //
  //     setState(() {
  //       _isWorkspaceOpen = false;
  //     });
  //   } catch (e) {
  //     Navigator.pop(context);
  //     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
  //   } finally {
  //     setState(() => _isExporting = false);
  //   }
  // }
  Future<void> _exportAndSaveFinalReceipt() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _currentTabIndex = 1;
      _isExporting = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. Get the final total amount
      double finalDue = _getGrandTotal();
      String amountStr = finalDue.toStringAsFixed(2);

      // 2. Generate simple ID (1, 2, 3...)
      String newBillId = _editingBillId ?? "";
      if (newBillId.isEmpty) {
        int maxId = 0;
        for (var bill in _savedBills) {
          int currentId = int.tryParse(bill['billId']?.toString() ?? "0") ?? 0;
          if (currentId > maxId) {
            maxId = currentId;
          }
        }
        newBillId = (maxId + 1).toString();
      }

      // 3. Format Date & Time in 12-hour format (e.g., 27-08-2026 12:00pm)
      DateTime timeNow = DateTime.now();
      int hour12 = timeNow.hour % 12 == 0 ? 12 : timeNow.hour % 12;
      String amPm = timeNow.hour >= 12 ? 'pm' : 'am';
      String timeStr = "${hour12.toString().padLeft(2, '0')}:${timeNow.minute.toString().padLeft(2, '0')}$amPm";
      String customDateStamp = "${timeNow.day.toString().padLeft(2, '0')}-${timeNow.month.toString().padLeft(2, '0')}-${timeNow.year} $timeStr";

      // 4. Formatted receipt tag: <receipt>ID&Amount&datetime</receipt>
      String receiptTag = "<receipt>$newBillId&$amountStr&$customDateStamp</receipt>";

      List<String> userImages = widget.customer.images
      .split(",")
      .where((s) => s.trim().isNotEmpty)
      .toList();
      userImages.add(receiptTag);

      await DBHelper.updateCustomerImages(widget.customer.id!, userImages.join(","));
      widget.customer.images = userImages.join(",");

      // --- SAVE NEW DUE TO DATABASE ---
      await DBHelper.updateCustomerDue(widget.customer.id!, finalDue);
      widget.customer.due = finalDue.toString();

      // --- SEND SMS AND LOG TO DB ---
      if (_sendSmsOnSave && widget.customer.phone.isNotEmpty && finalDue > 0) {
        try {
          String? status = await DBHelper.getStatus();
          String msg;

          if (status == "active") {
            msg = "Dear ${widget.customer.name}\nYour bill is generated. "
            "Your current due is Rs. $amountStr. "
            "If any queries, contact us.\n\n- Asha Grill House\n"
            "View details: https://ashagrillhouse.github.io/site/bill.html?q=${widget.customer.phone.replaceAll(RegExp(r'\D'), '').substring(widget.customer.phone.replaceAll(RegExp(r'\D'), '').length - 10)}";
          } else {
            msg = "Dear ${widget.customer.name}\nYour bill is generated. "
            "Your current due is Rs. $amountStr. "
            "If any queries, contact us.\n\n- Asha Grill House";
          }

          await SmsHelper.sendSMS(
            phone: widget.customer.phone,
            message: msg,
          );

          await DBHelper.insertMessage(widget.customer.id!, msg, customDateStamp);
        } catch (smsError) {
          debugPrint("SMS Error: $smsError");
        }
      }

      // // --- UPDATE JSON HISTORY LOG ---
      // List<ReceiptItem> finalizedItems = _appData.where((e) => e.status == "billed").toList();
      // if (finalizedItems.isEmpty) throw Exception("Cannot compile empty invoice.");
      //
      // String finalJsonStr = jsonEncode(finalizedItems.map((e) => e.toMap()).toList());
      //
      // if (_editingBillId != null) {
      //   // Update the existing row in SQLite
      //   await DBHelper.updateReceiptCalculation(int.parse(_editingBillId!), finalJsonStr);
      // } else {
      //   // Insert as a brand new row in SQLite
      //   await DBHelper.insertReceiptCalculation(widget.customer.id!, finalJsonStr);
      // }
      //
      //
      // Map<String, dynamic> completeBillObj = {
      //   "billId": newBillId,
      //   "date": _editingBillId != null ? _editingBillDate : customDateStamp,
      //   "items": finalizedItems.map((e) => e.toMap()).toList(),
      // };


      // --- UPDATE JSON HISTORY LOG ---
      List<ReceiptItem> finalizedItems = _appData.where((e) => e.status == "billed").toList();
      if (finalizedItems.isEmpty) throw Exception("Cannot compile empty invoice.");

      // Wrap the items in a map to explicitly declare this as FINALIZED
      Map<String, dynamic> finalWrapper = {
        "type": "finalized",
        "items": finalizedItems.map((e) => e.toMap()).toList()
      };
      String finalJsonStr = jsonEncode(finalWrapper);

      if (_editingBillId != null) {
        // Update the existing row in SQLite
        await DBHelper.updateReceiptCalculation(int.parse(_editingBillId!), finalJsonStr);
      } else {
        // Insert as a brand new row in SQLite
        await DBHelper.insertReceiptCalculation(widget.customer.id!, finalJsonStr);
      }

      // <-- ADD BACKUP HERE (Triggers only when saving/creating final bill)
      BackupService.autoBackupOnAppOpen();

      Map<String, dynamic> completeBillObj = {
        "billId": newBillId,
        "date": _editingBillId != null ? _editingBillDate : customDateStamp,
        "items": finalizedItems.map((e) => e.toMap()).toList(),
      };

      if (_editingBillId != null) {
        int originalIdx = _savedBills.indexWhere((b) => b['billId'].toString() == _editingBillId);
        if (originalIdx != -1) {
          _savedBills[originalIdx] = completeBillObj;
        } else {
          _savedBills.add(completeBillObj);
        }
      } else {
        _savedBills.add(completeBillObj);
      }

      // Clear workspace
      _appData = [];
      _editingBillId = null;
      _editingBillDate = "";
      _itemIdCounter = 1;

      //await _persistCurrentState();

      // Reload from database to update the _savedBills UI
      await _loadSavedCalculation();

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("বিল সেভ হয়েছে এবং বকেয়া আপডেট করা হয়েছে!"), backgroundColor: Colors.green),
      );

      setState(() {
        _isWorkspaceOpen = false;
      });
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isExporting = false);
    }
  }








  double _getGrandTotal() => _appData.where((e) => e.status == "billed").fold(0.0, (sum, item) => sum + item.totalPrice);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isWorkspaceOpen) {
      return Scaffold(
        backgroundColor: Colors.blueGrey.shade50,
        appBar: AppBar(
          title: Text(widget.customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          backgroundColor: Colors.blueGrey.shade900,
          foregroundColor: Colors.white,
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        ),
        body: _showBillManagerDashboardInline(),
      );
    }

    List<ReceiptItem> roughItems = _appData.where((element) => element.status == "rough").toList();
    List<ReceiptItem> billedItems = _appData.where((element) => element.status == "billed").toList();

    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      appBar: AppBar(
        title: const Text("ফাইনাল বিল (Final Bill)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: "ড্যাশবোর্ডে ফিরে যান",
            onPressed: () async {
              await _persistCurrentState();
              setState(() { _isWorkspaceOpen = false; });
            },
          ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        selectedItemColor: Colors.teal.shade800,
        unselectedItemColor: Colors.grey.shade500,
        iconSize: 28,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        onTap: (index) => setState(() {
          _currentTabIndex = index;
          if (index == 0) _isFabVisible = true;
        }),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.edit_note), label: "প্যাড (${roughItems.length})"),
          BottomNavigationBarItem(icon: const Icon(Icons.receipt_long), label: "ফাইনাল বিল (${billedItems.length})"),
        ],
      ),
      floatingActionButton: (_currentTabIndex == 0 && _isFabVisible)
      ? FloatingActionButton.extended(
        onPressed: _showAddItemSheet,
        backgroundColor: Colors.teal.shade700,
        elevation: 4,
        icon: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 24),
        label: const Text("নতুন যোগ করুন", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16)),
      )
      : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildRoughPadTab(roughItems),
          _buildFinalInvoiceTab(billedItems),
        ],
      ),
    );
  }

  Widget _buildRoughPadTab(List<ReceiptItem> roughItems) {
    if (roughItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("প্যাড খালি আছে।\nনতুন কিছু যোগ করুন।", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 20)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(left: 12, right: 12, top: 16, bottom: 90),
      itemCount: roughItems.length,
      itemBuilder: (ctx, idx) {
        var card = roughItems[idx];
        bool isCurrencyState = (card.currentUnit == "Rupees");

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isCurrencyState ? Colors.green.shade400 : Colors.orange.shade300, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(card.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    GestureDetector(
                      onTap: () async {
                        bool confirm = await _confirmAction("ডিলিট করবেন?", "আপনি কি ${card.name} মুছে ফেলতে চান?");
                        if (confirm) {
                          setState(() { _appData.removeWhere((e) => e.id == card.id); });
                          _persistCurrentState();
                        }
                      },
                      child: Icon(Icons.cancel, color: Colors.red.shade400, size: 28),
                    )
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Text("${card.qty} ", style: TextStyle(fontWeight: FontWeight.w900, color: isCurrencyState ? Colors.green.shade700 : Colors.orange.shade800, fontSize: 28)),
                    if (!isCurrencyState)
                      InkWell(
                        onTap: () => _showChangeUnitSheet(card),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Text(card.currentUnit, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontSize: 18)),
                              const SizedBox(width: 4),
                              Icon(Icons.edit, size: 16, color: Colors.orange.shade900)
                            ],
                          ),
                        ),
                      )
                      else
                        Text("₹", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green.shade700, fontSize: 28)),
                  ],
                ),
                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                  child: Text(card.history, style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.grey.shade800, height: 1.5)),
                ),
                const SizedBox(height: 16),

                if (isCurrencyState)
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: () {
                              setState(() {
                                card.qty = card.prePriceQty;
                                card.currentUnit = card.originalUnit;
                              });
                              _persistCurrentState();
                            },
                            child: const Icon(Icons.undo, size: 24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            icon: const Icon(Icons.check_circle_outline, size: 24),
                            label: const Text("ফাইনাল বিলে পাঠান", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            onPressed: () {
                              setState(() { card.status = "billed"; });
                              _persistCurrentState();
                            },
                          ),
                        ),
                      ),
                    ],
                  )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: ['+', '-', '×', '÷'].map((op) {
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade50,
                                foregroundColor: Colors.blue.shade900,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.blue.shade300, width: 2)),
                              ),
                              child: Text(op, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26)),
                              onPressed: () => _showMathSheet(card, op == '×' ? '*' : (op == '÷' ? '/' : op)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFinalInvoiceTab(List<ReceiptItem> billedItems) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.account_balance_wallet),
              label: const Text("অ্যাডভান্স (জমা) টাকা বাদ দিন", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _showAdvanceMoneySheet,
            ),
          ),

          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400, width: 1.5)),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("ফাইনাল বিল (Final Bill)", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                Text(widget.customer.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const Divider(thickness: 2, height: 24, color: Colors.black),

                if (billedItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Text("এখনও কোনো আইটেম যোগ করা হয়নি।", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 18)),
                  )
                  else
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(3.5),
                        1: FlexColumnWidth(1.5),
                        2: IntrinsicColumnWidth(),
                      },
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            decoration: BoxDecoration(color: Colors.grey.shade200),
                            children: [
                              Padding(padding: const EdgeInsets.all(10.0), child: Text("বিবরণ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800, fontSize: 13))),
                              Padding(padding: const EdgeInsets.all(10.0), child: Text("টাকা (₹)", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800, fontSize: 13))),
                              Padding(padding: const EdgeInsets.all(10.0), child: Text("ডিলিট", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800, fontSize: 13))),
                            ]
                          ),
                          ...billedItems.map((bItem) {
                            bool isAdvance = bItem.name == "Advance Paid Deducted" || bItem.name == "পূর্বের বকেয়া (Previous Due)";

                            return TableRow(
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 6.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(bItem.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                                      if (!isAdvance)
                                        Text("${bItem.prePriceQty}${bItem.originalUnit} × ${bItem.rate}", style: const TextStyle(color: Colors.black87, fontSize: 13)),

                                        if (!isAdvance && bItem.history.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(top: 6),
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(6)),
                                            child: Text(bItem.history.trim().replaceAll('\n', ' | '), style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800)),
                                          )
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 6.0),
                                  child: Text(bItem.totalPrice.toStringAsFixed(2), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: isAdvance && bItem.totalPrice < 0 ? Colors.red.shade700 : Colors.green.shade800, fontSize: 15)),
                                ),

                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 24),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  onPressed: () async {
                                    bool confirm = await _confirmAction("বিল থেকে মুছবেন?", "আপনি কি এই আইটেমটি ফাইনাল বিল থেকে মুছে ফেলতে চান?");
                                    if (confirm) {
                                      setState(() {
                                        if (isAdvance) {
                                          _appData.remove(bItem);
                                        } else {
                                          bItem.status = "rough";
                                          bItem.currentUnit = bItem.originalUnit;
                                          bItem.qty = bItem.prePriceQty;
                                          bItem.rate = 0;
                                          bItem.totalPrice = 0;
                                          bItem.history += "\n↩ বিল থেকে ফেরত";
                                        }
                                      });
                                      _persistCurrentState();
                                    }
                                  },
                                )
                              ]
                            );
                          }).toList(),
                        ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(thickness: 2.5, color: Colors.black87),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("মোট বাকি (Total Due):", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text("${_getGrandTotal().toStringAsFixed(2)} টাকা", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.green.shade900)),
                      ],
                    ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (billedItems.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  title: const Text(
                    "গ্রাহককে মোবাইলে মেসেজ (SMS) পাঠান",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  value: _sendSmsOnSave,
                  activeColor: Colors.teal.shade700,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (bool? value) {
                    setState(() {
                      _sendSmsOnSave = value ?? false;
                    });
                  },
                ),
                const SizedBox(height: 8),

                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.cloud_upload, size: 24),
                    label: const Text("সেভ করুন এবং বিল তৈরি করুন", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    onPressed: _exportAndSaveFinalReceipt,
                  ),
                ),
                const SizedBox(height: 16),

                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete_sweep, size: 24),
                  label: const Text("পুরো বিল মুছে ফেলুন", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  onPressed: () async {
                    bool confirm = await _confirmAction("পুরো বিল মুছবেন?", "আপনি কি ফাইনাল বিল থেকে সব আইটেম মুছে ফেলতে চান?");
                    if (confirm) {
                      setState(() {
                        _appData.removeWhere((e) => e.status == "billed");
                      });
                      _persistCurrentState();
                    }
                  },
                )
              ],
            )
        ],
      ),
    );
  }
}
