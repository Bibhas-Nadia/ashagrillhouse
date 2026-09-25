

                import 'dart:io';
                import 'package:flutter/material.dart';
                import 'package:speech_to_text/speech_to_text.dart' as stt;
                import 'package:intl/intl.dart';
                import 'customer_detail_page.dart';
                import 'add_customer_page.dart';
                import '../db_helper.dart';

                class CustomersPage extends StatefulWidget {
                  @override
                  _CustomersPageState createState() => _CustomersPageState();
                }

                class _CustomersPageState extends State<CustomersPage> {
                  List customers = [];
                  List filtered = [];
                  final searchController = TextEditingController();

                  // Sorting State
                  String sortType = "last_txn";

                  late stt.SpeechToText speech;
                  bool isListening = false;
                  List<int> _pinnedIds = [];
                  Map<int, DateTime> _lastTxnDates = {};

                  @override
                  void initState() {
                    super.initState();
                    speech = stt.SpeechToText();
                    load();
                  }

                  // 📥 LOAD DATA
                  // load() async {
                  //   customers = await DBHelper.getCustomers();
                  //   _processSearchAndSort();
                  // }

                  load() async {
                    customers = await DBHelper.getCustomers();
                    // Fetch the list of pinned IDs
                    final pins = await DBHelper.db.then((db) => db.query("pins"));
                    _pinnedIds = pins.map((e) => e['customerId'] as int).toList();

                    // 🟢 ডাটাবেজ থেকে প্রতিটি কাস্টমারের সর্বশেষ লেনদেনের তারিখ বের করা হচ্ছে
                    final dbClient = await DBHelper.db;
                    final txns = await dbClient.query("transactions", columns: ["customerId", "date"]);

                    _lastTxnDates.clear();
                    for (var txn in txns) {
                      int? cId = txn['customerId'] as int?;
                      if (cId != null) {
                        String dStr = txn['date']?.toString() ?? "";
                        DateTime dt;
                        try {
                          if (dStr.contains(' ')) {
                            dt = DateFormat('dd-M-yyyy HH:mm').parse(dStr);
                          } else {
                            dt = DateFormat('dd-M-yyyy').parse(dStr);
                          }
                        } catch (_) {
                          dt = DateTime(2000);
                        }

                        // যদি কাস্টমারের কোনো ট্রানজেকশন না থাকে বা নতুন ট্রানজেকশনটি আগেরটির চেয়ে লেটেস্ট হয়
                        if (!_lastTxnDates.containsKey(cId) || dt.isAfter(_lastTxnDates[cId]!)) {
                          _lastTxnDates[cId] = dt;
                        }
                      }
                    }

                    _processSearchAndSort();
                  }





                  // 🔄 UNIFIED SEARCH & SORT LOGIC
                  void _processSearchAndSort() {
                    String query = searchController.text.toLowerCase().trim();

                    // 1. Filter (🔥 Changed to search by Name OR Phone Number)
                    List temp = customers.where((c) {
                      final name = c.name.toString().toLowerCase();
                      final phone = c.phone.toString().toLowerCase(); // Added phone search

                      return name.contains(query) || phone.contains(query);
                    }).toList();

                    DateTime parseMyDate(String dateStr) {
                      try {
                        // Matches formats like '11-4-2026 15:17' or '11-12-2002'
                        if (dateStr.contains(' ')) {
                          return DateFormat('dd-M-yyyy HH:mm').parse(dateStr);
                        } else {
                          return DateFormat('dd-M-yyyy').parse(dateStr);
                        }
                      } catch (e) {
                        return DateTime(2000); // Fallback for truly invalid data
                      }
                    }

                    // 2. Sort
                    temp.sort((a, b) {
                      switch (sortType) {
                        case "last_txn": // 🟢 শেষ লেনদেনকারী খদ্দের সবার উপরে যাবে
                          DateTime dtA = _lastTxnDates[a.id] ?? DateTime(2000);
                          DateTime dtB = _lastTxnDates[b.id] ?? DateTime(2000);
                          return dtB.compareTo(dtA);
                        case "name_asc":
                          return a.name.toString().toLowerCase().compareTo(b.name.toString().toLowerCase());
                        case "name_desc":
                          return b.name.toString().toLowerCase().compareTo(a.name.toString().toLowerCase());
                        case "due_low":
                          return (double.tryParse(a.due) ?? 0).compareTo(double.tryParse(b.due) ?? 0);
                        case "due_high":
                          return (double.tryParse(b.due) ?? 0).compareTo(double.tryParse(a.due) ?? 0);
                        case "date_asc":
                          return parseMyDate(a.createdAt).compareTo(parseMyDate(b.createdAt));
                        case "date_desc":
                        default:
                          return parseMyDate(b.createdAt).compareTo(parseMyDate(a.createdAt));
                      }
                    });


                    // 3. 🔥 Pinned logic: Split and Re-join
                    List pinnedList = temp.where((c) => _pinnedIds.contains(c.id)).toList();
                    List unpinnedList = temp.where((c) => !_pinnedIds.contains(c.id)).toList();

                    setState(() {
                      // Pinned list comes first, then the rest
                      filtered = [...pinnedList, ...unpinnedList];
                    });

                    // setState(() {
                    //   filtered = temp;
                    // });
                  }











                  // 🎤 VOICE SEARCH
                  void startListening() async {
                    bool available = await speech.initialize();
                    if (available) {
                      setState(() => isListening = true);
                      speech.listen(
                        localeId: "bn_IN",
                        onResult: (result) {
                          searchController.text = result.recognizedWords;
                          _processSearchAndSort();
                          if (result.finalResult) stopListening();
                        },
                      );
                    }
                  }

                  void stopListening() {
                    speech.stop();
                    setState(() => isListening = false);
                  }

                  @override
                  Widget build(BuildContext context) {
                    return Scaffold(
                      backgroundColor: const Color(0xfff4f6fb),

                      // 🛠 APP BAR WITH POPUP SORT (🔥 Changed to Orange Theme)
                      appBar: AppBar(
                        title: const Text("খদ্দেরের হিসাব", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), // White Text
                        backgroundColor: Colors.deepOrange, // Orange background
                        elevation: 0,
                        iconTheme: const IconThemeData(color: Colors.white), // White icons

                        actions: [
                          // 🆕 BEAUTIFUL "ADD NEW" BUTTON (🔥 Changed to White button with Orange text)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0), // Adjusted vertical padding
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => AddCustomerPage()));
                                load();
                              },
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Colors.deepOrange), // Orange icon, slightly bigger
                              label: const Text(
                                "Add",
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 15) // Orange text, bigger size
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white, // White background
                                elevation: 2,
                                shadowColor: Colors.black.withOpacity(0.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14), // Slightly increased padding
                              ),
                            ),
                          ),

                          // 🔽 EXISTING SORT BUTTON (Popup Icon will be white due to iconTheme)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.sort_rounded),
                            onSelected: (value) {
                              sortType = value;
                              _processSearchAndSort();
                            },
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            itemBuilder: (context) => [
                              _buildMenuItem("last_txn", Icons.swap_horiz_rounded, "Last Transaction"),
                              _buildMenuItem("date_desc", Icons.history, "Newest First"),
                              _buildMenuItem("date_asc", Icons.update, "Oldest First"),
                              _buildMenuItem("name_asc", Icons.sort_by_alpha, "Name A-Z"),
                              _buildMenuItem("name_desc", Icons.sort_by_alpha, "Name Z-A"),
                              _buildMenuItem("due_high", Icons.arrow_upward, "Due High → Low"),
                              _buildMenuItem("due_low", Icons.arrow_downward, "Due Low → High"),
                            ],
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),

                      body: Column(
                        children: [
                          // 🔍 SEARCH BAR
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))
                              ],
                            ),
                            child: TextField(
                              controller: searchController,
                              onChanged: (val) => _processSearchAndSort(),
                              style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                hintText: "Search name or phone...", // Updated hint text
                                hintStyle: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                                prefixIcon: const Icon(Icons.search, color: Colors.deepOrange, size: 24),

                                // suffixIcon: IconButton(
                                //   icon: Icon(isListening ? Icons.mic : Icons.mic_none, color: isListening ? Colors.red : Colors.grey, size: 24),
                                //   onPressed: isListening ? stopListening : startListening,
                                // ),

                                suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.deepOrange, size: 24),
                                  tooltip: "Clear search",
                                  onPressed: () {
                                    searchController.clear();
                                    _processSearchAndSort();
                                    setState(() {});
                                  },
                                )
                                : IconButton(
                                  icon: Icon(isListening ? Icons.mic : Icons.mic_none, color: isListening ? Colors.red : Colors.grey, size: 24),
                                  onPressed: isListening ? stopListening : startListening,
                                ),

                                filled: true,
                                fillColor: const Color(0xfff1f3f8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                              ),
                            ),
                          ),

                          // 📋 CUSTOMER LIST
                          Expanded(
                            child: filtered.isEmpty
                            ? const Center(child: Text("No Customers Found", style: TextStyle(color: Colors.grey, fontSize: 16)))
                            : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _customerCard(filtered[i]),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  PopupMenuItem<String> _buildMenuItem(String value, IconData icon, String label) {
                    bool isSelected = sortType == value;
                    return PopupMenuItem(
                      value: value,
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: isSelected ? Colors.deepOrange : Colors.grey),
                          const SizedBox(width: 12),
                          Text(label, style: TextStyle(color: isSelected ? Colors.deepOrange : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        ],
                      ),
                    );
                  }



                  Widget _customerCard(var c) {
                    double due = double.tryParse(c.due.toString()) ?? 0.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],

                        // 🔥 ADDED BACKGROUND IMAGE HERE
                        image: const DecorationImage(
                          image: AssetImage('assets/images/card_bg1.png'), // 👈 Put your background image path here
                          fit: BoxFit.cover, // Ensures the image covers the whole card
                          opacity: 0.25, // 👈 Adjust this for lighter/darker opacity (0.1 is 10%)
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent, // Important: Keeps background visible
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailPage(c: c)));
                            load();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // 🖼 IMAGE
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Image.asset(
                                    'assets/images/customer.png',
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 50,
                                      height: 50,
                                      color: Colors.orange.shade50,
                                      child: const Icon(Icons.person, color: Colors.deepOrange)
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // INFO
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Inside your list item widget
                                      // Row(
                                      //   children: [
                                      //     Text(c.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                      //     if (_pinnedIds.contains(c.id))
                                      //       const Padding(
                                      //         padding: EdgeInsets.only(left: 8.0),
                                      //         child: Icon(Icons.push_pin, size: 14, color: Colors.lightGreen),
                                      //       ),
                                      //   ],
                                      // ),


                                      // Inside your list item widget
                                      Row(
                                        children: [
                                          // 🔥 WRAPPED IN EXPANDED TO PREVENT OVERFLOW
                                          Expanded(
                                            child: Text(
                                              c.name,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                              maxLines: 1, // Restrict to single line
                                              overflow: TextOverflow.ellipsis, // Adds "..." if too long
                                            ),
                                          ),
                                          if (_pinnedIds.contains(c.id))
                                            const Padding(
                                              padding: EdgeInsets.only(left: 8.0),
                                              child: Icon(Icons.push_pin, size: 14, color: Colors.lightGreen),
                                            ),
                                        ],
                                      ),





                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.phone, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              c.phone.toString().isEmpty ? "No Phone" : c.phone.toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.grey, fontSize: 13)
                                            )
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // AMOUNT & TIME
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "${due.toStringAsFixed(0)} ₹",
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: due > 0 ? Colors.redAccent : Colors.green)
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatDateTime(c.createdAt),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500, height: 1.2),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }






                  String _formatDateTime(String dateStr) {
                    try {
                      DateTime dt;
                      if (dateStr.contains(' ')) {
                        dt = DateFormat('dd-M-yyyy HH:mm').parse(dateStr);
                      } else {
                        dt = DateFormat('dd-M-yyyy').parse(dateStr);
                      }
                      return DateFormat('dd/MM/yyyy\nhh:mm a').format(dt);
                    } catch (e) {
                      return dateStr;
                    }
                  }
                }
