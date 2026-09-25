/*
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../db_helper.dart';

class ExpensesPage extends StatefulWidget {
  @override
  _ExpensesPageState createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List expenses = [];
  List filteredExpenses = [];
  double totalSpend = 0.0;

  DateTime? startDate;
  DateTime? endDate;

  late stt.SpeechToText speech;

  @override
  void initState() {
    super.initState();
    speech = stt.SpeechToText();

    // ✨ Default Filter: Current Month (1st to Today)
    DateTime now = DateTime.now();
    startDate = DateTime(now.year, now.month, 1);
    endDate = now;

    loadExpenses();
  }

  // 💰 Easy Money Formatter (e.g. 100000 -> 1,00,000)
  String _formatMoney(dynamic amountStr) {
    double amount = double.tryParse(amountStr.toString()) ?? 0.0;
    final formatter = NumberFormat('#,##,##0.##', 'en_IN');
    return formatter.format(amount);
  }

  // 📥 LOAD DATA FROM DATABASE
  loadExpenses() async {
    final data = await DBHelper.getExpenses();
    setState(() {
      expenses = data;
      _applyFilterAndSum();
    });
  }

  // 🔄 FILTER & SUM CALCULATION
  void _applyFilterAndSum() {
    List temp;
    if (startDate == null || endDate == null) {
      temp = List.from(expenses);
    } else {
      temp = expenses.where((e) {
        try {
          DateTime expenseDate = DateFormat('dd-MM-yyyy hh:mm a').parse(e['date']);
          DateTime eDateOnly = DateTime(expenseDate.year, expenseDate.month, expenseDate.day);
          DateTime sDateOnly = DateTime(startDate!.year, startDate!.month, startDate!.day);
          DateTime eEndDateOnly = DateTime(endDate!.year, endDate!.month, endDate!.day);

          return (eDateOnly.isAtSameMomentAs(sDateOnly) || eDateOnly.isAfter(sDateOnly)) &&
          (eDateOnly.isAtSameMomentAs(eEndDateOnly) || eDateOnly.isBefore(eEndDateOnly));
        } catch (_) {
          return true;
        }
      }).toList();
    }

    // 💰 Calculate Total
    double sum = 0;
    for (var e in temp) {
      sum += double.tryParse(e['amount'].toString()) ?? 0.0;
    }

    setState(() {
      filteredExpenses = temp;
      totalSpend = sum;
    });
  }

  void _clearFilter() {
    setState(() {
      startDate = null;
      endDate = null;
    });
    _applyFilterAndSum();
  }

  // 📅 SELECT DATE FOR FILTER
  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (startDate ?? DateTime.now()) : (endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Colors.deepOrange)),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          startDate = picked;
          if (endDate != null && startDate!.isAfter(endDate!)) endDate = null;
        } else {
          endDate = picked;
        }
      });
      _applyFilterAndSum();
    }
  }

  // 🗑️ DELETE WITH WARNING
  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text("Delete Expense?"),
          ],
        ),
        content: const Text("Are you sure you want to delete this expense? This cannot be undone.", style: TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await DBHelper.deleteExpense(id);
              loadExpenses();
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ➕ ADD EXPENSE MODAL
  void _showAddExpenseSheet() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool isListening = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {

          // 🎤 Mic Logic
          void startListening() async {
            bool available = await speech.initialize();
            if (available) {
              setModalState(() => isListening = true);
              speech.listen(
                localeId: "bn_IN", // Bengali Audio
                onResult: (result) {
                  setModalState(() {
                    titleController.text = result.recognizedWords;
                  });
                },
              );
            }
          }

          void stopListening() {
            speech.stop();
            setModalState(() => isListening = false);
          }

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24, right: 24, top: 30,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("নতুন খরচ যোগ করুন", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  const SizedBox(height: 24),

                  // AMOUNT FIELD (Mandatory)
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                    decoration: InputDecoration(
                      labelText: "Amount (₹) * Mandatory",
                      labelStyle: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600),
                      prefixIcon: const Icon(Icons.currency_rupee, color: Colors.deepOrange, size: 28),
                      filled: true, fillColor: const Color(0xfff8fafc),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.deepOrange, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // DATE PICKER (Mandatory)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xfff8fafc),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: const Icon(Icons.calendar_month_rounded, color: Colors.deepOrange),
                      title: Text(DateFormat('dd MMM yyyy').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      subtitle: const Text("Date * Mandatory", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null) setModalState(() => selectedDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // DESCRIPTION FIELD WITH MIC (Optional)
                  TextField(
                    controller: titleController,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      labelText: "Description (Optional)",
                      labelStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                      prefixIcon: const Icon(Icons.edit_note_rounded, color: Colors.blueGrey),
                      suffixIcon: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isListening ? Colors.red.withOpacity(0.1) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isListening ? Icons.mic : Icons.mic_none,
                            color: isListening ? Colors.redAccent : Colors.blueGrey,
                            size: 24,
                          ),
                        ),
                        onPressed: () => isListening ? stopListening() : startListening(),
                      ),
                      filled: true, fillColor: const Color(0xfff8fafc),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.blueGrey, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // SAVE BUTTON
                  ElevatedButton(
                    onPressed: () async {
                      if (amountController.text.trim().isEmpty) return;

                      TimeOfDay now = TimeOfDay.now();
                      DateTime finalDateTime = DateTime(
                        selectedDate.year, selectedDate.month, selectedDate.day, now.hour, now.minute
                      );

                      String formattedDate = DateFormat('dd-MM-yyyy hh:mm a').format(finalDateTime);

                      String finalTitle = titleController.text.trim().isNotEmpty
                      ? titleController.text.trim()
                      : "No Description";

                      await DBHelper.insertExpense({
                        'title': finalTitle,
                        'amount': amountController.text.trim(),
                        'date': formattedDate,
                      });

                      Navigator.pop(context);
                      loadExpenses();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      elevation: 4,
                      shadowColor: Colors.deepOrange.withOpacity(0.4),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    child: const Text("SAVE ENTRY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: AppBar(
        title: const Text("রোজকার খরচ", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22, letterSpacing: 0.5)),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // ✨ APPBAR BUTTON
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
            child: ElevatedButton.icon(
              onPressed: _showAddExpenseSheet,
              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.deepOrange, size: 20),
              label: const Text("New", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 3,
                shadowColor: Colors.black26,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // 💰 TOTAL COMPACT CARD
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF7043), Color(0xFFFF5722)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.deepOrange.withOpacity(0.4), blurRadius: 10, spreadRadius: 1, offset: const Offset(0, 4))
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), shape: BoxShape.circle),
                  child: const Icon(Icons.outbound_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Total Sent", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    // ✨ UPDATED: Easy to read Total formatting
                    Text(
                      "${_formatMoney(totalSpend)} ₹",
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1)
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 📅 FILTER BOX
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(child: _dateBtn(startDate, "Start Date", true)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.grey)),
                Expanded(child: _dateBtn(endDate, "End Date", false)),
                if (startDate != null || endDate != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: IconButton(
                      onPressed: _clearFilter,
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                      ),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),

          // 📋 EXPENSES LIST (COMPACT)
          Expanded(
            child: filteredExpenses.isEmpty
            ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 70, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text("No entries logged yet.", style: TextStyle(color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            )
            : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 20),
              itemCount: filteredExpenses.length,
              itemBuilder: (context, i) {
                final exp = filteredExpenses[i];

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 2,
                  color: Colors.white,
                  shadowColor: Colors.orange.withOpacity(0.1),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.orange.shade50, width: 1.5)
                  ),
                  child: Container(
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/images/card_bg1.png'),
                      fit: BoxFit.cover,
                      opacity: 0.25,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 🔥 LEFTMOST: Up-Arrow Icon
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12)
                          ),
                          child: const Icon(Icons.north_east_rounded, color: Colors.deepOrange, size: 24),
                        ),
                        const SizedBox(width: 12),

                        // 🔥 MIDDLE: Top Amount -> Under Comment -> Under DateTime
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ✨ UPDATED: Amount formatting applied here for individual cards
                              Text(
                                "${_formatMoney(exp['amount'])} ₹",
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.deepOrange, letterSpacing: -0.5)
                              ),
                              const SizedBox(height: 2),

                              // UNDER: Comment (Description)
                              if (exp['title'] != "No Description" && exp['title'].toString().trim().isNotEmpty) ...[
                                Text(
                                  exp['title'],
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155))
                                ),
                                const SizedBox(height: 2),
                              ],

                              // UNDER: Date & Time
                              Row(
                                children: [
                                  Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade400),
                                  const SizedBox(width: 4),
                                  Text(
                                    exp['date'],
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 🔥 RIGHTMOST: Delete Icon
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          ),
                          onPressed: () => _confirmDelete(exp['id']),
                          tooltip: 'Delete Entry',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
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

  // Helper widget for Date filter buttons
  Widget _dateBtn(DateTime? date, String label, bool isStart) {
    return InkWell(
      onTap: () => _selectDate(context, isStart),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: date == null ? Colors.grey.shade300 : Colors.deepOrange.shade200, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, spreadRadius: 1)]
        ),
        child: Text(
          date == null ? label : DateFormat('dd MMM yyyy').format(date),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: date == null ? Colors.grey.shade500 : Colors.deepOrange,
            fontSize: 12
          ),
        ),
      ),
    );
  }
}*/




