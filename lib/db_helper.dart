import 'dart:convert';
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
      version: 3,
      onCreate: (db, version) async {

        await db.execute('''
        CREATE TABLE customers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          phone TEXT,
          address TEXT,
          due TEXT,
          images TEXT,
          createdAt TEXT,
          dueHistory TEXT
        )
        ''');

        await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER,
          amount TEXT,
          date TEXT,
          note TEXT
        )
        ''');

        await db.execute('''
        CREATE TABLE tempcustomer(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          phone TEXT,
          address TEXT,
          createdAt TEXT
        )
        ''');

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

        await db.execute('''
        CREATE TABLE expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          amount TEXT,
          date TEXT
        )
        ''');

        await db.execute('''
        CREATE TABLE config (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          googleScriptUrl TEXT,
          appPassword TEXT,
          status TEXT
        )
        ''');

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

        await db.execute('''
        CREATE TABLE backup (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          date TEXT,
          issue TEXT,
          status TEXT
        )
        ''');

        await db.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER,
          message TEXT,
          date TEXT
        )
        ''');

        await db.execute('''
        CREATE TABLE IF NOT EXISTS pins (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER
        )
        ''');

        await db.execute('''
        CREATE TABLE IF NOT EXISTS price_agreements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          measurementId INTEGER,
          priceListJson TEXT,
          sentMessage TEXT,
          createdAt TEXT
        )
        ''');

        await db.execute('''
        CREATE TABLE IF NOT EXISTS backup_settings (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          isEnabled INTEGER DEFAULT 0
        )
        ''');

        await db.execute('''
        CREATE TABLE IF NOT EXISTS receipt_calculations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER,
          calculationJson TEXT,
          datetime TEXT
        )
        ''');

        await db.execute('''
        CREATE TABLE IF NOT EXISTS expense_keywords (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          keyword TEXT UNIQUE
        )
        ''');
      },

      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE customers ADD COLUMN dueHistory TEXT DEFAULT '{}'");
        }
        if (oldVersion < 3) {
          await db.execute("DROP TABLE IF EXISTS config");
          await db.execute('''
          CREATE TABLE config (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            googleScriptUrl TEXT,
            appPassword TEXT,
            status TEXT
          )
          ''');
        }
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

  static Future deleteCustomerCompletely(int customerId) async {
    final dbClient = await db;
    await dbClient.delete("transactions", where: "customerId=?", whereArgs: [customerId]);
    await dbClient.delete("messages", where: "customerId=?", whereArgs: [customerId]);
    await dbClient.delete("pins", where: "customerId=?", whereArgs: [customerId]);
    await dbClient.delete("receipt_calculations", where: "customerId=?", whereArgs: [customerId]);
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
    final res = await dbClient.query("customers", columns: ["dueHistory"], where: "id=?", whereArgs: [id]);
    Map<String, dynamic> historyMap = {};

    if (res.isNotEmpty && res.first['dueHistory'] != null) {
      try {
        historyMap = jsonDecode(res.first['dueHistory'].toString());
      } catch (e) {
        print("Error parsing history: $e");
      }
    }

    DateTime dt = DateTime.now();
    String now = "${dt.day}-${dt.month}-${dt.year} ${dt.hour}:${dt.minute}:${dt.second}";

    historyMap[now] = newDue.toString();

    await dbClient.update("customers", {
      "due": newDue.toString(),
      "dueHistory": jsonEncode(historyMap)
    }, where: "id=?", whereArgs: [id]);
  }

  static Future<Map<String, dynamic>> getCustomerDueHistory(int id) async {
    final dbClient = await db;
    final res = await dbClient.query("customers", columns: ["dueHistory"], where: "id=?", whereArgs: [id]);
    if (res.isNotEmpty && res.first['dueHistory'] != null) {
      try {
        return jsonDecode(res.first['dueHistory'].toString());
      } catch (e) {
        return {};
      }
    }
    return {};
  }

  static Future deleteCustomerDueHistory(int id, String timestampKey) async {
    final dbClient = await db;
    final res = await dbClient.query("customers", columns: ["dueHistory"], where: "id=?", whereArgs: [id]);

    if (res.isNotEmpty && res.first['dueHistory'] != null) {
      try {
        Map<String, dynamic> historyMap = jsonDecode(res.first['dueHistory'].toString());
        if (historyMap.containsKey(timestampKey)) {
          historyMap.remove(timestampKey);
          await dbClient.update("customers", {
            "dueHistory": jsonEncode(historyMap)
          }, where: "id=?", whereArgs: [id]);
        }
      } catch (e) {
        print("Error deleting history: $e");
      }
    }
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
  // MEASUREMENT & TEMP CUSTOMER OPERATIONS
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
  // EXPENSES
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

  static Future<int> insertExpenseKeyword(String keyword) async {
    final dbClient = await db;
    return await dbClient.insert(
      "expense_keywords",
      {"keyword": keyword.trim()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<List<String>> getExpenseKeywords() async {
    final dbClient = await db;
    final res = await dbClient.query("expense_keywords", orderBy: "keyword ASC");
    return res.map((e) => e['keyword'].toString()).toList();
  }

  static Future deleteExpenseKeyword(String keyword) async {
    final dbClient = await db;
    await dbClient.delete("expense_keywords", where: "keyword = ?", whereArgs: [keyword]);
  }

  // ====================================================
  // CONFIGURATION METHODS
  // ====================================================
  static Future<int> saveConfig(Map<String, dynamic> data) async {
    final dbClient = await db;
    data['id'] = 1;
    return await dbClient.insert("config", data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getConfig() async {
    final dbClient = await db;
    final List<Map<String, dynamic>> res = await dbClient.query("config", columns: ['googleScriptUrl'], where: "id = 1");
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
  // ORDERS
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
  // MISC (BACKUP LOGS, MESSAGES, PINS)
  // ==========================================

  // 👈 FIX: Matches BackupService signature: (date, status, issue)
  static Future<int> saveBackupStatus(String date, String status, String issue) async {
    final dbClient = await db;
    return await dbClient.insert(
      "backup",
      {"id": 1, "date": date, "issue": issue, "status": status},
      conflictAlgorithm: ConflictAlgorithm.replace
    );
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

  static Future<void> saveReceiptCalculation(int customerId, String calculationJson) async {
    final dbClient = await db;
    final List<Map<String, dynamic>> existing = await dbClient.query(
      'receipt_calculations',
      where: 'customerId = ?',
      whereArgs: [customerId],
    );

    if (existing.isEmpty) {
      await dbClient.insert('receipt_calculations', {
        'customerId': customerId,
        'calculationJson': calculationJson,
      });
    } else {
      await dbClient.update(
        'receipt_calculations',
        {'calculationJson': calculationJson},
        where: 'customerId = ?',
        whereArgs: [customerId],
      );
    }
  }

  static Future<String?> getReceiptCalculation(int customerId) async {
    final dbClient = await db;
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


  ////////////////////////////////////////////////////////////////
  // Insert a new calculation (auto-generates id and datetime)
  static Future<int> insertReceiptCalculation(int customerId, String itemsJson) async {
    final dbClient = await db;
    String currentDatetime = DateTime.now().toIso8601String();

    return await dbClient.insert(
      'receipt_calculations',
      {
        'customerId': customerId,
        'calculationJson': itemsJson,
        'datetime': currentDatetime
      }
    );
  }

  // Update an existing draft/calculation by ID
  static Future<int> updateReceiptCalculation(int id, String itemsJson) async {
    final dbClient = await db;
    String updatedDatetime = DateTime.now().toIso8601String();

    return await dbClient.update(
      'receipt_calculations',
      {
        'calculationJson': itemsJson,
        'datetime': updatedDatetime
      },
      where: 'id = ?',
      whereArgs: [id]
    );
  }

  // Fetch all calculations for a specific customer
  static Future<List<Map<String, dynamic>>> getCustomerCalculations(int customerId) async {
    final dbClient = await db;
    return await dbClient.query(
      'receipt_calculations',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'datetime DESC' // Latest first
    );
  }
  //////////////////////////////////////////////////////////////////////////
  static Future<String?> getSpecificReceiptCalculation(int customerId, String targetBillId) async {
    final dbClient = await db; // use your actual database instance variable

    final List<Map<String, dynamic>> maps = await dbClient.query(
      'receipt_calculations',
      columns: ['calculationJson'],
      where: 'customerId = ? AND id = ?',
      whereArgs: [customerId, int.tryParse(targetBillId)],
    );

    if (maps.isNotEmpty) {
      return maps.first['calculationJson'] as String?;
    }
    return null;
  }


  // Delete calculation record by ID
  static Future<void> deleteReceiptCalculation(int id) async {
    final dbClient = await db;
    await dbClient.delete(
      'receipt_calculations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }


}
