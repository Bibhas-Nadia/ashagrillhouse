
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';

class ViewReport extends StatefulWidget {
  @override
  _ViewReportState createState() => _ViewReportState();
}

class _ViewReportState extends State<ViewReport> {
  bool _isLoading = true;

  // 🕒 Time Filter Variables
  final int _currentYear = DateTime.now().year;
  int _selectedYear = DateTime.now().year;
  int? _selectedMonth = DateTime.now().month; // Default: Current Month
  int? _selectedDay = null;                  // Default: All Days

  final List<String> _monthNames = [
    'সব মাস', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // 📊 Dashboard Data
  double _totalRevenue = 0.0;
  double _totalSpends = 0.0;
  double _totalDueInPeriod = 0.0;
  double _totalDueAllTime = 0.0;
  double _netProfit = 0.0;

  // Chart Data Setup
  List<FlSpot> _revenueSpots = [];
  List<FlSpot> _expenseSpots = [];
  List<FlSpot> _dueSpots = [];

  int _startX = 1;
  int _endX = 31;
  double _maxY = 100.0;

  // Limited Transaction Lists (Max 10 Income + 10 Spend)
  List<Map<String, dynamic>> _limitedIncomeList = [];
  List<Map<String, dynamic>> _limitedExpenseList = [];

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  // 💰 Indian Standard Comma Formatter (e.g., 150000 -> 1,50,000)
  String _formatMoney(double amount) {
    final formatter = NumberFormat('#,##,##0.##', 'en_IN');
    return formatter.format(amount);
  }

  int _getDaysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  // 🛠️ Safe Date Parser
  DateTime _parseDateSafely(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return DateTime.now();
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}
    try {
      String cleanDate = dateStr.replaceAll('/', '-');
      var parts = cleanDate.split(' ')[0].split('-');
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        } else {
          return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        }
      }
    } catch (_) {}
    return DateTime.now();
  }













  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);

    try {
      final dbClient = await DBHelper.db;
      final allTxns = await dbClient.query('transactions');
      final allCustomers = await dbClient.query('customers');
      final allExpenses = await dbClient.query('expenses');

      _totalRevenue = 0.0;
      _totalSpends = 0.0;
      _totalDueInPeriod = 0.0;
      _totalDueAllTime = 0.0;

      Map<int, double> revMap = {};
      Map<int, double> expMap = {};
      Map<int, double> dueMap = {};

      List<Map<String, dynamic>> tempAllIncome = [];
      List<Map<String, dynamic>> tempAllExpense = [];
      Map<int, String> customerNamesMap = {};

      // Calculate Total Market Due (All time global market outstandings)
      // for (var c in allCustomers) {
      //   int id = c['id'] as int;
      //   customerNamesMap[id] = c['name'].toString();
      //   _totalDueAllTime += double.tryParse(c['due'].toString()) ?? 0.0;
      // }

      // Calculate Total Market Due (All time global market outstandings)
      for (var c in allCustomers) {
        int id = c['id'] as int;
        customerNamesMap[id] = c['name'].toString();
      }


      // Filter Logic
      bool isInPeriod(DateTime date) {
        if (date.year != _selectedYear) return false;
        if (_selectedMonth != null && date.month != _selectedMonth) return false;
        if (_selectedDay != null && date.day != _selectedDay) return false;
        return true;
      }

      int getXValue(DateTime date) {
        if (_selectedMonth == null) return date.month;
        if (_selectedDay == null) return date.day;
        return date.hour;
      }

      // 1. Process Income (Transactions)
      for (var t in allTxns) {
        DateTime dt = _parseDateSafely(t['date'].toString());
        if (isInPeriod(dt)) {
          double amt = double.tryParse(t['amount'].toString()) ?? 0.0;
          _totalRevenue += amt;
          int x = getXValue(dt);
          revMap[x] = (revMap[x] ?? 0) + amt;

          int cId = int.tryParse(t['customerId'].toString()) ?? 0;
          tempAllIncome.add({
            'title': customerNamesMap[cId] ?? 'গ্রাহক লেনদেন',
            'amount': amt,
            'dateStr': t['date'].toString(),
            'dateObj': dt
          });
        }
      }

      // 2. Process Expenses
      for (var e in allExpenses) {
        DateTime dt = _parseDateSafely(e['date'].toString());
        if (isInPeriod(dt)) {
          double amt = double.tryParse(e['amount'].toString()) ?? 0.0;
          _totalSpends += amt;
          int x = getXValue(dt);
          expMap[x] = (expMap[x] ?? 0) + amt;

          tempAllExpense.add({
            'title': e['title'] ?? 'অন্যান্য খরচ',
            'amount': amt,
            'dateStr': e['date'].toString(),
            'dateObj': dt
          });
        }
      }

      // 3. Process Customers Due creation timeline
      // for (var c in allCustomers) {
      //   DateTime dt = _parseDateSafely(c['createdAt'].toString());
      //   if (isInPeriod(dt)) {
      //     double due = double.tryParse(c['due'].toString()) ?? 0.0;
      //     if (due > 0) {
      //       _totalDueInPeriod += due;
      //       int x = getXValue(dt);
      //       dueMap[x] = (dueMap[x] ?? 0) + due;
      //     }
      //   }
      // }

      // 3. Process Customers Due creation timeline
      for (var c in allCustomers) {
        DateTime dt = _parseDateSafely(c['createdAt'].toString());
        if (isInPeriod(dt)) { // 🟢 সময়/তারিখ অনুযায়ী ফিল্টার হচ্ছে
          double due = double.tryParse(c['due'].toString()) ?? 0.0;
          if (due > 0) {
            _totalDueInPeriod += due;
            _totalDueAllTime += due; // 🟢 ড্যাশবোর্ডে দেখানোর জন্য শুধু নির্বাচিত সময়ের বকেয়া যোগ করা হলো
            int x = getXValue(dt);
            dueMap[x] = (dueMap[x] ?? 0) + due;
          }
        }
      }



      _netProfit = _totalRevenue - _totalSpends;

      // Limit lists to latest 10 items only
      tempAllIncome.sort((a, b) => b['dateObj'].compareTo(a['dateObj']));
      tempAllExpense.sort((a, b) => b['dateObj'].compareTo(a['dateObj']));
      _limitedIncomeList = tempAllIncome.take(10).toList();
      _limitedExpenseList = tempAllExpense.take(10).toList();

      // Configure X-Axis boundaries
      if (_selectedMonth == null) {
        _startX = 1; _endX = 12;
      } else if (_selectedDay == null) {
        _startX = 1; _endX = _getDaysInMonth(_selectedYear, _selectedMonth!);
      } else {
        _startX = 0; _endX = 23;
      }

      // Populate Chart Spots securely to avoid any rendering bugs
      _revenueSpots = [];
      _expenseSpots = [];
      _dueSpots = [];
      double highestPeak = 100.0;

      for (int i = _startX; i <= _endX; i++) {
        double r = revMap[i] ?? 0.0;
        double e = expMap[i] ?? 0.0;
        double d = dueMap[i] ?? 0.0;

        _revenueSpots.add(FlSpot(i.toDouble(), r));
        _expenseSpots.add(FlSpot(i.toDouble(), e));
        _dueSpots.add(FlSpot(i.toDouble(), d));

        if (r > highestPeak) highestPeak = r;
        if (e > highestPeak) highestPeak = e;
        if (d > highestPeak) highestPeak = d;
      }

      _maxY = highestPeak * 1.25;

    } catch (e) {
      debugPrint("Error loading report: $e");
    }

    setState(() => _isLoading = false);
  }












  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange.shade50,
      appBar: AppBar(
        title: const Text('রিপোর্ট এবং অ্যানালিটিক্স', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
          elevation: 2,
      ),
      body: _isLoading
      ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
      : RefreshIndicator(
        onRefresh: _loadReportData,
        color: Colors.deepOrange,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAdvancedFilters(),
              const SizedBox(height: 14),
              _buildSmartFinancialBanner(),
              const SizedBox(height: 14),
              _buildMetricsGrid(),
              const SizedBox(height: 20),
              _buildChart1_Line(),
              const SizedBox(height: 20),
              _buildChart2_DueTrend(),
              const SizedBox(height: 20),
              _buildChart3_SummaryBar(),
              const SizedBox(height: 24),
              _buildSplitTransactionLists(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGET BUILDERS
  // ===========================================================================

  Widget _buildAdvancedFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepOrange.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Year Picker
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedYear,
                      isExpanded: true,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                      items: List.generate(5, (index) {
                        int year = _currentYear - index;
                        return DropdownMenuItem(value: year, child: Text("$year সাল"));
                      }),
                      onChanged: (val) {
                        setState(() {
                          _selectedYear = val!;
                        });
                        _loadReportData();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Month Picker
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedMonth ?? 0,
                      isExpanded: true,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                      items: List.generate(13, (index) {
                        return DropdownMenuItem(value: index, child: Text(_monthNames[index]));
                      }),
                      onChanged: (val) {
                        setState(() {
                          _selectedMonth = val == 0 ? null : val;
                          _selectedDay = null; // Reset day if month changes
                        });
                        _loadReportData();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_selectedMonth != null) ...[
            const SizedBox(height: 8),
            // Day Picker
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedDay ?? 0,
                  isExpanded: true,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text("সব দিন (All Days)")),
                    ...List.generate(_getDaysInMonth(_selectedYear, _selectedMonth!), (index) {
                      return DropdownMenuItem(value: index + 1, child: Text("${index + 1} তারিখ"));
                    })
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedDay = val == 0 ? null : val;
                    });
                    _loadReportData();
                  },
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildSmartFinancialBanner() {
    bool isProfit = _netProfit >= 0;
    String statusMessage = "";

    if (_netProfit > 0) {
      statusMessage = "এই নির্দিষ্ট সময়ে আপনি লাভজনক অবস্থানে আছেন। আপনার মোট লাভ ₹${_formatMoney(_netProfit)} টাকা।";
    } else if (_netProfit < 0) {
      statusMessage = "এই নির্দিষ্ট সময়ে আপনার লোকসান বা ক্ষতি হয়েছে। আপনার মোট ক্ষতি ₹${_formatMoney(_netProfit.abs())} টাকা।";
    } else {
      statusMessage = "এই নির্দিষ্ট সময়ে ব্যবসায় কোনো লাভ বা লোকসান হয়নি।";
    }

    if (_totalDueAllTime > 0) {
      statusMessage += " \n⚠️ মার্কেটে বকেয়া টাকা আছে, দ্রুত তা তোলার চেষ্টা করুন।";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isProfit ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isProfit ? Colors.green.shade300 : Colors.orange.shade300, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isProfit ? Icons.check_circle_rounded : Icons.info_rounded,
            color: isProfit ? Colors.green.shade700 : Colors.deepOrange,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              statusMessage,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isProfit ? Colors.green.shade900 : Colors.red.shade900,
                height: 1.4
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      childAspectRatio: 1.3,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMetricBox("মোট আয়", _totalRevenue, Colors.green.shade700, Icons.arrow_downward),
        _buildMetricBox("মোট খরচ", _totalSpends, Colors.red.shade700, Icons.arrow_upward),
        _buildMetricBox("নিট লাভ/ক্ষতি", _netProfit, Colors.blue.shade700, Icons.account_balance_wallet),
        _buildMetricBox("সর্বমোট বকেয়া", _totalDueAllTime, Colors.deepOrange, Icons.monetization_on_rounded),
      ],
    );
  }

  Widget _buildMetricBox(String title, double value, Color accentColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 18),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "₹${_formatMoney(value)}",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accentColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // --- CHART 1: LINE CHART FOR INCOME VS EXPENSE ---
  Widget _buildChart1_Line() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("১. আয় বনাম খরচ বিশ্লেষণ গ্রাফ", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildBulletDot("আয় (Income)", Colors.green),
              const SizedBox(width: 14),
              _buildBulletDot("খরচ (Expense)", Colors.red),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: ((_endX - _startX) / 5).clamp(1, 31).toDouble(),
                      getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: Colors.grey.shade300), left: BorderSide(color: Colors.grey.shade300))),
                minX: _startX.toDouble(), maxX: _endX.toDouble(),
                minY: 0, maxY: _maxY,
                lineBarsData: [
                  LineChartBarData(spots: _revenueSpots, isCurved: true, color: Colors.green, barWidth: 2.5, dotData: const FlDotData(show: false)),
                  LineChartBarData(spots: _expenseSpots, isCurved: true, color: Colors.red, barWidth: 2.5, dotData: const FlDotData(show: false)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- CHART 2: DUE TREND OVER TIME ---
  Widget _buildChart2_DueTrend() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("২. নতুন বকেয়া (Due) সৃষ্টির সময়সীমা গ্রাফ", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 4),
          _buildBulletDot("বকেয়ার পরিমাণ ট্রেন্ড", Colors.deepOrange),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: ((_endX - _startX) / 5).clamp(1, 31).toDouble(),
                      getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: Colors.grey.shade300), left: BorderSide(color: Colors.grey.shade300))),
                minX: _startX.toDouble(), maxX: _endX.toDouble(),
                minY: 0, maxY: _maxY,
                lineBarsData: [
                  LineChartBarData(spots: _dueSpots, isCurved: true, color: Colors.deepOrange, barWidth: 2.5, dotData: const FlDotData(show: false)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- CHART 3: TOTAL COMPARISON SUMMARY BAR CHART ---
  Widget _buildChart3_SummaryBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("৩. মোট আর্থিক অনুপাত (Summary Bar Chart)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 24),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: [_totalRevenue, _totalSpends, _totalDueAllTime].reduce((a, b) => a > b ? a : b) * 1.25 + 100,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        switch (value.toInt()) {
                          case 0: return const Text("আয়", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12));
                          case 1: return const Text("খরচ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12));
                          case 2: return const Text("বকেয়া", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12));
                        }
                        return const Text("");
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: _totalRevenue, color: Colors.green, width: 22, borderRadius: BorderRadius.circular(4))]),
                  BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: _totalSpends, color: Colors.red, width: 22, borderRadius: BorderRadius.circular(4))]),
                  BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: _totalDueAllTime, color: Colors.deepOrange, width: 22, borderRadius: BorderRadius.circular(4))]),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBulletDot(String label, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
      ],
    );
  }

  // --- TOP 10 INCOME AND TOP 10 EXPENSES SPLIT INTERFACE ---
  Widget _buildSplitTransactionLists() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Income Tab Label
        Text("সাম্প্রতিক আয় সমূহ (সর্বোচ্চ ১০টি)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
        const SizedBox(height: 6),
        if (_limitedIncomeList.isEmpty)
          _buildNoDataCard("কোনো আয়ের রেকর্ড পাওয়া যায়নি।")
          else
            ..._limitedIncomeList.map((item) => _buildTxnRow(item['title'], item['amount'], item['dateStr'], Colors.green)),

            const SizedBox(height: 20),

            // Expense Tab Label
            Text("সাম্প্রতিক খরচ সমূহ (সর্বোচ্চ ১০টি)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
            const SizedBox(height: 6),
            if (_limitedExpenseList.isEmpty)
              _buildNoDataCard("কোনো খরচের রেকর্ড পাওয়া যায়নি।")
              else
                ..._limitedExpenseList.map((item) => _buildTxnRow(item['title'], item['amount'], item['dateStr'], Colors.red)),
      ],
    );
  }

  Widget _buildTxnRow(String title, double amt, String date, Color txtColor) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        dense: true,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(date, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        trailing: Text(
          "${txtColor == Colors.green ? '+' : '-'} ₹${_formatMoney(amt)}",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: txtColor),
        ),
      ),
    );
  }

  Widget _buildNoDataCard(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Center(child: Text(msg, style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontStyle: FontStyle.italic))),
    );
  }
}