import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../db_helper.dart';

class ExpensesPage extends StatefulWidget {
  @override
  _ExpensesPageState createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List expenses = [];
  List filteredExpenses = [];
  List<String> keywords = []; // 🔥 Tracks dynamic keywords
  double totalSpend = 0.0;

  DateTime? startDate;
  DateTime? endDate;
  String searchQuery = ''; // 🔥 Tracks active search

  late stt.SpeechToText speech;

  @override
  void initState() {
    super.initState();
    speech = stt.SpeechToText();

    // ✨ Default Filter: Current Month (1st to Today)
    DateTime now = DateTime.now();
    startDate = DateTime(now.year, now.month, 1);
    endDate = now;

    loadExpenses();
  }

  // 📥 LOAD DATA FROM DATABASE (Loads both expenses and keywords)
  Future<void> loadExpenses() async {
    final data = await DBHelper.getExpenses();
    final kws = await DBHelper.getExpenseKeywords();
    setState(() {
      expenses = data;
      keywords = kws;
      _applyFilterAndSum();
    });
  }

  // 💰 Easy Money Formatter (e.g. 100000 -> 1,00,000)
  String _formatMoney(dynamic amountStr) {
    double amount = double.tryParse(amountStr.toString()) ?? 0.0;
    final formatter = NumberFormat('#,##,##0.##', 'en_IN');
    return formatter.format(amount);
  }

