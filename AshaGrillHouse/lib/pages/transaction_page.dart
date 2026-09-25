import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../utils/sms_helper.dart';
import '../db_helper.dart';
import 'package:intl/intl.dart';

class TransactionPage extends StatefulWidget {
  dynamic customer;

  TransactionPage({required this.customer});

  @override
  _TransactionPageState createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  List<Map<String, dynamic>> transactions = [];

  final amount = TextEditingController();
  final note = TextEditingController();

  DateTime selectedDate = DateTime.now();
  bool sendSMS = true;

  String sortType = "new";

  late stt.SpeechToText speech;
  bool isListening = false;

  @override
  void initState() {
    super.initState();
    speech = stt.SpeechToText();
    load();
  }



  // 💰 Easy Money Formatter (Indian Comma System)
  String _formatMoney(dynamic amountStr) {
    double amount = double.tryParse(amountStr.toString()) ?? 0.0;
    final formatter = NumberFormat('#,##,##0.##', 'en_IN');
    return formatter.format(amount);
  }



  // 🎤 VOICE
  void startListening(TextEditingController controller) async {
    bool available = await speech.initialize();
    if (available) {
      setState(() => isListening = true);
      speech.listen(
        localeId: "bn_IN",
        onResult: (result) {
          setState(() {
            controller.text = result.recognizedWords;
          });
        },
      );
    }
  }

  void stopListening() {
    speech.stop();
    setState(() => isListening = false);
  }

  // 📥 LOAD + SORT
  load() async {
    List<Map<String, dynamic>> rawData = await DBHelper.getTransactions(widget.customer.id);
    transactions = List<Map<String, dynamic>>.from(rawData);

    transactions.sort((a, b) {
      if (sortType == "new") {
        return b['id'].compareTo(a['id']);
      } else if (sortType == "old") {
        return a['id'].compareTo(b['id']);
      } else {
        double amtA = double.tryParse(a['amount'].toString()) ?? 0;
        double amtB = double.tryParse(b['amount'].toString()) ?? 0;

        if (sortType == "high") return amtB.compareTo(amtA);
        if (sortType == "low") return amtA.compareTo(amtB);
        return 0;
      }
    });

    var updatedCustomers = await DBHelper.getCustomers();
    widget.customer = updatedCustomers.firstWhere((e) => e.id == widget.customer.id);

    setState(() {});
  }

  // 📅 DATE
  pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  // ➕ ADD (Advance Payment allowed!)
//   addTransaction() async {
//     double enteredAmount = double.tryParse(amount.text) ?? 0;
//
//     if (enteredAmount <= 0) {
//       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid amount")));
//       return;
//     }
//
//     double currentDue = double.tryParse(widget.customer.due.toString()) ?? 0;
//
//
//     // 🔥 Fixed: Rounded to 2 decimal places right here to prevent database precision glitches
//     double newDue = double.parse((currentDue - enteredAmount).toStringAsFixed(2));
//     final now = DateTime.now();
//
//
//     String dateTime =
//     "${selectedDate.day}-${selectedDate.month}-${selectedDate.year} "
//     "${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? "PM" : "AM"}";
//
//     await DBHelper.insertTransaction(widget.customer.id, amount.text, dateTime, note.text);
//     await DBHelper.updateCustomerDue(widget.customer.id, newDue);
//
//     if (sendSMS) {
//       String phone = widget.customer.phone.toString();
//       if (phone.isNotEmpty && phone.length >= 10) {
//
//         String? status = await DBHelper.getStatus();
//
//         String msg;
//
//         // 2. Check if status is "active"
//         if (status == "active") {
//           // Message for Active Status
//           msg = "Dear ${widget.customer.name}\nPayment Rs. $enteredAmount has received.\nYour ${newDue < 0 ? 'Advance Balance is Rs. ${newDue.abs()}' : 'Remaining Due is Rs. $newDue'}\n\n- Asha Grill House\nView details: https://ashagrillhouse.github.io/site/receipt.html?q=${phone.replaceAll(RegExp(r'\D'), '').substring(phone.replaceAll(RegExp(r'\D'), '').length - 10)}";
//         }
//         else {
//           // 3. Message for Inactive or any other status
//           msg = "Dear ${widget.customer.name}\nPayment Rs. $enteredAmount has received.\nYour ${newDue < 0 ? 'Advance Balance is Rs. ${newDue.abs()}' : 'Remaining Due is Rs. $newDue'}\n\n- Asha Grill House";
//         }
//
//         await SmsHelper.sendSMS(phone: phone, message: msg);
//
//         String now =
//         "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year} "
//         "${DateTime.now().hour}:${DateTime.now().minute}";
//
//         await DBHelper.insertMessage(widget.customer.id,msg,now);
//       }
//     }
//
//     amount.clear();
//     note.clear();
//     load();
//   }


