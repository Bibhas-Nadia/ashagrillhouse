// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import '../db_helper.dart'; // Adjust path if needed
//
// class TransactionHistoryPage extends StatefulWidget {
//   @override
//   _TransactionHistoryPageState createState() => _TransactionHistoryPageState();
// }
//
// class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
//   List<Map<String, dynamic>> allTransactions = [];
//   List<Map<String, dynamic>> filteredTransactions = [];
//   bool isLoading = true;
//
//   double totalAmount = 0.0;
//
//   // Date Range Variables
//   DateTime? startDate;
//   DateTime? endDate;
//
//   @override
//   void initState() {
//     super.initState();
//
//     // Default Filter: From 1st of the Current Month to Today
//     DateTime now = DateTime.now();
//     startDate = DateTime(now.year, now.month, 1);
//     endDate = now;
//
//     _loadTransactions();
//   }
//
//   Future<void> _loadTransactions() async {
//     if (!mounted) return;
//     setState(() => isLoading = true);
//
//     final data = await DBHelper.getAllTransactionsWithCustomers();
//
//     if (!mounted) return;
//     setState(() {
//       allTransactions = data;
//       _applyDateFilter();
//       isLoading = false;
//     });
//   }
//
//   DateTime? _parseDateSafely(String? dateStr) {
//     if (dateStr == null || dateStr.trim().isEmpty) return null;
//
//     try {
//       return DateTime.parse(dateStr);
//     } catch (e) {}
//
//     List<String> customFormats = [
//       "d-M-yyyy h:mm a",
//       "dd-MM-yyyy hh:mm a",
//       "yyyy-MM-dd hh:mm a",
//       "dd MMM yyyy, hh:mm a",
//       "yyyy-MM-dd HH:mm",
//       "yyyy-MM-dd",
//       "dd/MM/yyyy",
//     ];
//
//     for (String formatStr in customFormats) {
//       try {
//         return DateFormat(formatStr).parseLoose(dateStr);
//       } catch (e) {}
//     }
//     return null;
//   }
//
//   void _applyDateFilter() {
//     setState(() {
//       filteredTransactions = allTransactions.where((t) {
//         DateTime? txDate = _parseDateSafely(t['date']);
//         if (txDate == null) return false;
//
//         if (startDate != null && endDate != null) {
//           DateTime start = DateTime(startDate!.year, startDate!.month, startDate!.day, 0, 0, 0);
//           DateTime end = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);
//
//           return txDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
//           txDate.isBefore(end.add(const Duration(seconds: 1)));
//         }
//         return true;
//       }).toList();
//
//       _calculateTotal();
//     });
//   }
//
//   void _calculateTotal() {
//     totalAmount = 0.0;
//     for (var t in filteredTransactions) {
//       double amount = double.tryParse(t['amount'].toString()) ?? 0.0;
//       totalAmount += amount;
//     }
//   }
//
//   Future<void> _selectDate(BuildContext context, bool isStart) async {
//     DateTime initialDate = isStart ? (startDate ?? DateTime.now()) : (endDate ?? DateTime.now());
//
//     final DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: initialDate,
//       firstDate: DateTime(2000),
//       lastDate: DateTime(2100),
//       builder: (context, child) {
//         return Theme(
//           data: Theme.of(context).copyWith(
//             colorScheme: const ColorScheme.light(
//               primary: Colors.deepOrange,
//               onPrimary: Colors.white,
//               onSurface: Colors.black87,
//             ),
//           ),
//           child: child!,
//         );
//       },
//     );
//
//     if (picked != null) {
//       setState(() {
//         if (isStart) {
//           startDate = picked;
//           if (endDate != null && endDate!.isBefore(startDate!)) {
//             endDate = startDate;
//           }
//         } else {
//           endDate = picked;
//           if (startDate != null && startDate!.isAfter(endDate!)) {
//             startDate = endDate;
//           }
//         }
//         _applyDateFilter();
//       });
//     }
//   }
//
//   String _formatDisplayDate(String isoDate) {
//     DateTime? date = _parseDateSafely(isoDate);
//     if (date == null) return isoDate;
//     return DateFormat('dd MMM, hh:mm a').format(date);
//   }
//
//   // 💰 Easy Money Formatter (e.g. 124810 -> 1,24,810)
//   String _formatMoney(double amount) {
//     final formatter = NumberFormat('#,##,##0.##', 'en_IN');
//     return formatter.format(amount);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xfff4f6fb),
//       appBar: AppBar(
//         backgroundColor: Colors.deepOrange,
//         elevation: 0,
//         toolbarHeight: 30, // Slightly shorter toolbar
//         centerTitle: true,
//         iconTheme: const IconThemeData(color: Colors.white),
//       ),
//       body: Column(
//         children: [
//           // ==========================================
//           // 📊 COMPACT TOP CARD
//           // ==========================================
//           Container(
//             width: double.infinity,
//             padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
//             decoration: const BoxDecoration(
//               gradient: LinearGradient(
//                 colors: [Colors.deepOrange, Color(0xFFFF8A65)],
//                 begin: Alignment.topCenter,
//                 end: Alignment.bottomCenter,
//               ),
//               borderRadius: BorderRadius.only(
//                 bottomLeft: Radius.circular(25),
//                 bottomRight: Radius.circular(25),
//               ),
//             ),
//             child: Column(
//               children: [
//                 Text(
//                   "আপনার এর মধ্যে আয় হয়েছে",
//                   style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 20, fontWeight: FontWeight.w500),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   "${_formatMoney(totalAmount)} টাকার",
//                   style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
//                 ),
//               ],
//             ),
//           ),
//
//           const SizedBox(height: 15),
//
//           // ==========================================
//           // 🗓️ DATE RANGE INPUTS
//           // ==========================================
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 12),
//             child: Row(
//               children: [
//                 Expanded(child: _buildDateInput("From", startDate, () => _selectDate(context, true))),
//                 const SizedBox(width: 8),
//                 Expanded(child: _buildDateInput("To", endDate, () => _selectDate(context, false))),
//               ],
//             ),
//           ),
//
//           const SizedBox(height: 12),
//
//           // ==========================================
//           // 📄 TRANSACTIONS LIST
//           // ==========================================
//           Expanded(
//             child: isLoading
//             ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
//             : filteredTransactions.isEmpty
//             ? _buildEmptyState()
//             : ListView.builder(
//               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//               physics: const BouncingScrollPhysics(),
//               itemCount: filteredTransactions.length,
//               itemBuilder: (context, index) {
//                 final t = filteredTransactions[index];
//                 final customerName = t['customerName'] ?? 'Unknown';
//             final note = t['note'] ?? '';
//             final amount = double.tryParse(t['amount'].toString()) ?? 0.0;
//
//             return Container(
//               margin: const EdgeInsets.only(bottom: 10),
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.circular(15),
//                 border: Border.all(color: Colors.grey.shade200),
//               ),
//               child: Padding(
//                 padding: const EdgeInsets.all(12.0),
//                 child: Row(
//                   crossAxisAlignment: CrossAxisAlignment.start, // Align to top
//                   children: [
//                     // 👤 Mini Avatar
//                     Container(
//                       height: 40,
//                       width: 40,
//                       decoration: BoxDecoration(
//                         color: Colors.deepOrange.shade50,
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: Center(
//                         child: Text(
//                           customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
//                           style: TextStyle(color: Colors.deepOrange.shade700, fontWeight: FontWeight.bold, fontSize: 18),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//
//                     // 📝 Details (Expanded to take available space)
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             customerName,
//                             style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
//                           ),
//                           const SizedBox(height: 2),
//                           Text(
//                             _formatDisplayDate(t['date']),
//                             style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
//                           ),
//                           if (note.isNotEmpty)
//                             Padding(
//                               padding: const EdgeInsets.only(top: 6.0),
//                               child: Text(
//                                 note, // FULL TEXT SHOWN HERE
//                                 style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13, height: 1.3),
//                               ),
//                             ),
//                         ],
//                       ),
//                     ),
//
//                     const SizedBox(width: 8),
//
//                     // 💰 Amount (Fixed size logic prevents overlap)
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//                       decoration: BoxDecoration(
//                         color: Colors.green.shade50,
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: Text(
//                         "${_formatMoney(amount)} ₹",
//                         style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 14),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildEmptyState() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(Icons.history_rounded, size: 50, color: Colors.grey.shade300),
//           const SizedBox(height: 10),
//           Text("No records found", style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildDateInput(String label, DateTime? selectedDate, VoidCallback onTap) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(12),
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(color: Colors.deepOrange.withOpacity(0.2)),
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold)),
//             const SizedBox(height: 2),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text(
//                   selectedDate != null ? DateFormat('dd MMM yy').format(selectedDate) : 'Date',
//                   style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
//                 ),
//                 const Icon(Icons.calendar_today, color: Colors.deepOrange, size: 14),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart'; // Adjust path if needed