  // 🔄 FILTER & SUM CALCULATION (Includes Search!)
  void _applyFilterAndSum() {
    List temp;

    // 1. Apply Date Filter
    if (startDate == null || endDate == null) {
      temp = List.from(expenses);
    } else {
      temp = expenses.where((e) {
        try {
          DateTime expenseDate = DateFormat('dd-MM-yyyy hh:mm a').parse(e['date']);
          DateTime eDateOnly = DateTime(expenseDate.year, expenseDate.month, expenseDate.day);
          DateTime sDateOnly = DateTime(startDate!.year, startDate!.month, startDate!.day);
          DateTime eEndDateOnly = DateTime(endDate!.year, endDate!.month, endDate!.day);

          return (eDateOnly.isAtSameMomentAs(sDateOnly) || eDateOnly.isAfter(sDateOnly)) &&
          (eDateOnly.isAtSameMomentAs(eEndDateOnly) || eDateOnly.isBefore(eEndDateOnly));
        } catch (_) {
          return true;
        }
      }).toList();
    }

    // 2. 🔥 Apply Search Query Filter
    if (searchQuery.isNotEmpty) {
      temp = temp.where((e) {
        String title = e['title'].toString().toLowerCase();
        return title.contains(searchQuery.toLowerCase());
      }).toList();
    }

    // 💰 Calculate Total
    double sum = 0;
    for (var e in temp) {
      sum += double.tryParse(e['amount'].toString()) ?? 0.0;
    }

    setState(() {
      filteredExpenses = temp;
      totalSpend = sum;
    });
  }