  // ➕ ADD (Advance Payment allowed!)
  addTransaction() async {
    double enteredAmount = double.tryParse(amount.text) ?? 0;

    if (enteredAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid amount")));
      return;
    }

    double currentDue = double.tryParse(widget.customer.due.toString()) ?? 0;

    // 🔥 Fixed: Rounded to 2 decimal places right here to prevent database precision glitches
    double newDue = double.parse((currentDue - enteredAmount).toStringAsFixed(2));
    final now = DateTime.now();

    String dateTime =
    "${selectedDate.day}-${selectedDate.month}-${selectedDate.year} "
    "${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? "PM" : "AM"}";

    await DBHelper.insertTransaction(widget.customer.id, amount.text, dateTime, note.text);
    await DBHelper.updateCustomerDue(widget.customer.id, newDue);

    if (sendSMS) {
      String phone = widget.customer.phone.toString();
      if (phone.isNotEmpty && phone.length >= 10) {

        String? status = await DBHelper.getStatus();

        String msg;

        // 🔥 Fixed: Pre-format clean strings with exactly 2 decimal places for the text message
        String cleanEntered = enteredAmount.toStringAsFixed(2);
        String cleanDue = newDue.toStringAsFixed(2);
        String cleanAdvance = newDue.abs().toStringAsFixed(2);

        // 2. Check if status is "active"
        if (status == "active") {
          // Message for Active Status
          msg = "Dear ${widget.customer.name}\nPayment Rs. $cleanEntered has received.\nYour ${newDue < 0 ? 'Advance Balance is Rs. $cleanAdvance' : 'Remaining Due is Rs. $cleanDue'}\n\n- Asha Grill House\nView details: https://ashagrillhouse.github.io/site/receipt.html?q=${phone.replaceAll(RegExp(r'\D'), '').substring(phone.replaceAll(RegExp(r'\D'), '').length - 10)}";
        }
        else {
          // 3. Message for Inactive or any other status
          msg = "Dear ${widget.customer.name}\nPayment Rs. $cleanEntered has received.\nYour ${newDue < 0 ? 'Advance Balance is Rs. $cleanAdvance' : 'Remaining Due is Rs. $cleanDue'}\n\n- Asha Grill House";
        }

        await SmsHelper.sendSMS(phone: phone, message: msg);

        String nowStr =
        "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year} "
        "${DateTime.now().hour}:${DateTime.now().minute}";

          await DBHelper.insertMessage(widget.customer.id, msg, nowStr);
      }
    }

    amount.clear();
    note.clear();
    load();
  }










  // ❌ DELETE
  deleteTx(int id, String amountValue) async {
    double deletedAmount = double.tryParse(amountValue) ?? 0;
    double currentDue = double.tryParse(widget.customer.due) ?? 0;
    double newDue = currentDue + deletedAmount;

    await DBHelper.deleteTransaction(id);
    await DBHelper.updateCustomerDue(widget.customer.id, newDue);

    load();
  }

