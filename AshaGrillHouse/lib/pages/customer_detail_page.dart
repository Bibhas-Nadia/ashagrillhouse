
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'transaction_page.dart';
import '../db_helper.dart';
import '../models/customer.dart';
import '../utils/sms_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:call_log/call_log.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import "customer_receipt_page.dart";

class CustomerDetailPage extends StatefulWidget {
  final Customer c;

  CustomerDetailPage({required this.c});

  @override
  _CustomerDetailPageState createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  List<String> imgs = [];
  final ImagePicker _picker = ImagePicker();
  bool _hasModifiedData = false;
  double _totalPaid = 0.0;
  List<Map<String, dynamic>> _messages = []; // To store message history
  bool _isPinned = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _refreshCustomerData();
  }

  String _formatMoney(double amount) {
    final formatter = NumberFormat('#,##,##0.##', 'en_IN'); // Indian Comma System
    return formatter.format(amount);
  }





  // ==========================================================
  // SAVE AND DELETE CONTACTS LOGIC (WITH WARNINGS)
  // ==========================================================

  Future<void> _saveToPhoneContacts() async {
    if (widget.c.phone.isEmpty) return;

    // 🛑 CONFIRMATION DIALOG WITH OVERWRITE WARNING
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Text("Save Contact?"),
          ],
        ),
        content: Text("আপনি কি ${widget.c.name} সংরক্ষণ করতে নিশ্চিত?\n\n⚠️ সতর্কীকরণ: যদি এই নম্বরটি ইতিমধ্যেই অন্য কোনো নামে সংরক্ষিত থাকে, তাহলে এটি আপনার ডিভাইসে পূর্ববর্তী নম্বরটিকে ওভাররাইট করবে অথবা একটি ডুপ্লিকেট কন্ট্যাক্ট তৈরি করবে।"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("SAVE"),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    if (await FlutterContacts.requestPermission()) {
      try {
        final newContact = Contact()
        ..name.first = widget.c.name
        ..phones = [Phone(widget.c.phone)];

        await newContact.insert();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${widget.c.name} saved to phone contacts!"), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to save: $e")));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Contacts permission denied")));
    }
  }

  Future<void> _deleteFromPhoneContacts() async {
    if (widget.c.phone.isEmpty) return;

    // 🛑 CONFIRMATION DIALOG WITH DELETION WARNING
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text("Delete Contact?"),
          ],
        ),
        content: Text("⚠️ সতর্কীকরণ: এটি আপনার ফোনের স্টোরেজ ডিরেক্টরি থেকে '${widget.c.name}'-এর জন্য সংরক্ষিত সংশ্লিষ্ট কন্ট্যাক্টটি স্থায়ীভাবে মুছে ফেলবে।"),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("DELETE"),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    if (await FlutterContacts.requestPermission()) {
      try {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        String targetPhone = widget.c.phone.replaceAll(RegExp(r'\D'), '');

        Contact? contactToDelete;
        for (var contact in contacts) {
          for (var phone in contact.phones) {
            if (phone.number.replaceAll(RegExp(r'\D'), '').endsWith(targetPhone)) {
              contactToDelete = contact;
              break;
            }
          }
          if (contactToDelete != null) break;
        }

        if (contactToDelete != null) {
          await contactToDelete.delete();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${widget.c.name} deleted from phone!"), backgroundColor: Colors.redAccent),
            );
          }
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Contact not found in phone")));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
      }
    }
  }









  // ==========================================================
  // 📤 SHARE CUSTOMER PROFILE DETAILS & TRANSACTIONS WITH IMAGES
  // ==========================================================
  Future<void> _shareCustomerDetails() async {
    try {
      // Fetch latest transactions for this customer from database
      final transactions = await DBHelper.getTransactions(widget.c.id!);

      // Construct professional, easy-to-read text summary
      StringBuffer sb = StringBuffer();
      sb.writeln("Dear ${widget.c.name}");

      // // Handle optional contact/address info dynamically
      // List<String> contactInfo = [];
      // if (widget.c.address.trim().isNotEmpty) {
      //   contactInfo.add("📍 ${widget.c.address.trim()}");
      // }
      // if (widget.c.phone.trim().isNotEmpty) {
      //   contactInfo.add("📞 ${widget.c.phone.trim()}");
      // }
      // if (contactInfo.isNotEmpty) {
      //   sb.writeln(contactInfo.join(", "));
      // }
      sb.writeln(); // Add line gap

      // Skip transaction details section completely if there are no records
      if (transactions.isNotEmpty && _totalPaid > 0) {
        sb.writeln("✅ You already paid Rs. ${_totalPaid.toStringAsFixed(2)} on");
        for (var t in transactions) {
          String date = t['date'] ?? '';
          String amount = t['amount']?.toString() ?? '0';
          sb.writeln("date: $date : Rs. $amount");
        }
        sb.writeln(); // Add line gap
      }

      double actualDue = double.tryParse(widget.c.due) ?? 0;
      double displayDue = actualDue < 0 ? 0.0 : actualDue;
      sb.writeln("💰 Your current due is : Rs. ${displayDue.toStringAsFixed(2)}");
      sb.writeln();

      sb.writeln("Pay your due online amount on upi id: ashagrillhouse@upi For any queries contact us.");
      sb.writeln("-- Asha Grill House");

      String shareMessageText = sb.toString();

      // Collect any valid active attached image files
      List<XFile> xFilesToShare = [];
      for (String imgPath in imgs) {
        if (imgPath.trim().isNotEmpty) {
          File physicalFile = File(imgPath.trim());
          if (await physicalFile.exists()) {
            xFilesToShare.add(XFile(imgPath.trim()));
          }
        }
      }

      // 🛠️ NEW LOGIC: Send text and images together automatically
      if (xFilesToShare.isNotEmpty) {
        // This will send the text and images directly.
        // Note: WhatsApp might duplicate this text as a caption on every image.
        await Share.shareXFiles(xFilesToShare, text: shareMessageText);
      } else {
        // No images, just share the text
        await Share.share(shareMessageText);
      }

    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error generating share card: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }






  void _loadImages() {
    imgs = widget.c.images.split(",").where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> _refreshCustomerData() async {
    if (widget.c.id == null) return;

    try {
      final transactions = await DBHelper.getTransactions(widget.c.id!);
      double total = 0.0;

      for (var t in transactions) {
        double? amount = double.tryParse(t['amount'].toString());
        if (amount != null) {
          total += amount;
        }
      }

      final allCustomers = await DBHelper.getCustomers();
      final updatedCustomer = allCustomers.firstWhere((cust) => cust.id == widget.c.id);


      // NEW: Fetch messages for this customer
      final messageHistory = await DBHelper.getMessages(widget.c.id!);

      // NEW: Check if this customer is pinned
      final pinned = await DBHelper.isCustomerPinned(widget.c.id!);

      setState(() {
        _totalPaid = total;
        widget.c.due = updatedCustomer.due;
        _messages = messageHistory; // Update the list
        _isPinned = pinned; // Update pin status
      });


    } catch (e) {
      debugPrint("Error refreshing customer data: $e");
    }
  }





  Future<void> _togglePin() async {
    if (_isPinned) {
      await DBHelper.unpinCustomer(widget.c.id!);
      setState(() => _isPinned = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Customer unpinned.")));
    } else {
      // Check limit before asking confirmation
      int count = await DBHelper.getPinCount();
      if (count >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Maximum 3 customers can be pinned!"),
          backgroundColor: Colors.redAccent,
        ));
        return;
      }

      bool confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Pin Customer?"),
          content: const Text("This customer will be pinned to the top of your list."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("CONFIRM PIN", style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
      ) ?? false;

      if (confirm) {
        await DBHelper.pinCustomer(widget.c.id!);
        setState(() => _isPinned = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Customer pinned successfully!")));
      }
    }
  }



  // 📞 FETCH RECENT CALLS (For Edit Profile Bottom Sheet)
  Future<void> _showRecentCalls(BuildContext sheetContext, TextEditingController phoneController) async {
    PermissionStatus status = await Permission.phone.request();

    if (status.isGranted) {
      Iterable<CallLogEntry> entries = await CallLog.get();

      if (!sheetContext.mounted) return;

      showModalBottomSheet(
        context: sheetContext,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Recent Calls",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length > 20 ? 20 : entries.length,
                    itemBuilder: (context, index) {
                      CallLogEntry entry = entries.elementAt(index);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepOrange.shade100,
                          child: const Icon(Icons.phone, color: Colors.deepOrange),
                        ),
                        title: Text(entry.name ?? "Unknown"),
                        subtitle: Text(entry.number ?? ""),
                        onTap: () {
                          if (entry.number != null) {
                            String cleanNumber = entry.number!.replaceAll(RegExp(r'\D'), '');
                            if (cleanNumber.length > 10) {
                              cleanNumber = cleanNumber.substring(cleanNumber.length - 10);
                            }

                            // Instantly update the text field
                            phoneController.text = cleanNumber;
                          }
                          Navigator.pop(context); // Close the call log list
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Call log permission denied", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        )
      );
    }
  }




  Future<void> _updateImagesInDB() async {
    String newImageString = imgs.join(",");
    await DBHelper.updateCustomerImages(widget.c.id!, newImageString);
    setState(() {
      widget.c.images = newImageString;
      _hasModifiedData = true;
    });
  }

  void _showEditCustomerBottomSheet() {
    final TextEditingController nameCtrl = TextEditingController(text: widget.c.name);
    final TextEditingController phoneCtrl = TextEditingController(text: widget.c.phone);
    final TextEditingController addressCtrl = TextEditingController(text: widget.c.address);

    stt.SpeechToText speech = stt.SpeechToText();
    bool isListeningName = false;
    bool isListeningAddress = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            void listenToSpeech(TextEditingController controller, String field) async {
              bool isCurrentlyListening = field == 'name' ? isListeningName : isListeningAddress;

              if (!isCurrentlyListening) {
                bool available = await speech.initialize(
                  onError: (val) => print('Error: $val'),
                  onStatus: (val) => print('Status: $val'),
                );

                if (available) {
                  setModalState(() {
                    if (field == 'name') isListeningName = true;
                    if (field == 'address') isListeningAddress = true;
                  });
                    // 🔥 CHANGED: Added localeId to ensure it listens in Bengali
                    speech.listen(
                      localeId: "bn_IN",
                      onResult: (val) {
                        setModalState(() {
                          controller.text = val.recognizedWords;
                        });
                      }
                    );
                }
              } else {
                setModalState(() {
                  if (field == 'name') isListeningName = false;
                  if (field == 'address') isListeningAddress = false;
                });
                  speech.stop();
              }
            }

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20, right: 20, top: 16
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [





                    Container(
                      width: 50, height: 5,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                    ),
                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Icon(Icons.edit_note_rounded, color: Colors.blue, size: 28),
                        SizedBox(width: 10),
                        Text("Edit Profile", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),







                    const SizedBox(height: 24),


                    // _buildStyledTextField(
                    //   nameCtrl, "Customer Name", Icons.person_outline,
                    //   hasMic: true,
                    //   isListening: isListeningName,
                    //   onMicTap: () => listenToSpeech(nameCtrl, 'name'),
                    // ),
                    // const SizedBox(height: 16),
                    //
                    // _buildStyledTextField(phoneCtrl, "Phone Number", Icons.phone_outlined, isPhone: true),
                    //
                    // const SizedBox(height: 16),
                    //
                    // _buildStyledTextField(
                    //   addressCtrl, "Address", Icons.location_on_outlined,
                    //   hasMic: true,
                    //   isListening: isListeningAddress,
                    //   onMicTap: () => listenToSpeech(addressCtrl, 'address'),
                    // ),

                    _buildStyledTextField(
                      nameCtrl, "Customer Name", Icons.person_outline,
                      hasMic: true,
                      isListening: isListeningName,
                      onMicTap: () => listenToSpeech(nameCtrl, 'name'),
                    ),
                    const SizedBox(height: 16),

                    // 🔥 UPDATED PHONE TEXT FIELD
                    _buildStyledTextField(
                      phoneCtrl, "Phone Number", Icons.phone_outlined,
                      isPhone: true,
                      hasCallLog: true,
                      onCallLogTap: () => _showRecentCalls(context, phoneCtrl), // Pass the inner context
                    ),
                    // 🔥 END OF UPDATE

                    const SizedBox(height: 16),
                    _buildStyledTextField(
                      addressCtrl, "Address", Icons.location_on_outlined,
                      hasMic: true,
                      isListening: isListeningAddress,
                      onMicTap: () => listenToSpeech(addressCtrl, 'address'),
                    ),

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                        ),
                        onPressed: () async {
                          String newName = nameCtrl.text.trim();
                          String newPhone = phoneCtrl.text.trim();
                          String newAddress = addressCtrl.text.trim();

                          if (newName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name cannot be empty!")));
                            return;
                          }

                          if (newName == widget.c.name && newPhone == widget.c.phone && newAddress == widget.c.address) {
                            Navigator.pop(context);
                            return;
                          }

                          bool exists = await DBHelper.customerExists(newName, newPhone, newAddress);
                          if (exists) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text("A customer with these exact details already exists!"),
                                backgroundColor: Colors.redAccent,
                              ));
                            }
                            return;
                          }

                          await DBHelper.updateCustomerDetails(widget.c.id!, newName, newPhone, newAddress);

                          setState(() {
                            widget.c.name = newName;
                            widget.c.phone = newPhone;
                            widget.c.address = newAddress;
                            _hasModifiedData = true;
                          });

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text("Customer updated successfully!"),
                              backgroundColor: Colors.green,
                            ));
                          }
                        },
                        child: const Text("SAVE CHANGES", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          }
        );
      },
    ).whenComplete(() {
      speech.stop();
    });
  }

  // ==========================================================
  // 💰 UPDATE DUE AMOUNT BOTTOM SHEET
  // ==========================================================
  void _showUpdateDueBottomSheet() {
    final TextEditingController dueCtrl = TextEditingController();
    bool sendSMS = widget.c.phone.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
        builder: (context, setModalState) {
          double actualDue = double.tryParse(widget.c.due) ?? 0;
          double displayDue = actualDue < 0 ? 0.0 : actualDue;

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20, right: 20, top: 16
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 50, height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      Icon(Icons.currency_rupee_rounded, color: Colors.orange, size: 28),
                      SizedBox(width: 10),
                      Text("Update Due Amount", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Show current due visually
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("বর্তমানে পাবেন", style: TextStyle(fontSize: 16, color: Colors.orange.shade900)),
                        // Text(
                        //   "${displayDue.toStringAsFixed(2)} ₹",
                        //   style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade900)
                        // ),
                        Text(
                          "${_formatMoney(displayDue)} ₹",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade900)
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  _buildStyledTextField(dueCtrl, "এখন এনার কাছে পাবেন", Icons.edit_note_rounded, isNumeric: true),
                  const SizedBox(height: 16),

                  // Send SMS Checkbox
                  if (widget.c.phone.isNotEmpty)
                    Row(
                      children: [
                        Checkbox(
                          value: sendSMS,
                          activeColor: Colors.orange.shade600,
                          onChanged: (v) => setModalState(() => sendSMS = v ?? false),
                        ),
                        const Text("Send SMS Notification", style: TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                        ),
                        onPressed: () async {
                          if (dueCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a new due amount.")));
                            return;
                          }

                          double? newAmount = double.tryParse(dueCtrl.text);
                          if (newAmount == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid number format.")));
                            return;
                          }

                          // Ask for confirmation
                          bool confirm = await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: const Text("Confirm Update"),
                              content: Text("Are you sure you want to change the due amount to $newAmount ₹ ?"),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade600,
                                    foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("UPDATE"),
                                ),
                              ],
                            ),
                          ) ?? false;

                          if (confirm) {
                            await DBHelper.updateCustomerDue(widget.c.id!, newAmount);

                            // Send SMS if checked
                            if (sendSMS && widget.c.phone.isNotEmpty) {

                              String? status = await DBHelper.getStatus();

                              String msg;

                              // 2. Check if status is "active"
                              if (status == "active") {
                                // Message for Active Status
                                msg = "Dear ${widget.c.name}\nYour due amount has been updated.\nNew Due Balance is Rs. $newAmount\n\n- Asha Grill House\nView details: https://ashagrillhouse.github.io/site/receipt.html?q=${widget.c.phone.replaceAll(RegExp(r'\D'), '').substring(widget.c.phone.replaceAll(RegExp(r'\D'), '').length - 10)}";
                              }
                              else {
                                // 3. Message for Inactive or any other status
                                msg = "Dear ${widget.c.name}\nYour due amount has been updated.\nNew Due Balance is Rs. $newAmount\n\n- Asha Grill House";
                              }


                              await SmsHelper.sendSMS(phone: widget.c.phone, message: msg);

                              String now =
                              "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year} "
                              "${DateTime.now().hour}:${DateTime.now().minute}";

                              if (widget.c.id != null) {
                                await DBHelper.insertMessage(widget.c.id!, msg, now);
                              } else {
                                print("Error: Customer ID is missing!");
                              }

                            }

                            setState(() {
                              widget.c.due = newAmount.toStringAsFixed(2);
                              _hasModifiedData = true;
                            });

                            if (context.mounted) {
                              Navigator.pop(context); // Close bottom sheet
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Due amount updated!"), backgroundColor: Colors.green)
                              );
                            }
                          }
                        },
                        child: const Text("SAVE NEW AMOUNT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      ),
                    ),
                    const SizedBox(height: 30),
                ],
              ),
            ),
          );
        }
        );
      },
    );
  }

  // Widget _buildStyledTextField(
  //   TextEditingController controller,
  //   String label,
  //   IconData icon,
  //   {bool isPhone = false, bool isNumeric = false, bool hasMic = false, bool isListening = false, VoidCallback? onMicTap}
  // ) {
  //   return TextField(
  //     controller: controller,
  //     keyboardType: isNumeric ? TextInputType.number : (isPhone ? TextInputType.phone : TextInputType.text),
  //     decoration: InputDecoration(
  //       labelText: label,
  //       prefixIcon: Icon(icon, color: Colors.grey.shade600),
  //       suffixIcon: hasMic
  //       ? IconButton(
  //         icon: Icon(isListening ? Icons.mic : Icons.mic_none_rounded),
  //         color: isListening ? Colors.red : Colors.blue,
  //         onPressed: onMicTap,
  //       )
  //       : null,
  //       filled: true,
  //       fillColor: Colors.grey.shade50,
  //       enabledBorder: OutlineInputBorder(
  //         borderRadius: BorderRadius.circular(16),
  //         borderSide: BorderSide(color: Colors.grey.shade300),
  //       ),
  //       focusedBorder: OutlineInputBorder(
  //         borderRadius: BorderRadius.circular(16),
  //         borderSide: const BorderSide(color: Colors.blue, width: 2),
  //       ),
  //     ),
  //   );
  // }


  Widget _buildStyledTextField(
    TextEditingController controller,
    String label,
    IconData icon,
    // 🔥 NEW PARAMETERS ADDED HERE:
    {bool isPhone = false, bool isNumeric = false, bool hasMic = false, bool isListening = false, VoidCallback? onMicTap, bool hasCallLog = false, VoidCallback? onCallLogTap}
  ) {
    return TextField(
      controller: controller,
      keyboardType: isNumeric ? TextInputType.number : (isPhone ? TextInputType.phone : TextInputType.text),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey.shade600),

        // 🔥 UPDATED SUFFIX ICON LOGIC:
        suffixIcon: hasMic
        ? IconButton(
          icon: Icon(isListening ? Icons.mic : Icons.mic_none_rounded),
          color: isListening ? Colors.red : Colors.blue,
          onPressed: onMicTap,
        )
        : hasCallLog
        ? IconButton(
          icon: const Icon(Icons.history_rounded, color: Colors.deepOrange),
          tooltip: "Fetch from call log",
          onPressed: onCallLogTap,
        )
        : null,

        filled: true,
        fillColor: Colors.grey.shade50,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
      ),
    );
  }



  Future<String> _getDir() async {
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }

    String? sdCardRootPath;
    String internalRootPath = '/storage/emulated/0';

    try {
      final List<Directory>? extDirs = await getExternalStorageDirectories();
      if (extDirs != null && extDirs.length > 1) {
        String appSpecificSdPath = extDirs[1].path;
        int androidIndex = appSpecificSdPath.indexOf('/Android/');
        if (androidIndex != -1) {
          sdCardRootPath = appSpecificSdPath.substring(0, androidIndex);
        }
      }
    } catch (e) {
      print("❌ Error finding SD card directories: $e");
    }

    Directory targetFolder;

    if (sdCardRootPath != null) {
      targetFolder = Directory("$sdCardRootPath/Pictures/.AshaGrillHouse/customers");
      try {
        if (!await targetFolder.exists()) {
          await targetFolder.create(recursive: true);
        }
        return targetFolder.path;
      } catch (e) {
        print("⚠️ OS Blocked SD Card 'Pictures' access: $e");
      }
    }

    targetFolder = Directory("$internalRootPath/Pictures/.AshaGrillHouse/customers");
    try {
      if (!await targetFolder.exists()) {
        await targetFolder.create(recursive: true);
      }
    } catch (e) {
      print("❌ CRITICAL ERROR creating folder in Internal Storage: $e");
    }

    return targetFolder.path;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 1080,
        maxHeight: 1080,
      );

      if (image != null) {
        String permanentDirPath = await _getDir();
        String uniqueFileName = "CUST_${widget.c.id}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        String permanentFilePath = "$permanentDirPath/$uniqueFileName";

        File cachedImage = File(image.path);
        await cachedImage.copy(permanentFilePath);

        setState(() => imgs.add(permanentFilePath));
        await _updateImagesInDB();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Image saved successfully")));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to pick/save image: $e")));
      }
    }
  }

  Future<void> _deleteImage(int index) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Image?"),
        content: const Text("Are you sure you want to remove this image?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("DELETE", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      String pathToRemove = imgs[index];
      setState(() => imgs.removeAt(index));
      await _updateImagesInDB();

      try {
        final file = File(pathToRemove);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("Error deleting file: $e");
      }
    }
  }

  Future<void> _deleteCustomer(BuildContext context) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Delete Customer?"),
          ],
        ),
        content: Text("Are you sure you want to delete ${widget.c.name}? This will permanently remove all their details, images, and transaction history."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL", style: TextStyle(color: Colors.black54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("DELETE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    ) ?? false;

    // if (confirm) {
    //   for (String path in imgs) {
    //     if (path.isNotEmpty) {
    //       final file = File(path.trim());
    //       if (await file.exists()) await file.delete();
    //     }
    //   }
    //
    //   //second unpin if already pined
    //   if (_isPinned) {
    //     await DBHelper.unpinCustomer(widget.c.id!);
    //     setState(() => _isPinned = false);
    //     //ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Customer unpinned.")));
    //   }
    //
    //   await DBHelper.deleteCustomerCompletely(widget.c.id!);
    //
    //   if (context.mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${widget.c.name} deleted successfully.")));
    //     Navigator.pop(context, true);
    //   }
    // }



    if (confirm) {
      // ✅ This successfully deletes all physical images from device storage
      for (String path in imgs) {
        if (path.isNotEmpty) {
          final file = File(path.trim());
          if (await file.exists()) await file.delete();
        }
      }

      // Unpin locally for UI state
      if (_isPinned) {
        await DBHelper.unpinCustomer(widget.c.id!);
        setState(() => _isPinned = false);
      }

      // ✅ This now triggers the updated global DB cleanup
      await DBHelper.deleteCustomerCompletely(widget.c.id!);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${widget.c.name} deleted successfully.")));
        Navigator.pop(context, true);
      }
    }




  }





  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("Add Photo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text("Take a Picture"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.purple),
              title: const Text("Choose from Gallery"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double actualDue = double.tryParse(widget.c.due) ?? 0;
    double displayDue = actualDue < 0 ? 0.0 : actualDue;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasModifiedData);
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xfff4f6fb),
        // appBar: AppBar(
        //   title: const Text("খদ্দেরের বিস্তারিত", style: TextStyle(fontWeight: FontWeight.w600)),
        //   backgroundColor: Colors.white,
        //   foregroundColor: Colors.black87,
        //     elevation: 0,
        //     actions: [
        //       IconButton(
        //         icon: Icon(
        //           _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        //           color: _isPinned ? Colors.blue : Colors.grey
        //         ),
        //         tooltip: "Pin Customer",
        //         onPressed: _togglePin,
        //       ),
        //       IconButton(
        //         icon: const Icon(Icons.delete_outline, color: Colors.red),
        //         tooltip: "Delete Customer",
        //         onPressed: () => _deleteCustomer(context),
        //       )
        //     ],
        // ),
        appBar: AppBar(
          title: const Text("খদ্দেরের বিস্তারিত", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
            elevation: 0.5,
            actions: [
              // 📌 PIN BUTTON (Light Green when active)
              IconButton(
                onPressed: _togglePin,
                icon: Icon(
                  _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _isPinned ? Colors.lightGreen : Colors.grey.shade400,
                  size: 26,
                ),
                tooltip: _isPinned ? "Unpin" : "Pin",
              ),

              // Spacing between buttons
              const SizedBox(width: 4),

              // 🗑️ DELETE BUTTON (Red and spaced from the edge)
              IconButton(
                onPressed: () => _deleteCustomer(context),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 26),
                tooltip: "Delete",
              ),

              // Padding to keep it away from the very right edge
              const SizedBox(width: 12),
            ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔥 TOP CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade400, Colors.red.shade300],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.person, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.c.name,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          // const SizedBox(height: 4),
                          // const Text("Customer Profile", style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),




                    // Container(
                    //   decoration: BoxDecoration(
                    //     color: Colors.white.withOpacity(0.2),
                    //     borderRadius: BorderRadius.circular(12)
                    //   ),
                    //   child: IconButton(
                    //     icon: const Icon(Icons.edit, color: Colors.white),
                    //     tooltip: "Edit Profile",
                    //     onPressed: _showEditCustomerBottomSheet,
                    //   ),
                    // ),


                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [

                        // ✏️ EDIT BUTTON
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12)
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white),
                            tooltip: "Edit Profile",
                            onPressed: _showEditCustomerBottomSheet,
                          ),
                        ),

                        const SizedBox(width: 8), // Space between buttons

                        // 📤 SHARE BUTTON
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12)
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.share, color: Colors.white),
                            tooltip: "Share Details",
                            onPressed: _shareCustomerDetails,
                          ),
                        ),
                      ],
                    ),







                  ],
                ),
              ),




              const SizedBox(height: 16),

              // 📱 NEW CLEAN CONTACT MANAGEMENT BUTTON ROW
              if (widget.c.phone.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      // 💾 RESPONSIVE SAVE BUTTON
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: const Text("Save Contact", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue.shade700,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _saveToPhoneContacts,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // 🗑️ RESPONSIVE DELETE BUTTON
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.person_remove, size: 18),
                          label: const Text("Delete Contact", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red.shade700,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _deleteFromPhoneContacts,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

              // 📦 INFO CARD
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(blurRadius: 15, color: Colors.black.withOpacity(0.04), offset: const Offset(0, 5))
                  ],
                ),
                child: Column(
                  children: [
                    rowItem(
                      Icons.phone_rounded,
                      Colors.green,
                      widget.c.phone.isEmpty ? "No Phone Provided" : widget.c.phone,
                      trailing: widget.c.phone.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.call, color: Colors.green),
                        onPressed: () async {
                          final Uri callUri = Uri(scheme: 'tel', path: widget.c.phone);
                          if (await canLaunchUrl(callUri)) {
                            await launchUrl(callUri);
                          } else {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch dialer")));
                          }
                        },
                      )
                      : null,
                      subtitle:'ইনার মোবাইল নম্বর',
                    ),



                    Divider(color: Colors.grey.shade200, height: 1),



                    rowItem(Icons.location_on_rounded, Colors.blue, widget.c.address.isEmpty ? "No Address Provided" : widget.c.address,subtitle:'ইনার ঠিকানা'),




                    Divider(color: Colors.grey.shade200, height: 1),



                    // 💵 TOTAL PAID
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.payments_rounded, color: Colors.green, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("ইনি মোট দিয়েছেন", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                // Text(
                                //   "${_totalPaid.toStringAsFixed(2)} টাকা",
                                //   style: const TextStyle(
                                //     fontSize: 15,
                                //     fontWeight: FontWeight.bold,
                                //     color: Colors.green,
                                //   ),
                                // ),
                                Text(
                                  "${_formatMoney(_totalPaid)} টাকা",
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: Colors.grey.shade200, height: 1),

                    // 💰 CURRENT DUE
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.currency_rupee_rounded, color: Colors.orange, size: 20),
                          ),
                          const SizedBox(width: 16),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                                                                "বর্তমান টাকা পাবেন",
                                  style: TextStyle(fontSize: 12, color: Colors.grey)
                                ),
                                const SizedBox(height: 4),
                                // Text(
                                //   "${displayDue.toStringAsFixed(2)} টাকা",
                                //   style: TextStyle(
                                //     fontSize: 15,
                                //     fontWeight: FontWeight.bold,
                                //     color: displayDue > 0 ? Colors.red : Colors.green,
                                //   ),
                                // ),
                                Text(
                                  "${_formatMoney(displayDue)} টাকা",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: displayDue > 0 ? Colors.red : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // EDIT DUE BUTTON
                          TextButton.icon(
                            onPressed: _showUpdateDueBottomSheet,
                            icon: const Icon(Icons.edit, size: 16, color: Colors.orange),
                            label: const Text("Edit", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.orange.shade50,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                          )
                        ],
                      ),
                    ),
                    Divider(color: Colors.grey.shade200, height: 1),
                    rowItem(Icons.calendar_month_rounded, Colors.purple, widget.c.createdAt, subtitle: "Added On"),
                  ],
                ),
              ),

              const SizedBox(height: 24),









              // Append this button inside your Scaffold actions, floating action hooks, or row items list inside customer_detail_page.dart:
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.calculate_outlined, size: 22),
                label: const Text("বিল তৈরী করুন", style: TextStyle(fontWeight: FontWeight.bold)),


                // 🔴 FIND YOUR NAVIGATION CODE IN customer_detail_page.dart AND UPDATE IT TO THIS:
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CustomerReceiptPage(customer: widget.c),
                    ),
                  );

                  // 🔥 THIS WILL RUN INSTANTLY WHEN YOU COME BACK
                  setState(() {
                    _loadImages();            // Reloads your image list
                    _refreshCustomerData();    // Reloads all text/due information
                  });
                },





              ),



              const SizedBox(height: 24),






              // 🔘 TRANSACTION BUTTON
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.receipt_long_rounded, color: Colors.white),
                  label: const Text("টাকা জমা করুন", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: Colors.indigo.shade600, // 🔥 CHANGED: Beautiful indigo color instead of black
                    foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: Colors.indigo.shade200,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TransactionPage(customer: widget.c)),
                    ).then((_) {
                      setState(() { _hasModifiedData = true; });
                      _refreshCustomerData();
                    });
                  },
                ),
              ),















              const SizedBox(height: 30),

              // 🖼 IMAGES HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Attached Images", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                  TextButton.icon(
                    onPressed: _showImagePickerOptions,
                    icon: const Icon(Icons.add_a_photo, color: Colors.redAccent, size: 18),
                    label: const Text("Add", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),

              // 🖼 IMAGE GRID
              imgs.isNotEmpty
              ? GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: imgs.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (_, i) {
                  return Stack(
                    children: [



//                       GestureDetector(
//                         onTap: () {
//                           showDialog(
//                             context: context,
//                             builder: (_) => Dialog(
//                               backgroundColor: Colors.transparent,
//                               insetPadding: const EdgeInsets.all(5),
//                               child: Stack(
//                                 alignment: Alignment.topRight,
//                                 children: [
//                                   InteractiveViewer(
//                                     child: ClipRRect(
//                                       borderRadius: BorderRadius.circular(16),
//                                       child: Image.file(
//                                         File(imgs[i]),
//                                         errorBuilder: (context, error, stackTrace) => _missingImageDialogPlaceholder(),
//                                       ),
//                                     ),
//                                   ),
//                                   IconButton(
//                                     icon: const Icon(Icons.close, color: Colors.white, size: 30),
//                                     onPressed: () => Navigator.pop(context),
//                                   )
//                                 ],
//                               ),
//                             ),
//                           );
//                         },
//
//                       ),

                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              backgroundColor: Colors.black, // কালো ব্যাকগ্রাউন্ডে ছবি ভালো দেখা যাবে
                              insetPadding: EdgeInsets.zero, // স্ক্রিনের সম্পূর্ণ জায়গা ব্যবহার করবে
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                              child: Stack(
                                children: [
                                  // জুম এবং প্যান করার জন্য ফুল-স্ক্রিন ভিউয়ার
                                  SizedBox(
                                    width: MediaQuery.of(context).size.width,
                                    height: MediaQuery.of(context).size.height,
                                    child: InteractiveViewer(
                                      panEnabled: true,
                                      minScale: 0.5,
                                      maxScale: 6.0, // লম্বা ছবির জন্য জুম লিমিট বাড়ানো হয়েছে
                                      clipBehavior: Clip.none,
                                      child: Image.file(
                                        File(imgs[i]),
                                        fit: BoxFit.contain, // প্রথমে পুরো ছবি স্ক্রিনে ফিট করে দেখাবে
                                        errorBuilder: (context, error, stackTrace) => _missingImageDialogPlaceholder(),
                                      ),
                                    ),
                                  ),

                                  // পরিষ্কারভাবে দৃশ্যমান ক্লোজ (X) বাটন
                                  Positioned(
                                    top: 40, // সেফ এরিয়া মার্জিন
                                    right: 20,
                                    child: GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7), // বাটনের পেছনের ডার্ক ব্যাকগ্রাউন্ড
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                        child: const Icon(Icons.close, color: Colors.white, size: 26),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(imgs[i]),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade300, width: 1),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_not_supported_rounded, color: Colors.grey.shade400, size: 28),
                                    const SizedBox(height: 4),
                                    Text("Missing", style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),







                      // DELETE BUTTON OVERLAY
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _deleteImage(i),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.delete, color: Colors.white, size: 16),
                          ),
                        ),
                      )
                    ],
                  );
                },
              )
              : Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text("No images attached", style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),






              // 💬 MESSAGE HISTORY HEADER
              const SizedBox(height: 30),
              const Row(
                children: [
                  Icon(Icons.history_edu_rounded, color: Colors.blueGrey, size: 22),
                  SizedBox(width: 8),
                  Text("Message History", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              ),
              const SizedBox(height: 12),

              // 💬 MESSAGE LIST
              _messages.isNotEmpty
              ? ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(msg['date'] ?? "", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),

                            // 🔥 UPDATED: Added Confirmation Dialog on Tap
                            GestureDetector(
                              onTap: () async {
                                bool confirm = await showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text("Delete Record?"),
                                    content: const Text("Are you sure you want to remove this message log?"),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text("DELETE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ) ?? false;

                                if (confirm) {
                                  await DBHelper.deleteMessage(msg['id']);
                                  _refreshCustomerData(); // Updates the UI instantly
                                }
                              },
                              child: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          msg['message'] ?? "",
                          style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                        ),
                      ],
                    ),
                  );
                },
              )
              : Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text("No message history", style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),




              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _missingImageDialogPlaceholder() {
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_rounded, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "Image file not found on device",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget rowItem(IconData icon, Color iconColor, String text, {String? subtitle, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                ],
                Text(
                  text,
                  style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