  void _clearFilter() {
    setState(() {
      startDate = null;
      endDate = null;
    });
    _applyFilterAndSum();
  }

  void _clearSearch() {
    setState(() {
      searchQuery = '';
    });
    _applyFilterAndSum();
  }

  // 📅 SELECT DATE FOR FILTER
  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (startDate ?? DateTime.now()) : (endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Colors.deepOrange)),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          startDate = picked;
          if (endDate != null && startDate!.isAfter(endDate!)) endDate = null;
        } else {
          endDate = picked;
        }
      });
      _applyFilterAndSum();
    }
  }

  // 🗑️ DELETE EXPENSE
  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text("Delete Expense?"),
          ],
        ),
        content: const Text("Are you sure you want to delete this expense? This cannot be undone.", style: TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await DBHelper.deleteExpense(id);
              loadExpenses();
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 🛠️ CREATE NEW KEYWORD DIALOG
  Future<void> _addKeywordDialog() async {
    TextEditingController kwController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add New Keyword"),
        content: TextField(
          controller: kwController,
          decoration: const InputDecoration(hintText: "Enter keyword (e.g. Travel, Food)"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              if (kwController.text.trim().isNotEmpty) {
                await DBHelper.insertExpenseKeyword(kwController.text.trim());
                Navigator.pop(context);
                loadExpenses(); // Refresh keywords
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text("SAVE", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // 🗑️ DELETE KEYWORD DIALOG
  void _confirmDeleteKeyword(String keyword) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete '$keyword'?"),
        content: const Text("Remove this keyword from your quick selections?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await DBHelper.deleteExpenseKeyword(keyword);
              Navigator.pop(context);
              loadExpenses(); // Refresh keywords
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // 🔍 SEARCH MODAL
  void _showSearchSheet() {
    final searchController = TextEditingController();
    bool isListening = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {

          void startListening() async {
            bool available = await speech.initialize();
            if (available) {
              setModalState(() => isListening = true);
              speech.listen(
                localeId: "bn_IN",
                onResult: (result) {
                  setModalState(() {
                    searchController.text = result.recognizedWords;
                  });
                },
              );
            }
          }

          void stopListening() {
            speech.stop();
            setModalState(() => isListening = false);
          }

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24, right: 24, top: 30,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("খুঁজুন (Search)", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  const SizedBox(height: 20),

                  // SEARCH INPUT WITH MIC
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: "Type or say something...",
                      prefixIcon: const Icon(Icons.search, color: Colors.deepOrange),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isListening ? Icons.mic : Icons.mic_none,
                          color: isListening ? Colors.redAccent : Colors.blueGrey,
                        ),
                        onPressed: () => isListening ? stopListening() : startListening(),
                      ),
                      filled: true, fillColor: const Color(0xfff8fafc),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (val) {
                      setState(() => searchQuery = val.trim());
                      _applyFilterAndSum();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 20),

                  // DYNAMIC KEYWORDS CHIPS
                  const Text("Quick Keywords (Long press to delete)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...keywords.map((kw) => GestureDetector(
                        onLongPress: () {
                          Navigator.pop(context); // Close sheet safely
                          _confirmDeleteKeyword(kw);
                        },
                        child: ActionChip(
                          label: Text(kw, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.deepOrange)),
                          backgroundColor: Colors.deepOrange.withOpacity(0.1),
                          side: BorderSide.none,
                          onPressed: () {
                            setState(() => searchQuery = kw);
                            _applyFilterAndSum();
                            Navigator.pop(context);
                          },
                        ),
                      )),
                       ActionChip(
                         label: const Row(
                           mainAxisSize: MainAxisSize.min,
                           children: [Icon(Icons.add, size: 16), SizedBox(width: 4), Text("New")],
                         ),
                         backgroundColor: Colors.grey.shade200,
                         side: BorderSide.none,
                         onPressed: () {
                           Navigator.pop(context);
                           _addKeywordDialog();
                         },
                       )
                    ],
                  ),
                  const SizedBox(height: 30),

                  // SEARCH BUTTON
                  ElevatedButton(
                    onPressed: () {
                      setState(() => searchQuery = searchController.text.trim());
                      _applyFilterAndSum();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    child: const Text("SEARCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ➕ ADD EXPENSE MODAL
  void _showAddExpenseSheet() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool isListening = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {

          // 🎤 Mic Logic
          void startListening() async {
            bool available = await speech.initialize();
            if (available) {
              setModalState(() => isListening = true);
              speech.listen(
                localeId: "bn_IN",
                onResult: (result) {
                  setModalState(() {
                    titleController.text = result.recognizedWords;
                  });
                },
              );
            }
          }

          void stopListening() {
            speech.stop();
            setModalState(() => isListening = false);
          }

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24, right: 24, top: 30,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("নতুন খরচ যোগ করুন", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  const SizedBox(height: 24),

                  // AMOUNT FIELD (Mandatory)
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                    decoration: InputDecoration(
                      labelText: "Amount (₹) * Mandatory",
                      labelStyle: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600),
                      prefixIcon: const Icon(Icons.currency_rupee, color: Colors.deepOrange, size: 28),
                      filled: true, fillColor: const Color(0xfff8fafc),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.deepOrange, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // DATE PICKER
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xfff8fafc),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: const Icon(Icons.calendar_month_rounded, color: Colors.deepOrange),
                      title: Text(DateFormat('dd MMM yyyy').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      subtitle: const Text("Date * Mandatory", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null) setModalState(() => selectedDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 🔥 DYNAMIC KEYWORDS SELECTION FOR NEW ENTRY
                  if (keywords.isNotEmpty) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: keywords.map((kw) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ActionChip(
                            label: Text(kw, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            backgroundColor: Colors.blueGrey.withOpacity(0.1),
                            side: BorderSide.none,
                            onPressed: () {
                              setModalState(() {
                                // Append text nicely
                                titleController.text = titleController.text.isEmpty
                                ? kw
                                : "${titleController.text} $kw";
                              });
                            },
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // DESCRIPTION FIELD WITH MIC
                  TextField(
                    controller: titleController,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      labelText: "Description (Optional)",
                      labelStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                      prefixIcon: const Icon(Icons.edit_note_rounded, color: Colors.blueGrey),
                      suffixIcon: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isListening ? Colors.red.withOpacity(0.1) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isListening ? Icons.mic : Icons.mic_none,
                            color: isListening ? Colors.redAccent : Colors.blueGrey,
                            size: 24,
                          ),
                        ),
                        onPressed: () => isListening ? stopListening() : startListening(),
                      ),
                      filled: true, fillColor: const Color(0xfff8fafc),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.blueGrey, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // SAVE BUTTON
                  ElevatedButton(
                    onPressed: () async {
                      if (amountController.text.trim().isEmpty) return;

                      TimeOfDay now = TimeOfDay.now();
                      DateTime finalDateTime = DateTime(
                        selectedDate.year, selectedDate.month, selectedDate.day, now.hour, now.minute
                      );

                      String formattedDate = DateFormat('dd-MM-yyyy hh:mm a').format(finalDateTime);

                      String finalTitle = titleController.text.trim().isNotEmpty
                      ? titleController.text.trim()
                      : "No Description";

                      await DBHelper.insertExpense({
                        'title': finalTitle,
                        'amount': amountController.text.trim(),
                        'date': formattedDate,
                      });

                      Navigator.pop(context);
                      loadExpenses(); // 🔥 This forces the UI to refresh with the new data
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      elevation: 4,
                      shadowColor: Colors.deepOrange.withOpacity(0.4),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    child: const Text("SAVE ENTRY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: AppBar(
        title: const Text("রোজকার খরচ", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22, letterSpacing: 0.5)),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // 🔥 SEARCH BUTTON
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.white, size: 26),
            onPressed: _showSearchSheet,
          ),
          // ✨ APPBAR NEW BUTTON
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
            child: ElevatedButton.icon(
              onPressed: _showAddExpenseSheet,
              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.deepOrange, size: 20),
              label: const Text("New", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 3,
                shadowColor: Colors.black26,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // 💰 TOTAL COMPACT CARD
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF7043), Color(0xFFFF5722)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.deepOrange.withOpacity(0.4), blurRadius: 10, spreadRadius: 1, offset: const Offset(0, 4))
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), shape: BoxShape.circle),
                  child: const Icon(Icons.outbound_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Total Sent", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(
                      "${_formatMoney(totalSpend)} ₹",
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1)
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 📅 FILTER BOX
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(child: _dateBtn(startDate, "Start Date", true)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.grey)),
                Expanded(child: _dateBtn(endDate, "End Date", false)),
                if (startDate != null || endDate != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: IconButton(
                      onPressed: _clearFilter,
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                      ),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),

          // 🔥 ACTIVE SEARCH REVERT BANNER
          if (searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.deepOrange.withOpacity(0.3))
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 16, color: Colors.deepOrange),
                          const SizedBox(width: 6),
                          Expanded(child: Text("Searching: '$searchQuery'", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _clearSearch,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text("Revert"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                        backgroundColor: Colors.red.withOpacity(0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                  )
                ],
              ),
            ),

            // 📋 EXPENSES LIST (COMPACT)
            Expanded(
              child: filteredExpenses.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history_rounded, size: 70, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text("No entries found.", style: TextStyle(color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
              : ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 20),
                itemCount: filteredExpenses.length,
                itemBuilder: (context, i) {
                  final exp = filteredExpenses[i];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 2,
                    color: Colors.white,
                    shadowColor: Colors.orange.withOpacity(0.1),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.orange.shade50, width: 1.5)
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('assets/images/card_bg1.png'),
                          fit: BoxFit.cover,
                          opacity: 0.25,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12)
                              ),
                              child: const Icon(Icons.north_east_rounded, color: Colors.deepOrange, size: 24),
                            ),
                            const SizedBox(width: 12),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${_formatMoney(exp['amount'])} ₹",
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.deepOrange, letterSpacing: -0.5)
                                  ),
                                  const SizedBox(height: 2),

                                  if (exp['title'] != "No Description" && exp['title'].toString().trim().isNotEmpty) ...[
                                    Text(
                                      exp['title'],
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155))
                                    ),
                                    const SizedBox(height: 2),
                                  ],

                                  Row(
                                    children: [
                                      Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade400),
                                      const SizedBox(width: 4),
                                      Text(
                                        exp['date'],
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                              ),
                              onPressed: () => _confirmDelete(exp['id']),
                              tooltip: 'Delete Entry',
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
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

  // Helper widget for Date filter buttons
  Widget _dateBtn(DateTime? date, String label, bool isStart) {
    return InkWell(
      onTap: () => _selectDate(context, isStart),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: date == null ? Colors.grey.shade300 : Colors.deepOrange.shade200, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, spreadRadius: 1)]
        ),
        child: Text(
          date == null ? label : DateFormat('dd MMM yyyy').format(date),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: date == null ? Colors.grey.shade500 : Colors.deepOrange,
            fontSize: 12
          ),
        ),
      ),
    );
  }
}
