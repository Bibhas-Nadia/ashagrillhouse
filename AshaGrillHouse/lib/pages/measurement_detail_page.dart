
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/measurement.dart';
import '../models/customer.dart';
import '../db_helper.dart';
import '../utils/sms_helper.dart';
import 'canvas_page.dart';
import 'measurement_form_page.dart';
import 'customer_detail_page.dart';
import 'set_price_page.dart';

class MeasurementDetailPage extends StatefulWidget {
  final Measurement measurement;

  const MeasurementDetailPage({Key? key, required this.measurement}) : super(key: key);

  @override
  _MeasurementDetailPageState createState() => _MeasurementDetailPageState();
}

class _MeasurementDetailPageState extends State<MeasurementDetailPage> {
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  // Modern Color Palette
  final Color primaryColor = const Color(0xFF4F46E5); // Indigo
  final Color primaryLight = const Color(0xFF6366F1); // Lighter Indigo
  final Color bgColor = const Color(0xFFE2E8F0);      // Darker Slate for High Contrast
  final Color textDark = const Color(0xFF0F172A);     // Slate 900
  final Color textMuted = const Color(0xFF64748B);    // Slate 500
  final Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final data = await DBHelper.getDetailedMeasurements(widget.measurement.id!);
    setState(() {
      _records = data;
      _isLoading = false;
    });
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "Unknown Date";
    try {
      DateTime dt = DateTime.parse(isoString);
      return "${dt.day}/${dt.month}/${dt.year} • ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "Invalid Date";
    }
  }

  // ==========================================
  // 🔥 HELPER: Get Existing Customer
  // ==========================================
  Future<Customer?> _getExistingCustomer() async {
    final customers = await DBHelper.getCustomers();
    try {
      return customers.firstWhere((c) =>
      c.name == widget.measurement.name &&
      c.phone == widget.measurement.phone &&
      c.address == widget.measurement.address
      );
    } catch (e) {
      return null;
    }
  }

  // ==========================================
  // 🔥 HELPER: Create New Customer
  // ==========================================
  Future<Customer> _createNewCustomer() async {

    String now =
    "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year} "
    "${DateTime.now().hour}:${DateTime.now().minute}";

    Customer newCustomer = Customer(
      name: widget.measurement.name,
      phone: widget.measurement.phone,
      address: widget.measurement.address,
      due: "0",
      images: "",
      createdAt: now
    );

    await DBHelper.insert(newCustomer);

    // Fetch it back to get the DB-assigned ID
    return (await _getExistingCustomer())!;
  }

  // ==========================================
  // 🔥 ACTION: Handle Menu Clicks
  // ==========================================
  Future<void> _handleMenuAction(String action) async {

    // 1. Redirect for Price Setting (Passes the current measurement)
    if (action == 'set_price') {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            // Pass the current measurement object here
            builder: (context) => SetPricePage(measurement: widget.measurement),
          ),
        );
      }
      return;
    }

    Customer? existingCustomer = await _getExistingCustomer();

    // RULE 1: If customer already exists, redirect immediately for both buttons!
    if (existingCustomer != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Customer already exists! Redirecting to profile..."),
          backgroundColor: Colors.orange,
        ));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CustomerDetailPage(c: existingCustomer)),
        );
      }
      return;
    }

    // RULE 2: If customer does NOT exist
    if (action == 'add_customer') {
      // Create and redirect
      Customer newCust = await _createNewCustomer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Added to Customer List successfully!"),
          backgroundColor: Colors.green,
        ));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CustomerDetailPage(c: newCust)),
        );
      }
    } else if (action == 'add_advance') {
      // Open form to add advance
      _showAdvanceMoneyBottomSheet();
    }
  }

  // ==========================================
  // 🔥 ACTION: Add Advance Money Bottom Sheet
  // ==========================================
  void _showAdvanceMoneyBottomSheet() {
    final TextEditingController amountCtrl = TextEditingController();
    bool sendSMS = widget.measurement.phone.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                        Icon(Icons.payments_rounded, color: Colors.green, size: 28),
                        SizedBox(width: 10),
                        Text("Add Advance Money", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Advance Amount",
                        prefixIcon: Icon(Icons.currency_rupee_rounded, color: Colors.grey.shade600),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (widget.measurement.phone.isNotEmpty)
                      Row(
                        children: [
                          Checkbox(
                            value: sendSMS,
                            activeColor: Colors.green.shade600,
                            onChanged: (v) => setModalState(() => sendSMS = v ?? false),
                          ),
                          const Text("Send SMS Notification", style: TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () async {
                            if (amountCtrl.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter amount.")));
                              return;
                            }

                            double? amount = double.tryParse(amountCtrl.text);
                            if (amount == null || amount <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid amount.")));
                              return;
                            }

                            // 1. We already know customer doesn't exist, so create them
                            Customer newCust = await _createNewCustomer();

                            final now = DateTime.now();

                            String dateTime =
                            "${now.day}-${now.month}-${now.year} "
                            "${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? "PM" : "AM"}";

                            // 2. Add transaction
                            await DBHelper.insertTransaction(
                              newCust.id!,
                              amount.toStringAsFixed(2),
                              dateTime,
                              "Advance Payment from Measurement"
                            );

                            // 3. Update the Due amount (subtracting advance makes it negative or 0)
                            double newDue = 0.0 - amount;
                            await DBHelper.updateCustomerDue(newCust.id!, newDue);
                            newCust.due = newDue.toStringAsFixed(2);

                            // 4. Navigate to Customer Detail Page FIRST
                            if (context.mounted) {
                              Navigator.pop(context); // Close bottom sheet

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Customer created & Advance added! Opening Profile..."), backgroundColor: Colors.green)
                              );

                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CustomerDetailPage(c: newCust),
                                ),
                              );
                            }

                            // 5. THEN open the SMS app over the new page
                            if (sendSMS && widget.measurement.phone.isNotEmpty) {
                              // A tiny delay ensures the page transition animation starts smoothly before native SMS app pops up
                              await Future.delayed(const Duration(milliseconds: 400));

                              String? status = await DBHelper.getStatus();

                              String msg;

                              // 2. Check if status is "active"
                              if (status == "active") {
                                // Message for Active Status
                                msg = "Dear ${widget.measurement.name}\nWe have received your advance payment of Rs. $amount. Thank you!\n\n- Asha Grill House\nView details: https://ashagrillhouse.github.io/site/receipt.html?q=${widget.measurement.phone.replaceAll(RegExp(r'\D'), '').substring(widget.measurement.phone.replaceAll(RegExp(r'\D'), '').length - 10)}";
                              }
                              else {
                                // 3. Message for Inactive or any other status
                                msg = "Dear ${widget.measurement.name}\nWe have received your advance payment of Rs. $amount. Thank you!\n\n- Asha Grill House";
                              }

                              await SmsHelper.sendSMS(phone: widget.measurement.phone, message: msg);

                              String now =
                              "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year} "
                              "${DateTime.now().hour}:${DateTime.now().minute}";

                              if (newCust.id != null) {
                              await DBHelper.insertMessage(newCust.id!,msg,now);
                              }else{
                                print("Error: Customer ID is missing!");
                              }


                            }
                          },
                          child: const Text("SUBMIT ADVANCE", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  // Full Screen Image Zoom Popup
  void _showImageZoomDialog(String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 80),
                    const SizedBox(height: 16),
                    const Text("Image file not found on device", style: TextStyle(color: Colors.white54, fontSize: 16)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.cancel, color: Colors.white70, size: 36),
                onPressed: () => Navigator.pop(context),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showAddOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
              ),
              Text("Add Measurement", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark)),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildOptionCard(
                    icon: Icons.feed_rounded,
                    title: "Use Form",
                    color: primaryColor,
                    onTap: () async {
                      Navigator.pop(context);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => MeasurementFormPage(customer: widget.measurement)),
                      );
                      if (result == true) _loadRecords();
                    },
                  ),
                  _buildOptionCard(
                    icon: Icons.draw_rounded,
                    title: "Draw Canvas",
                    color: const Color(0xFF0D9488), // Teal
                    onTap: () async {
                      Navigator.pop(context);
                      final savedImagePath = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => CanvasPage(customerName: widget.measurement.name)),
                      );

                      if (savedImagePath != null) {
                        await DBHelper.insertDetailedMeasurement({
                          'customerId': widget.measurement.id,
                          'height': '',
                          'length': '',
                          'note': 'Canvas Drawing',
                          'images': savedImagePath,
                          'createdAt': DateTime.now().toIso8601String(),
                        });
                        _loadRecords();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text("খদ্দেরের বিস্তারিত মাপ ", style: TextStyle(fontWeight: FontWeight.w700, color: textDark, fontSize: 18)),
        backgroundColor: cardColor,
        elevation: 1,
        iconTheme: IconThemeData(color: textDark),
        centerTitle: true,
        // 🔥 Updated Dropdown Menu
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: textDark),
            onSelected: _handleMenuAction,
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'add_customer',
                child: Text('হিসাবে যুক্ত করুন', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              const PopupMenuItem(
                value: 'add_advance',
                child: Text('অ্যাডভান্স টাকা নথিভুক্ত করুন', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              const PopupMenuItem(
                value: 'set_price',
                child: Text('দরদাম নিশ্চিত করুন', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ],
      ),




      body: Column(
        children: [




          // // 📦 TOP SECTION: Compact Profile Card
          // Container(
          //   margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          //   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          //   decoration: BoxDecoration(
          //     gradient: LinearGradient(
          //       colors: [primaryColor, primaryLight],
          //       begin: Alignment.topLeft,
          //       end: Alignment.bottomRight,
          //     ),
          //     borderRadius: BorderRadius.circular(20),
          //     boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
          //   ),
          //   child: Row(
          //     children: [
          //       CircleAvatar(
          //         radius: 20,
          //         backgroundColor: Colors.white.withOpacity(0.9),
          //         child: Text(
          //           widget.measurement.name.isNotEmpty ? widget.measurement.name[0].toUpperCase() : '?',
          //           style: TextStyle(color: primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
          //         ),
          //       ),
          //       const SizedBox(width: 12),
          //       Expanded(
          //         child: Column(
          //           crossAxisAlignment: CrossAxisAlignment.start,
          //           children: [
          //             Text(
          //               widget.measurement.name,
          //               style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          //             ),
          //             const SizedBox(height: 2),
          //             if (widget.measurement.phone.isNotEmpty)
          //               _buildCompactWhiteInfoRow(Icons.phone_rounded, widget.measurement.phone),
          //               if (widget.measurement.address.isNotEmpty)
          //                 _buildCompactWhiteInfoRow(Icons.location_on_rounded, widget.measurement.address),
          //           ],
          //         ),
          //       ),
          //       InkWell(
          //         onTap: _showAddOptionsBottomSheet,
          //         borderRadius: BorderRadius.circular(12),
          //         child: Container(
          //           padding: const EdgeInsets.all(8),
          //           decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
          //           child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
          //         ),
          //       ),
          //     ],
          //   ),
          // ),


          // 📦 TOP SECTION: Compact Profile Card (Clickable Name, Avatar, Phone, Address)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                // 🔥 Wrapped Left Side with GestureDetector to trigger 'add_customer' navigation
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleMenuAction('add_customer'),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white.withOpacity(0.9),
                          child: Text(
                            widget.measurement.name.isNotEmpty ? widget.measurement.name[0].toUpperCase() : '?',
                            style: TextStyle(color: primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.measurement.name,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              if (widget.measurement.phone.isNotEmpty)
                                _buildCompactWhiteInfoRow(Icons.phone_rounded, widget.measurement.phone),
                                if (widget.measurement.address.isNotEmpty)
                                  _buildCompactWhiteInfoRow(Icons.location_on_rounded, widget.measurement.address),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Left Add Button untouched to still toggle its own bottom sheet menu
                InkWell(
                  onTap: _showAddOptionsBottomSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),







          // 📄 MIDDLE SECTION: Scrollable Records List
          Expanded(
            child: _isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : _records.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              physics: const BouncingScrollPhysics(),
              itemCount: _records.length,
              itemBuilder: (context, index) {
                return _buildMeasurementCard(_records[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  // Builds Individual Compact Cards
  Widget _buildMeasurementCard(Map<String, dynamic> item) {
    String imagePath = item['images'] ?? '';
    bool hasImage = imagePath.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Date & Delete
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 14, color: textMuted),
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(item['createdAt']),
                      style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    bool? confirm = await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text("Delete Record", style: TextStyle(fontSize: 18)),
                        content: const Text("Are you sure you want to permanently delete this measurement?", style: TextStyle(fontSize: 14)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                        ],
                      )
                    );
                    if (confirm == true) {
                      await DBHelper.deleteDetailedMeasurement(item['id']);
                      _loadRecords();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 16),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
            ),

            // Image Content
            if (hasImage) ...[
              GestureDetector(
                onTap: () => _showImageZoomDialog(imagePath),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.file(
                        File(imagePath),
                        height: 85,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 85,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300, width: 1),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))
                            ]
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_not_supported_rounded, color: Colors.grey.shade400, size: 24),
                              const SizedBox(height: 4),
                              Text("Image Missing", style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 18),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Specs
            if ((item['height'] ?? '').isNotEmpty || (item['length'] ?? '').isNotEmpty)
              Row(
                children: [
                  if ((item['height'] ?? '').isNotEmpty)
                    Expanded(child: _buildDataPill("Height", item['height'], Icons.height_rounded)),
                    if ((item['height'] ?? '').isNotEmpty && (item['length'] ?? '').isNotEmpty)
                      const SizedBox(width: 12),
                      if ((item['length'] ?? '').isNotEmpty)
                        Expanded(child: _buildDataPill("Length", item['length'], Icons.straighten_rounded)),
                ],
              ),

              // Notes
              if ((item['note'] ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: const Border(left: BorderSide(color: Color(0xFF94A3B8), width: 3)),
                  ),
                  child: Text(
                    item['note'],
                    style: TextStyle(fontSize: 14, color: textDark, height: 1.4),
                  ),
                ),
              ]
          ],
        ),
      ),
    );
  }

  Widget _buildDataPill(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.1), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: primaryColor, fontWeight: FontWeight.w600)),
                Text(value, style: TextStyle(fontSize: 22, color: textDark, fontWeight: FontWeight.w900)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
            child: Icon(Icons.inventory_2_rounded, size: 48, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          Text("No measurements yet", style: TextStyle(color: textDark, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text("Tap the '+' button above to add some.", style: TextStyle(color: textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCompactWhiteInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 30, color: color),
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textDark)),
        ],
      ),
    );
  }
}