class TransactionHistoryPage extends StatefulWidget {
  @override
  _TransactionHistoryPageState createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  List<Map<String, dynamic>> allTransactions = [];
  List<Map<String, dynamic>> filteredTransactions = [];
  bool isLoading = true;

  double totalAmount = 0.0;

  // Date Range Variables
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();

    // Default Filter: From 1st of the Current Month to Today
    DateTime now = DateTime.now();
    startDate = DateTime(now.year, now.month, 1);
    endDate = now;

    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final data = await DBHelper.getAllTransactionsWithCustomers();

    if (!mounted) return;
    setState(() {
      allTransactions = data;
      _applyDateFilter();
      isLoading = false;
    });
  }

  DateTime? _parseDateSafely(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;

    try {
      return DateTime.parse(dateStr);
    } catch (e) {}

    List<String> customFormats = [
      "d-M-yyyy h:mm a",
      "dd-MM-yyyy hh:mm a",
      "yyyy-MM-dd hh:mm a",
      "dd MMM yyyy, hh:mm a",
      "yyyy-MM-dd HH:mm",
      "yyyy-MM-dd",
      "dd/MM/yyyy",
    ];

    for (String formatStr in customFormats) {
      try {
        return DateFormat(formatStr).parseLoose(dateStr);
      } catch (e) {}
    }
    return null;
  }

  void _applyDateFilter() {
    setState(() {
      filteredTransactions = allTransactions.where((t) {
        DateTime? txDate = _parseDateSafely(t['date']);
        if (txDate == null) return false;

        if (startDate != null && endDate != null) {
          DateTime start = DateTime(startDate!.year, startDate!.month, startDate!.day, 0, 0, 0);
          DateTime end = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);

          return txDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
          txDate.isBefore(end.add(const Duration(seconds: 1)));
        }
        return true;
      }).toList();

      // 🔥 ADDED SORTING LOGIC HERE 🔥
      // This sorts the list from newest date (top) to oldest date (bottom)
      filteredTransactions.sort((a, b) {
        DateTime dateA = _parseDateSafely(a['date']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        DateTime dateB = _parseDateSafely(b['date']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA); // b compared to a puts newest first
      });

      _calculateTotal();
    });
  }

  void _calculateTotal() {
    totalAmount = 0.0;
    for (var t in filteredTransactions) {
      double amount = double.tryParse(t['amount'].toString()) ?? 0.0;
      totalAmount += amount;
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    DateTime initialDate = isStart ? (startDate ?? DateTime.now()) : (endDate ?? DateTime.now());

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.deepOrange,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          startDate = picked;
          if (endDate != null && endDate!.isBefore(startDate!)) {
            endDate = startDate;
          }
        } else {
          endDate = picked;
          if (startDate != null && startDate!.isAfter(endDate!)) {
            startDate = endDate;
          }
        }
        _applyDateFilter();
      });
    }
  }

  String _formatDisplayDate(String isoDate) {
    DateTime? date = _parseDateSafely(isoDate);
    if (date == null) return isoDate;
    return DateFormat('dd MMM, hh:mm a').format(date);
  }

  // 💰 Easy Money Formatter (e.g. 124810 -> 1,24,810)
  String _formatMoney(double amount) {
    final formatter = NumberFormat('#,##,##0.##', 'en_IN');
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        toolbarHeight: 30, // Slightly shorter toolbar
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ==========================================
          // 📊 COMPACT TOP CARD
          // ==========================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepOrange, Color(0xFFFF8A65)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(25),
                bottomRight: Radius.circular(25),
              ),
            ),
            child: Column(
              children: [
                Text(
                  "আপনার এর মধ্যে আয় হয়েছে",
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 20, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  "${_formatMoney(totalAmount)} টাকার",
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),

          const SizedBox(height: 15),

          // ==========================================
          // 🗓️ DATE RANGE INPUTS
          // ==========================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: _buildDateInput("From", startDate, () => _selectDate(context, true))),
                const SizedBox(width: 8),
                Expanded(child: _buildDateInput("To", endDate, () => _selectDate(context, false))),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ==========================================
          // 📄 TRANSACTIONS LIST
          // ==========================================
          Expanded(
            child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
            : filteredTransactions.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              physics: const BouncingScrollPhysics(),
              itemCount: filteredTransactions.length,
              itemBuilder: (context, index) {
                final t = filteredTransactions[index];
                final customerName = t['customerName'] ?? 'Unknown';
            final note = t['note'] ?? '';
            final amount = double.tryParse(t['amount'].toString()) ?? 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start, // Align to top
                  children: [
                    // 👤 Mini Avatar
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
                          style: TextStyle(color: Colors.deepOrange.shade700, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 📝 Details (Expanded to take available space)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDisplayDate(t['date']),
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                          if (note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                note, // FULL TEXT SHOWN HERE
                                style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13, height: 1.3),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 💰 Amount (Fixed size logic prevents overlap)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "${_formatMoney(amount)} ₹",
                        style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 50, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text("No records found", style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDateInput(String label, DateTime? selectedDate, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.deepOrange.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedDate != null ? DateFormat('dd MMM yy').format(selectedDate) : 'Date',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.calendar_today, color: Colors.deepOrange, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
