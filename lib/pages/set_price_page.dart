import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/measurement.dart';
import '../db_helper.dart';
import '../utils/sms_helper.dart';

class PriceItem {
  String selectedType;
  TextEditingController priceController;

  PriceItem({required this.selectedType})
  : priceController = TextEditingController();
}

class SetPricePage extends StatefulWidget {
  final Measurement measurement;

  const SetPricePage({Key? key, required this.measurement}) : super(key: key);

  @override
  _SetPricePageState createState() => _SetPricePageState();
}

class _SetPricePageState extends State<SetPricePage> {
  final List<String> itemTypes = [
    "লোহা", "সিট্", "ফুল", "পাতা", "কব্জা", "ফুট হিসাবে", "মজুরি", "পুরানো লোহা" ,"হ্যান্ডেল", "অন্যান্য"
  ];

  List<PriceItem> items = [];
  bool sendSms = true;
  bool isLoading = true;
  bool isEditing = false; // Controls whether we show the Form or the Receipt

  Map<String, dynamic>? existingAgreement;

  @override
  void initState() {
    super.initState();
    _loadExistingAgreement();
  }

  @override
  void dispose() {
    for (var item in items) {
      item.priceController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingAgreement() async {
    setState(() => isLoading = true);
    try {
      final data = await DBHelper.getPriceAgreement(widget.measurement.id!);

      if (data != null) {
        // Data exists: Populate the existing items to memory for editing
        existingAgreement = data;
        List<dynamic> parsedItems = jsonDecode(data['priceListJson']);

        _populateItemsList(parsedItems);
        setState(() => isEditing = false); // Show the Receipt view first
      } else {
        // No data exists: First time user
        items = [PriceItem(selectedType: "লোহা")];
        setState(() => isEditing = true); // Show the Form immediately
      }
    } catch (e) {
      debugPrint("Error loading agreement: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Fills the text controllers with previous data if editing
  void _populateItemsList(List<dynamic> savedItems) {
    items.clear();
    for (var item in savedItems) {
      String type = item['type'];
      // Ensure the saved type exists in our dropdown list to prevent errors
      if (!itemTypes.contains(type)) {
        itemTypes.add(type);
      }
      var priceItem = PriceItem(selectedType: type);
      priceItem.priceController.text = item['price'].toString();
      items.add(priceItem);
    }
  }

  void _addItem() {
    setState(() => items.add(PriceItem(selectedType: "লোহা")));
  }

  void _removeItem(int index) {
    if (items.length > 1) {
      setState(() {
        items[index].priceController.dispose();
        items.removeAt(index);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must have at least one item.", style: TextStyle(fontSize: 16)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleAgreeAndSave() async {
    // 1. Validation
    for (var item in items) {
      if (item.priceController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please enter a price for all items.", style: TextStyle(fontSize: 16)),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() => isLoading = true);

    try {
      List<Map<String, dynamic>> itemsList = [];
      String messageDetails = "";

      // 2. Calculate Totals and Build Message
      for (var item in items) {
        String type = item.selectedType;
        String price = item.priceController.text.trim();

        itemsList.add({'type': type, 'price': price});
        messageDetails += "- $type: Rs. $price\n";
      }

      String priceListJson = jsonEncode(itemsList);
      String message = "";
      bool canSendSms = widget.measurement.phone.isNotEmpty;

      if (canSendSms) {
        message = "Dear ${widget.measurement.name}\n"
        "We have agreed on the following prices for your order:\n"
        "$messageDetails\n"
        "- Asha Grill House";
      }

      // 3. Save to Database
      await DBHelper.insertPriceAgreement(
        measurementId: widget.measurement.id!,
        priceListJson: priceListJson,
        sentMessage: sendSms && canSendSms ? message : "SMS Not Sent (Or no phone number)",
      );

      // 4. Send SMS if requested
      if (sendSms && canSendSms) {
        await SmsHelper.sendSMS(phone: widget.measurement.phone, message: message);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Prices saved successfully!", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green
          ),
        );
        // Reload to show the receipt view
        _loadExistingAgreement();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasPhone = widget.measurement.phone.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8), // Softer background for better contrast
      appBar: AppBar(
        title: const Text("Price Agreement", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 22)),
        backgroundColor: Colors.indigo,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
      ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
      : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerProfile(hasPhone),
            const SizedBox(height: 24),

            // Toggle between Receipt View and Edit Form View
            if (!isEditing && existingAgreement != null)
              _buildExistingDataReceipt()
              else
                _buildForm(hasPhone),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // UI: CUSTOMER PROFILE (Larger & Clearer)
  // ==========================================
  Widget _buildCustomerProfile(bool hasPhone) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.indigo.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.indigo,
                child: Text(
                  widget.measurement.name.isNotEmpty ? widget.measurement.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.measurement.name,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87)
                )
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.only(top: 16), child: Divider(height: 1, thickness: 1)),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.phone_rounded, size: 28, color: Colors.green),
              const SizedBox(width: 12),
              Text(
                hasPhone ? widget.measurement.phone : "No Phone Number",
                style: TextStyle(fontSize: 18, color: hasPhone ? Colors.black87 : Colors.red, fontWeight: FontWeight.w600)
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 28, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.measurement.address.isNotEmpty ? widget.measurement.address : "No Address Provided",
                  style: const TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.w500)
                )
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // UI: EXISTING AGREEMENT RECEIPT
  // ==========================================
  Widget _buildExistingDataReceipt() {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 30),
            SizedBox(width: 10),
            Text("Fixed Prices Saved", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            border: Border.all(color: Colors.green.shade400, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Agreed Items:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 12),
              ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("• ${item.selectedType}", style: const TextStyle(fontSize: 20, color: Colors.black87)),
                    Text("₹ ${item.priceController.text}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                  ],
                ),
              )).toList(),

              const Divider(height: 30, thickness: 2),


              const SizedBox(height: 24),
              const Text("Message Sent to Customer:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade100)),
                child: Text(
                  existingAgreement!['sentMessage'] ?? 'No message stored',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 16, height: 1.5, color: Colors.indigo.shade900),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 20),

        // BIG EDIT BUTTON
        SizedBox(
          width: double.infinity,
          height: 60,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => isEditing = true),
            icon: const Icon(Icons.edit_document, size: 28, color: Colors.indigo),
            label: const Text("EDIT PRICES", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.indigo, width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // UI: NEW / EDIT AGREEMENT FORM
  // ==========================================
  Widget _buildForm(bool hasPhone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(existingAgreement == null ? "Set New Prices" : "Edit Prices",
             style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo)
        ),
        const SizedBox(height: 16),

        // ListView.builder(
        //   shrinkWrap: true,
        //   physics: const NeverScrollableScrollPhysics(),
        //   itemCount: items.length,
        //   itemBuilder: (context, index) {
        //     return Container(
        //       margin: const EdgeInsets.only(bottom: 16),
        //       padding: const EdgeInsets.all(16),
        //       decoration: BoxDecoration(
        //         color: Colors.white,
        //         borderRadius: BorderRadius.circular(16),
        //         border: Border.all(color: Colors.grey.shade400, width: 1.5),
        //         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)]
        //       ),
        //       child: Row(
        //         children: [
        //           Expanded(
        //             flex: 4,
        //             child: DropdownButtonFormField<String>(
        //               value: items[index].selectedType,
        //               style: const TextStyle(fontSize: 18, color: Colors.black),
        //               decoration: const InputDecoration(
        //                 labelText: "Material",
        //                 labelStyle: TextStyle(fontSize: 18),
        //                 border: OutlineInputBorder(),
        //                 contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16)
        //               ),
        //               items: itemTypes.map((type) => DropdownMenuItem(value: type, child: Text(type, style: const TextStyle(fontSize: 18)))).toList(),
        //               onChanged: (val) { if (val != null) setState(() => items[index].selectedType = val); },
        //             ),
        //           ),
        //           const SizedBox(width: 12),
        //           Expanded(
        //             flex: 4,
        //             child: TextFormField(
        //               controller: items[index].priceController,
        //               keyboardType: TextInputType.number,
        //               style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        //               decoration: const InputDecoration(
        //                 labelText: "Price (₹)",
        //                 labelStyle: TextStyle(fontSize: 18),
        //                 prefixIcon: Icon(Icons.currency_rupee, size: 20),
        //                 border: OutlineInputBorder(),
        //                 contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16)
        //               ),
        //             ),
        //           ),
        //           IconButton(
        //             icon: const Icon(Icons.remove_circle, color: Colors.red, size: 32),
        //             onPressed: () => _removeItem(index),
        //           )
        //         ],
        //       ),
        //     );
        //   },
        // ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12), // Slightly reduced padding
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade400, width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)]
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5, // Given slightly more space to the material name
                    child: DropdownButtonFormField<String>(
                      isExpanded: true, // 🔥 THIS FIXES THE OVERFLOW
                      value: items[index].selectedType,
                      style: const TextStyle(fontSize: 16, color: Colors.black), // Reduced to 16 for better fit
                      decoration: const InputDecoration(
                        labelText: "Material",
                        labelStyle: TextStyle(fontSize: 16),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 16)
                      ),
                      items: itemTypes.map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                          type,
                          style: const TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis, // 🔥 Ensures long text adds "..." instead of overflowing
                        )
                      )).toList(),
                      onChanged: (val) { if (val != null) setState(() => items[index].selectedType = val); },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      controller: items[index].priceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: "Price",
                        labelStyle: TextStyle(fontSize: 16),
                        prefixIcon: Icon(Icons.currency_rupee, size: 18),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 16)
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Adjusted icon button to take less horizontal space
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(), // Removes default wide padding
                    icon: const Icon(Icons.remove_circle, color: Colors.red, size: 30),
                    onPressed: () => _removeItem(index),
                  )
                ],
              ),
            );
          },
        ),


        TextButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add_circle, color: Colors.indigo, size: 28),
          label: const Text("Add Another Material", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 18)),
        ),

        const SizedBox(height: 20),
        const Divider(thickness: 2),
        const SizedBox(height: 10),

        if (hasPhone)
          Container(
            decoration: BoxDecoration(
              color: sendSms ? Colors.green.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sendSms ? Colors.green : Colors.grey.shade300, width: 2)
            ),
            child: CheckboxListTile(
              value: sendSms,
              activeColor: Colors.green,
              title: const Text("Send Confirmation SMS to Customer", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: const Text("Sends a clear receipt message to avoid misunderstandings.", style: TextStyle(fontSize: 14)),
              onChanged: (val) => setState(() => sendSms = val ?? true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),

          if (!hasPhone)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange)),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 30),
                  SizedBox(width: 12),
                  Expanded(child: Text("Cannot send SMS: No phone number provided for this customer.", style: TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold))),
                ],
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 65, // Very large touch target
              child: ElevatedButton.icon(
                onPressed: _handleAgreeAndSave,
                icon: const Icon(Icons.handshake_rounded, color: Colors.white, size: 32),
                label: Text(existingAgreement == null ? "SAVE AGREEMENT" : "UPDATE AGREEMENT", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4
                ),
              ),
            ),

            // If editing, allow them to cancel and go back to the receipt view
            if (existingAgreement != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: TextButton(
                  onPressed: () => setState(() {
                    _populateItemsList(jsonDecode(existingAgreement!['priceListJson'])); // Revert to saved data
                    isEditing = false;
                  }),
                  child: const Text("Cancel Edit", style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              )
            ]
      ],
    );
  }
}
