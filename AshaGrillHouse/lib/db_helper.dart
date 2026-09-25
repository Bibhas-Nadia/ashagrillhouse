



import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'models/customer.dart';
import 'models/measurement.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  static Future<Database> initDB() async {
    String path = p.join(await getDatabasesPath(), "customer.db");

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // 1. Customers Table
        await db.execute('''
        CREATE TABLE customers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          phone TEXT,
          address TEXT,
          due TEXT,
          images TEXT,
          createdAt TEXT
        )
        ''');

        // 2. Transactions Table
        await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER,
          amount TEXT,
          date TEXT,
          note TEXT
        )
        ''');

        // 3. Measurements Table
        await db.execute('''
        CREATE TABLE tempcustomer(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          phone TEXT,
          address TEXT,
          createdAt TEXT
        )
        ''');

        // 4. Detailed Measurements Table
        await db.execute('''
        CREATE TABLE measurements(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER,
          height TEXT,
          length TEXT,
          note TEXT,
          images TEXT,
          createdAt TEXT
        )
        ''');

        // 5. Store expenses
        await db.execute('''
        CREATE TABLE expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          amount TEXT,
          date TEXT
        )
        ''');

        // 6. Configuration Table
        await db.execute('''
        CREATE TABLE config (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          githubToken TEXT,
          githubUsername TEXT,
          githubRepo TEXT,
          appPassword TEXT,
          status TEXT
        )
        ''');

        // 7. Orders Table
        await db.execute('''
        CREATE TABLE orders(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item TEXT,
          qty TEXT,
          unit TEXT,
          date TEXT,
          status TEXT
        )
        ''');

        // 8. backup
        await db.execute('''
        CREATE TABLE backup (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          date TEXT,
          issue TEXT,
          status TEXT
        )
        ''');

        // 9. Messages table
        await db.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER,
          message TEXT,
          date TEXT
        )
        ''');

        // 10. Pins table
        await db.execute('''
        CREATE TABLE IF NOT EXISTS pins (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER
        )
        ''');

        // 11. Price agreements
        await db.execute('''
        CREATE TABLE IF NOT EXISTS price_agreements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          measurementId INTEGER,
          priceListJson TEXT,
          sentMessage TEXT,
          createdAt TEXT
        )
        ''');

        // 12. Backup Settings Table
        await db.execute('''
        CREATE TABLE IF NOT EXISTS backup_settings (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          isEnabled INTEGER DEFAULT 0
        )
        ''');

        // 13. Receipt Calculations Table
        await db.execute('''
        CREATE TABLE IF NOT EXISTS receipt_calculations (
          customerId INTEGER PRIMARY KEY,
          calculationJson TEXT
        )
        ''');

        // 14. 🔥 EXPENSE KEYWORDS TABLE (NEW)
        await db.execute('''
        CREATE TABLE IF NOT EXISTS expense_keywords (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          keyword TEXT UNIQUE
        )
        ''');
      },
    );
  }

  // ==========================================
  // CUSTOMER OPERATIONS
  // ==========================================
  static Future<int> insert(Customer c) async {
    final dbClient = await db;
    return await dbClient.insert("customers", c.toMap());
  }

  static Future<List<Customer>> getCustomers() async {
    final dbClient = await db;
    final res = await dbClient.query("customers", orderBy: "id DESC");

    return res.map((e) => Customer(
      id: e['id'] as int,
      name: e['name'].toString(),
      phone: e['phone'].toString(),
      address: e['address'].toString(),
      due: e['due'].toString(),
      images: e['images'].toString(),
      createdAt: e['createdAt']?.toString() ?? "",
    )).toList();
  }

  // static Future deleteCustomerCompletely(int customerId) async {
  //   final dbClient = await db;
  //   await dbClient.delete("transactions", where: "customerId=?", whereArgs: [customerId]);
  //   await dbClient.delete("customers", where: "id=?", whereArgs: [customerId]);
  // }


  static Future deleteCustomerCompletely(int customerId) async {
    final dbClient = await db;

    // 1. Delete all Transactions
    await dbClient.delete("transactions", where: "customerId=?", whereArgs: [customerId]);

    // 2. Delete all Messages history
    await dbClient.delete("messages", where: "customerId=?", whereArgs: [customerId]);

    // 3. Delete from Pins (if pinned)
    await dbClient.delete("pins", where: "customerId=?", whereArgs: [customerId]);

    // 4. Delete saved Bill/Receipt Calculations
    await dbClient.delete("receipt_calculations", where: "customerId=?", whereArgs: [customerId]);

    // 5. Finally, delete the Customer record itself
    await dbClient.delete("customers", where: "id=?", whereArgs: [customerId]);
  }




  static Future<bool> customerExists(String name, String phone, String address) async {
    final dbClient = await db;
    final res = await dbClient.query(
      "customers",
      where: "name=? AND phone=? AND address=?",
      whereArgs: [name, phone, address],
    );
    return res.isNotEmpty;
  }

  static Future updateCustomerDue(int id, double newDue) async {
    final dbClient = await db;
    await dbClient.update("customers", {"due": newDue.toString()}, where: "id=?", whereArgs: [id]);
  }

  static Future updateCustomerImages(int id, String newImagesString) async {
    final dbClient = await db;
    await dbClient.update("customers", {"images": newImagesString}, where: "id=?", whereArgs: [id]);
  }

  static Future updateCustomerDetails(int id, String name, String phone, String address) async {
    final dbClient = await db;
    await dbClient.update("customers", {"name": name, "phone": phone, "address": address}, where: "id=?", whereArgs: [id]);
  }

  // ==========================================
  // TRANSACTION OPERATIONS
  // ==========================================
  static Future insertTransaction(int customerId, String amount, String date, String note) async {
    final dbClient = await db;
    await dbClient.insert("transactions", {"customerId": customerId, "amount": amount, "date": date, "note": note});
  }

  static Future<List<Map<String, dynamic>>> getTransactions(int customerId) async {
    final dbClient = await db;
    return await dbClient.query("transactions", where: "customerId = ?", whereArgs: [customerId], orderBy: "id DESC");
  }

  static Future deleteTransaction(int id) async {
    final dbClient = await db;
    await dbClient.delete("transactions", where: "id = ?", whereArgs: [id]);
  }

  // ==========================================
  // CUSTOMER FOR MEASUREMENT OPERATIONS
  // ==========================================
  static Future<int> insertMeasurement(Measurement m) async {
    final dbClient = await db;
    return await dbClient.insert("tempcustomer", m.toMap());
  }

  static Future<List<Measurement>> getMeasurements() async {
    final dbClient = await db;
    final res = await dbClient.query("tempcustomer", orderBy: "id DESC");

    return res.map((e) => Measurement(
      id: e['id'] as int,
      name: e['name'].toString(),
      phone: e['phone'].toString(),
      address: e['address'].toString(),
      createdAt: e['createdAt']?.toString() ?? "",
    )).toList();
  }

  static Future deleteMeasurement(int id) async {
    final dbClient = await db;
    await dbClient.delete("tempcustomer", where: "id=?", whereArgs: [id]);
  }

  static Future updateMeasurementImages(int id, String newImagesString) async {
    final dbClient = await db;
    await dbClient.update("tempcustomer", {"images": newImagesString}, where: "id=?", whereArgs: [id]);
  }

  // ==========================================
  // DETAILED MEASUREMENT OPERATIONS
  // ==========================================
  static Future<int> insertDetailedMeasurement(Map<String, dynamic> data) async {
    final dbClient = await db;
    return await dbClient.insert("measurements", data);
  }

  static Future<List<Map<String, dynamic>>> getDetailedMeasurements(int customerId) async {
    final dbClient = await db;
    return await dbClient.query("measurements", where: "customerId = ?", whereArgs: [customerId], orderBy: "id DESC");
  }

  static Future deleteDetailedMeasurement(int id) async {
    final dbClient = await db;
    await dbClient.delete("measurements", where: "id=?", whereArgs: [id]);
  }

  // ===============================================
  //   EXPENSES STORE METHODS
  // ===============================================
  static Future<int> insertExpense(Map<String, dynamic> data) async {
    final dbClient = await db;
    return await dbClient.insert("expenses", data);
  }

  static Future<List<Map<String, dynamic>>> getExpenses() async {
    final dbClient = await db;
    return await dbClient.query("expenses", orderBy: "id DESC");
  }

  static Future deleteExpense(int id) async {
    final dbClient = await db;
    await dbClient.delete("expenses", where: "id = ?", whereArgs: [id]);
  }

  // ===============================================
  // 🔥 EXPENSE KEYWORDS OPERATIONS (NEW)
  // ===============================================
  static Future<int> insertExpenseKeyword(String keyword) async {
    final dbClient = await db;
    // Create table inline just in case the database is already created without it
    await dbClient.execute('''
    CREATE TABLE IF NOT EXISTS expense_keywords (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      keyword TEXT UNIQUE
    )
    ''');
    return await dbClient.insert(
      "expense_keywords",
      {"keyword": keyword.trim()},
      conflictAlgorithm: ConflictAlgorithm.ignore, // prevents duplicates
    );
  }

  static Future<List<String>> getExpenseKeywords() async {
    final dbClient = await db;
    await dbClient.execute('''
    CREATE TABLE IF NOT EXISTS expense_keywords (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      keyword TEXT UNIQUE
    )
    ''');
    final res = await dbClient.query("expense_keywords", orderBy: "keyword ASC");
    return res.map((e) => e['keyword'].toString()).toList();
  }

  static Future deleteExpenseKeyword(String keyword) async {
    final dbClient = await db;
    await dbClient.delete("expense_keywords", where: "keyword = ?", whereArgs: [keyword]);
  }

  // ====================================================
  //  CONFIGURATION PAGE
  // ====================================================
  static Future<int> saveConfig(Map<String, dynamic> data) async {
    final dbClient = await db;
    data['id'] = 1;
    return await dbClient.insert("config", data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getConfig() async {
    final dbClient = await db;
    final List<Map<String, dynamic>> res = await dbClient.query("config", columns: ['githubToken', 'githubUsername', 'githubRepo'], where: "id = 1");
    return res.isNotEmpty ? res.first : null;
  }

  static Future<String?> getAppPassword() async {
    final dbClient = await db;
    final List<Map<String, dynamic>> res = await dbClient.query("config", columns: ['appPassword'], where: "id = 1");
    return res.isNotEmpty ? res.first['appPassword'] as String? : null;
  }

  static Future<String?> getStatus() async {
    final dbClient = await db;
    final List<Map<String, dynamic>> res = await dbClient.query("config", columns: ['status'], where: "id = 1");
    return res.isNotEmpty ? res.first['status'] as String? : null;
  }

  // ==========================================
  // ORDER OPERATIONS
  // ==========================================
  static Future<int> insertOrder(Map<String, dynamic> data) async {
    final dbClient = await db;
    return await dbClient.insert("orders", data);
  }

  static Future<List<Map<String, dynamic>>> getPendingOrders() async {
    final dbClient = await db;
    return await dbClient.query("orders", where: "status = ?", whereArgs: ["pending"], orderBy: "id DESC");
  }

  static Future<List<Map<String, dynamic>>> getHistoryOrders() async {
    final dbClient = await db;
    return await dbClient.query("orders", where: "status = ?", whereArgs: ["sent"], orderBy: "id DESC");
  }

  static Future sendOrders() async {
    final dbClient = await db;
    DateTime now = DateTime.now();
    String formattedDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour > 12 ? now.hour - 12 : now.hour}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}";
    await dbClient.update("orders", {"status": "sent", "date": formattedDate}, where: "status = ?", whereArgs: ["pending"]);
  }

  static Future deleteOrder(int id) async {
    final dbClient = await db;
    await dbClient.delete("orders", where: "id = ?", whereArgs: [id]);
  }

  static Future clearOrderHistory() async {
    final dbClient = await db;
    await dbClient.delete("orders", where: "status = ?", whereArgs: ["sent"]);
  }

  // ==========================================
  // BACKUP FUNCTIONS
  // ==========================================
  static Future<int> logBackupStatus(String date, String issue, String status) async {
    final dbClient = await db;
    return await dbClient.insert("backup", {"id": 1, "date": date, "issue": issue, "status": status}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getBackupStatus() async {
    final dbClient = await db;
    final res = await dbClient.query("backup", where: "id = 1");
    if (res.isNotEmpty) return res.first;
    return null;
  }

  static Future<List<Map<String, dynamic>>> getAllTransactionsWithCustomers() async {
    final dbClient = await db;
    return await dbClient.rawQuery('''
    SELECT t.id, t.amount, t.date, t.note, c.name as customerName
    FROM transactions t
    LEFT JOIN customers c ON t.customerId = c.id
    ORDER BY t.date DESC
    ''');
  }

  // ==========================================
  // MESSAGES TRACK TABLES FUNCTIONS
  // ==========================================
  static Future insertMessage(int customerId, String message, String date) async {
    final dbClient = await db;
    await dbClient.insert("messages", {"customerId": customerId, "message": message, "date": date});
  }

  static Future<List<Map<String, dynamic>>> getMessages(int customerId) async {
    final dbClient = await db;
    return await dbClient.query("messages", where: "customerId = ?", whereArgs: [customerId], orderBy: "id DESC");
  }

  static Future deleteMessage(int id) async {
    final dbClient = await db;
    await dbClient.delete("messages", where: "id = ?", whereArgs: [id]);
  }

  // ==========================================
  // PIN OPERATIONS
  // ==========================================
  static Future<int> getPinCount() async {
    final dbClient = await db;
    final res = await dbClient.rawQuery("SELECT COUNT(*) FROM pins");
    return Sqflite.firstIntValue(res) ?? 0;
  }

  static Future<bool> isCustomerPinned(int customerId) async {
    final dbClient = await db;
    final res = await dbClient.query("pins", where: "customerId = ?", whereArgs: [customerId]);
    return res.isNotEmpty;
  }

  static Future<bool> pinCustomer(int customerId) async {
    final dbClient = await db;
    int count = await getPinCount();
    if (count >= 3) return false;
    await dbClient.insert("pins", {"customerId": customerId});
    return true;
  }

  static Future unpinCustomer(int customerId) async {
    final dbClient = await db;
    await dbClient.delete("pins", where: "customerId = ?", whereArgs: [customerId]);
  }

  // ========================================
  // PRICE AGREEMENTS
  // ========================================
  static Future<void> insertPriceAgreement({required int measurementId, required String priceListJson, required String sentMessage}) async {
    final dbClient = await db;
    String now = DateTime.now().toIso8601String();
    await dbClient.insert('price_agreements', {'measurementId': measurementId, 'priceListJson': priceListJson, 'sentMessage': sentMessage, 'createdAt': now});
  }

  static Future<Map<String, dynamic>?> getPriceAgreement(int measurementId) async {
    final dbClient = await db;
    final List<Map<String, dynamic>> maps = await dbClient.query('price_agreements', where: 'measurementId = ?', whereArgs: [measurementId], orderBy: 'id DESC', limit: 1);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  static Future<void> deletePriceAgreement(int measurementId) async {
    final dbClient = await db;
    await dbClient.delete('price_agreements', where: 'measurementId = ?', whereArgs: [measurementId]);
  }

  // ==========================================
  // DATABASE STUDIO
  // ==========================================
  static Future<List<String>> getAllTableNames() async {
    final dbClient = await db;
    final res = await dbClient.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    return res.map((e) => e['name'] as String).toList();
  }

  static Future<List<Map<String, dynamic>>> getTableStructure(String tableName) async {
    final dbClient = await db;
    return await dbClient.rawQuery("PRAGMA table_info($tableName)");
  }

  static Future<dynamic> executeRawQuery(String query) async {
    final dbClient = await db;
    String lowerQuery = query.trim().toLowerCase();
    try {
      if (lowerQuery.startsWith("select") || lowerQuery.startsWith("pragma")) {
        return await dbClient.rawQuery(query);
      } else if (lowerQuery.startsWith("insert")) {
        int id = await dbClient.rawInsert(query);
        return "Success: Inserted row ID $id";
      } else if (lowerQuery.startsWith("update") || lowerQuery.startsWith("delete")) {
        int rows = await dbClient.rawUpdate(query);
        return "Success: $rows rows affected.";
      } else {
        await dbClient.execute(query);
        return "Success: Command executed.";
      }
    } catch (e) {
      return "Error: ${e.toString()}";
    }
  }

  // ==========================================
  // BACKUP TOGGLE OPERATIONS
  // ==========================================
  static Future<int> setBackupEnabled(bool enabled) async {
    final dbClient = await db;
    return await dbClient.insert("backup_settings", {"id": 1, "isEnabled": enabled ? 1 : 0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<bool> isBackupEnabled() async {
    final dbClient = await db;
    final res = await dbClient.query("backup_settings", where: "id = 1");
    if (res.isNotEmpty) return res.first['isEnabled'] == 1;
    return false;
  }

  // ==========================================
  // RECEIPT CALCULATION PERSISTENCE
  // ==========================================
  static Future<void> saveReceiptCalculation(int customerId, String jsonStr) async {
    final dbClient = await db;
    await dbClient.execute('''
    CREATE TABLE IF NOT EXISTS receipt_calculations (
      customerId INTEGER PRIMARY KEY,
      calculationJson TEXT
    )
    ''');
    await dbClient.insert("receipt_calculations", {"customerId": customerId, "calculationJson": jsonStr}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> getReceiptCalculation(int customerId) async {
    final dbClient = await db;
    await dbClient.execute('''
    CREATE TABLE IF NOT EXISTS receipt_calculations (
      customerId INTEGER PRIMARY KEY,
      calculationJson TEXT
    )
    ''');
    final res = await dbClient.query("receipt_calculations", where: "customerId = ?", whereArgs: [customerId]);
    if (res.isNotEmpty) return res.first['calculationJson'] as String?;
    return null;
  }

  static Future<double> getCustomerDue(int customerId) async {
    final dbClient = await db;
    final res = await dbClient.query("customers", columns: ["due"], where: "id = ?", whereArgs: [customerId]);
    if (res.isNotEmpty && res.first['due'] != null) return double.tryParse(res.first['due'].toString()) ?? 0.0;
    return 0.0;
  }
}