  // 🔥 BOTTOM SHEET
  void openAddSheet() {
    amount.clear();
    note.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 50, height: 5,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const Text("ইনি টাকা জমা দিয়েছেন", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 20),

                    // 💰 AMOUNT
                    TextField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        prefixText: "₹ ",
                        prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black54),
                        hintText: "0.00",
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                              // 📝 NOTE
                              Container(
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                                child: TextField(
                                  controller: note,
                                  maxLines: 2,
                                  style: const TextStyle(color: Colors.black87),
                                  decoration: InputDecoration(
                                    hintText: "Add Note (optional)",
                                    hintStyle: const TextStyle(color: Colors.black38),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.all(16),
                                    suffixIcon: IconButton(
                                      icon: Icon(isListening ? Icons.mic : Icons.mic_none, color: isListening ? Colors.red : Colors.grey),
                                      onPressed: () async {
                                        if (isListening) {
                                          stopListening();
                                          setModalState(() {});
                                        } else {
                                          bool available = await speech.initialize();
                                          if (available) {
                                            setModalState(() => isListening = true);
                                            speech.listen(
                                              localeId: "bn_IN",
                                              onResult: (result) {
                                                setModalState(() { note.text = result.recognizedWords; });
                                              },
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 📅 DATE & SMS TOGGLE
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton.icon(
                                    onPressed: () async {
                                      await pickDate();
                                      setModalState(() {});
                                    },
                                    icon: const Icon(Icons.calendar_month, color: Colors.red),
                                    label: Text(
                                      "${selectedDate.day}-${selectedDate.month}-${selectedDate.year}",
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    style: TextButton.styleFrom(
                                      backgroundColor: Colors.red.shade50,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: sendSMS,
                                        activeColor: Colors.red,
                                        onChanged: (v) => setModalState(() => sendSMS = v!),
                                      ),
                                      const Text("Send SMS", style: TextStyle(fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // 🟢 SUBMIT BUTTON
                              SizedBox(
                                width: double.infinity,
                                height: 55,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    await addTransaction();
                                    Navigator.pop(context);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      elevation: 0,
                                  ),
                                  child: const Text("Save Payment", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (isListening) stopListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    var c = widget.customer;
    double currentDue = double.tryParse(c.due.toString()) ?? 0;
    bool isAdvance = currentDue < 0; // Check if it's an advance

    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: AppBar(
        title: const Text("খদ্দেরের টাকা জমা", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
          elevation: 0,
          actions: [
            // 🔥 NEW: Fixed prominent button in the app bar! Easy to see, never hides.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: ElevatedButton.icon(
                onPressed: openAddSheet,
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
                label: const Text("Pay", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, // Bright red to catch attention
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: Colors.black87),
              onSelected: (value) {
                sortType = value;
                load();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: "new", child: Text("Newest First")),
                const PopupMenuItem(value: "old", child: Text("Oldest First")),
                const PopupMenuItem(value: "high", child: Text("Amount High → Low")),
                const PopupMenuItem(value: "low", child: Text("Amount Low → High")),
              ],
            )
          ],
      ),
      body: Column(
        children: [
          // 🔥 CUSTOMER CARD (Updated to handle Advance)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isAdvance
                ? [Colors.green.shade400, Colors.green.shade600] // Green if advance
                : [const Color(0xFFE53935), const Color(0xFFEF5350)], // Red if due
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (isAdvance ? Colors.green : Colors.red).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(isAdvance ? "Advance Paid" : "Due Amount", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                    ],
                  ),
                ),
                // Text(
                //   isAdvance ? "+ ${currentDue.abs().toStringAsFixed(0)} ₹" : "${c.due} ₹",
                //   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)
                // ),
                Text(
                  isAdvance ? "+ ${_formatMoney(currentDue.abs())} ₹" : "${_formatMoney(c.due)} ₹",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)
                ),
              ],
            ),
          ),

          // 📊 TRANSACTION LIST
          Expanded(
            child: transactions.isEmpty
            ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text("No transactions yet", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
              ],
            )
            : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), // Removed large bottom padding since no floating button
              itemCount: transactions.length,
              itemBuilder: (_, i) {
                var t = transactions[i];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_downward, color: Colors.green, size: 20),
                    ),
                    // title: Text(
                    //   "${t['amount']} ₹",
                    //   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                    // ),
                    title: Text(
                      "${_formatMoney(t['amount'])} ₹",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(t['date'], style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        if (t['note'] != null && t['note'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text("Note: ${t['note']}", style: const TextStyle(color: Colors.black54, fontStyle: FontStyle.italic, fontSize: 13)),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _showDeleteConfirm(t['id'], t['amount'].toString()),
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

  void _showDeleteConfirm(int id, String amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Transaction?"),
        // content: Text("Are you sure you want to delete this payment of $amount ₹ ? This will add the amount back to the due balance."),
        content: Text("Are you sure you want to delete this payment of ${_formatMoney(amount)} ₹ ? This will add the amount back to the due balance."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.black54))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              deleteTx(id, amount);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    speech.stop();
    super.dispose();
  }
}
