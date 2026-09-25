import 'package:flutter/material.dart';
import '../db_helper.dart';

class DbStudioPage extends StatefulWidget {
  const DbStudioPage({Key? key}) : super(key: key);

  @override
  _DbStudioPageState createState() => _DbStudioPageState();
}

class _DbStudioPageState extends State<DbStudioPage> {
  bool isAuthenticated = false;
  bool isCheckingPin = false;
  final TextEditingController _pinController = TextEditingController();

  // Studio State
  List<String> tableNames = [];
  String? selectedTable;
  List<Map<String, dynamic>> tableStructure = [];

  final TextEditingController _queryController = TextEditingController();
  dynamic queryResult;
  bool isExecuting = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  // =====================================
  // AUTHENTICATION LOGIC
  // =====================================
  Future<void> _verifyPin() async {
    setState(() => isCheckingPin = true);

    String enteredPin = _pinController.text.trim();
    String? storedPassword = await DBHelper.getAppPassword();

    // If no password is set in DB, allow access or set a default behavior.
    // For now, we strictly check against stored password.
    if (storedPassword == null) {
      storedPassword = "123456";
    }

    if (enteredPin == storedPassword) {
      setState(() {
        isAuthenticated = true;
        isCheckingPin = false;
      });
      _loadTables();
    } else {
      setState(() {
        isCheckingPin = false;
        _pinController.clear();
      });
      _showError("Incorrect PIN");
    }
  }

  // =====================================
  // STUDIO LOGIC
  // =====================================
  Future<void> _loadTables() async {
    final tables = await DBHelper.getAllTableNames();
    setState(() {
      tableNames = tables;
      if (tables.isNotEmpty) {
        selectedTable = tables.first;
        _loadTableStructure(tables.first);
      }
    });
  }

  Future<void> _loadTableStructure(String tableName) async {
    final structure = await DBHelper.getTableStructure(tableName);
    setState(() {
      tableStructure = structure;
      // Provide a quick select query template
      _queryController.text = "SELECT * FROM $tableName LIMIT 50;";
      queryResult = null;
    });
  }

  Future<void> _runQuery() async {
    String query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() => isExecuting = true);

    final result = await DBHelper.executeRawQuery(query);

    setState(() {
      queryResult = result;
      isExecuting = false;
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // =====================================
  // UI BUILDERS
  // =====================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C), // Dark developer theme
      appBar: AppBar(
        title: const Text("Internal DB Studio", style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
        backgroundColor: const Color(0xFF252538),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: isAuthenticated ? _buildStudioView() : _buildAuthView(),
    );
  }

  // --- 1. LOGIN SCREEN ---
  Widget _buildAuthView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.admin_panel_settings, size: 80, color: Colors.greenAccent),
            const SizedBox(height: 24),
            const Text(
              "Developer Access Restricted",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Enter the 6-digit App Password to continue.",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF252538),
                counterText: "",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                hintText: "••••••",
                hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 8),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isCheckingPin ? null : _verifyPin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isCheckingPin
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("AUTHENTICATE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- 2. MAIN STUDIO VIEW ---
  Widget _buildStudioView() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.greenAccent,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.greenAccent,
            tabs: [
              Tab(icon: Icon(Icons.schema), text: "Tables & Schema"),
              Tab(icon: Icon(Icons.code), text: "SQL Editor"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSchemaTab(),
                _buildSqlEditorTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- SCHEMA TAB ---
  Widget _buildSchemaTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Select Table:", style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: const Color(0xFF252538), borderRadius: BorderRadius.circular(8)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedTable,
                dropdownColor: const Color(0xFF252538),
                isExpanded: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                items: tableNames.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => selectedTable = val);
                    _loadTableStructure(val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text("Structure for '$selectedTable':", style: const TextStyle(color: Colors.greenAccent, fontSize: 16)),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(const Color(0xFF252538)),
                    columns: const [
                      DataColumn(label: Text("CID", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text("Name", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text("Type", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text("PK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    ],
                    rows: tableStructure.map((col) => DataRow(
                      cells: [
                        DataCell(Text(col['cid'].toString(), style: const TextStyle(color: Colors.grey))),
                        DataCell(Text(col['name'].toString(), style: const TextStyle(color: Colors.white))),
                        DataCell(Text(col['type'].toString(), style: const TextStyle(color: Colors.amber))),
                        DataCell(Text(col['pk'] == 1 ? 'YES' : '', style: const TextStyle(color: Colors.greenAccent))),
                      ]
                    )).toList(),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- SQL EDITOR TAB ---
  Widget _buildSqlEditorTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF252538), borderRadius: BorderRadius.circular(8)),
            child: TextField(
              controller: _queryController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: "SELECT * FROM customers;\nINSERT INTO...\nUPDATE...",
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: isExecuting ? null : _runQuery,
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              label: const Text("RUN QUERY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.shade700),
            ),
          ),
          const SizedBox(height: 16),
          const Text("Results:", style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 8),
          Expanded(child: _buildResultsView()),
        ],
      ),
    );
  }

  // --- RENDER RESULTS ---
  Widget _buildResultsView() {
    if (isExecuting) return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
    if (queryResult == null) return const Center(child: Text("No results yet.", style: TextStyle(color: Colors.white24)));

    if (queryResult is String) {
      // It's an error or success message
      bool isError = queryResult.toString().startsWith("Error");
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isError ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isError ? Colors.red : Colors.greenAccent),
        ),
        child: Text(queryResult, style: TextStyle(color: isError ? Colors.redAccent : Colors.greenAccent, fontFamily: 'monospace')),
      );
    }

    if (queryResult is List<Map<String, dynamic>>) {
      List<Map<String, dynamic>> rows = queryResult;
      if (rows.isEmpty) return const Center(child: Text("0 Rows returned.", style: TextStyle(color: Colors.white54)));

      List<String> columns = rows.first.keys.toList();

      return Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(const Color(0xFF252538)),
              columns: columns.map((col) => DataColumn(label: Text(col, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)))).toList(),
              rows: rows.map((row) => DataRow(
                cells: columns.map((col) => DataCell(Text(row[col]?.toString() ?? 'NULL', style: const TextStyle(color: Colors.white)))).toList(),
              )).toList(),
            ),
          ),
        ),
      );
    }

    return const SizedBox();
  }
}
