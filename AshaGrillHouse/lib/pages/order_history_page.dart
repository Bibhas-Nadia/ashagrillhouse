import 'package:flutter/material.dart';
import '../db_helper.dart'; // Ensure this points to your DBHelper

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

  // Delete a single item (Optional, but good to have)
  Future<void> _deleteSingleOrder(int id) async {
    await DBHelper.deleteOrder(id);
    _loadHistory();
  }

  // Delete an entire section by looping through their IDs
  Future<void> _deleteGroup(String date, List<Map<String, dynamic>> items) async {
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Delete Order Group", style: TextStyle(fontWeight: FontWeight.bold)),
            content: Text(
              "Are you sure you want to delete all ${items.length} orders from:\n\n$date?",
              style: const TextStyle(fontSize: 18),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel", style: TextStyle(fontSize: 18))
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Delete All", style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
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
      backgroundColor: Colors.grey.shade200, // Slightly darker background to make cards pop
      appBar: AppBar(
        title: const Text("Order History", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _historyOrders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 100, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text("No previous orders found", style: TextStyle(fontSize: 22, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
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
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ==========================================
                      // SECTION HEADER (Date/Time & Group Delete)
                      // ==========================================
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade50,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                          border: Border(bottom: BorderSide(color: Colors.deepPurple.shade100, width: 2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_month, color: Colors.deepPurple, size: 28),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      date,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepPurple),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 🔴 DELETE ENTIRE GROUP BUTTON
                            IconButton(
                              icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 32),
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
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: items.map((order) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: ListTile(
                                leading: const Icon(Icons.check_circle, color: Colors.green),
                                title: Text(order['item'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  "${order['qty']} ${order['unit']}",
                                  style: TextStyle(fontSize: 18, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                                ),
                                // Individual delete button (Optional, you can remove this if you only want the group delete)
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.grey, size: 24),
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
