
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:permission_handler/permission_handler.dart';
import '../db_helper.dart';
import '../backup_service.dart';

// ==========================================
// 🔐 HTTP CLIENT WRAPPER (Required for Drive API)
// ==========================================
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

// ==========================================================
// 🖼️ IMAGE COLUMN HANDLING  (the heart of the fix)
//
// The "images" column is a comma separated list that can hold THREE different things:
//
//   1) real file paths   /storage/emulated/0/Pictures/.AshaGrillHouse/customers/CUST_109_1784345257536.jpg
//                        -> these are moved to the folders of THIS phone (only the folder part changes)
//
//   2) XML reference     <receipt>242&42277.04&07-10-2026 09:54pm</receipt>
//                        -> NOT a file. The app draws this image dynamically, so it must stay
//                           EXACTLY as it is (character for character).
//
//   3) web links         https://...   -> kept as they are
//
// The old code ran p.basename() on every piece. basename cuts at the LAST "/", and the closing
// "</receipt>" contains one, so the reference turned into ".../customers/receipt>" (a dead image).
// ==========================================================
class ImageRemapResult {
  final String value;
  final int droppedCorrupt;
  const ImageRemapResult(this.value, this.droppedCorrupt);
}

class ImportImageRefs {
  // <tag> ... </tag>   (any tag name; the closing tag must match the opening one)
  static final RegExp _xmlRef = RegExp(r'<([A-Za-z_][\w\-]*)>[\s\S]*?</\1>');

  /// Splits the column into pieces. A complete <tag>...</tag> is ONE piece, even if it contains
  /// commas or slashes. Everything else is split on commas.
  static List<String> split(String raw) {
    final List<String> tokens = [];

    void addPlain(String chunk) {
      for (final String part in chunk.split(',')) {
        final String t = part.trim();
        if (t.isNotEmpty) tokens.add(t);
      }
    }

    int pos = 0;
    for (final Match m in _xmlRef.allMatches(raw)) {
      if (m.start > pos) addPlain(raw.substring(pos, m.start));
      tokens.add(m.group(0)!);
      pos = m.end;
    }
    if (pos < raw.length) addPlain(raw.substring(pos));
    return tokens;
  }

  static bool _isUrl(String t) {
    final String l = t.toLowerCase();
    return l.startsWith('http://') || l.startsWith('https://');
  }

  /// The footprint of the old bug: basename("<receipt>..</receipt>") == "receipt>".
  /// Such a value is not an image and its original content cannot be recovered.
  static bool _isDamagedReceipt(String t) {
    return !t.startsWith('<') && p.basename(t) == 'receipt>';
  }

  /// Rewrites the folder part of real image paths for this phone and keeps everything else untouched.
  /// [expected] (optional) collects  fileName -> new local path  for the Drive download step.
  static ImageRemapResult remap(
    String raw,
    String customersDir,
    String measurementsDir,
    Map<String, String>? expected,
  ) {
    final List<String> out = [];
    int dropped = 0;

    for (final String token in split(raw)) {
      // XML-like reference (<receipt>...</receipt>) or anything starting with "<": keep EXACTLY as it is
      if (token.startsWith('<')) {
        out.add(token);
        continue;
      }
      // web link: keep
      if (_isUrl(token)) {
        out.add(token);
        continue;
      }
      // damaged leftover from the old import bug: drop (it can never display)
      if (_isDamagedReceipt(token)) {
        dropped++;
        continue;
      }

      final String fName = p.basename(token);
      if (fName.isEmpty) {
        out.add(token);
        continue;
      }
      final String lower = token.toLowerCase();
      final bool isMeasurement = lower.contains('/measurements/') || lower.contains('/mesurements/');
      final String newPath = '${isMeasurement ? measurementsDir : customersDir}/$fName';
      out.add(newPath);
      if (expected != null) expected[fName] = newPath;
    }
    return ImageRemapResult(out.join(','), dropped);
  }
}

// ==========================================================
// 📅 DATE FIXER  (day / month mix-up from Google Sheets)
//
// Google Sheets keeps some dates as real date cells and some as plain text. The cells that Sheets
// understood as dates (every date whose day is 12 or smaller, e.g. 12-07-2026) can reach the app
// with day and month reversed (07-12-2026) - while dates such as 18-04-2026 stay correct.
// Result: 10 July shows up in October, 1 July in January, 2 July in February ...
//
// How this fixer decides (no guessing per row):
//   * a date that can only be read one way (day > 12, ISO text, sheet serial number, ...) is certain
//   * a date where BOTH numbers are <= 12 is "ambiguous"
//   * the whole table is compared in id order: read ambiguous dates as they are, or read them
//     reversed - the version that follows the id order (a timeline without crazy jumps) wins.
//     So one back-dated entry can never fool it, and a correct table is left exactly as it is.
//
//   expenses                         -> dates are rewritten to the app format  dd-MM-yyyy hh:mm AM/PM
//   transactions / messages / orders -> only a detected reversal is repaired (the rest of the text is kept)
// ==========================================================
class DateFixStats {
  int swapped = 0; // rows where day and month were reversed and are repaired now
  int converted = 0; // rows converted from ISO / serial number / other text to dd-MM-yyyy
  int unreadable = 0; // dates that could not be read at all (kept exactly as received)
  final List<String> swappedTables = [];
  final List<String> unverifiedTables = [];
}

class _DateCell {
  final int rowIndex;
  final int sortKey;
  final DateTime? exact; // certain date
  final DateTime? asIs; // ambiguous: first number is the day
  final DateTime? reversed; // ambiguous: first number is the month
  final bool monthFirst; // certain, but written month-first (e.g. 07-13-2026)
  final bool converted; // not dd-MM text (ISO, serial number, ...)

  const _DateCell({
    required this.rowIndex,
    required this.sortKey,
    this.exact,
    this.asIs,
    this.reversed,
    this.monthFirst = false,
    this.converted = false,
  });

  bool get ambiguous => exact == null;
}

class ImportDateFixer {
  // 12-07-2026 | 12/07/2026 | 12-07-2026 5:35 AM | 12-07-2026 05:35 PM | 12-07-2026 17:35 | 7/12/2026, 5:35:00 AM
  static final RegExp _textRe = RegExp(
    r'^\s*(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})(?:[\sT,]+(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?)?\s*$',
  );
  static final RegExp _isoRe = RegExp(r'^\s*\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}');
  // Sun Jul 12 2026 05:35:00 GMT+0530 (India Standard Time)
  static final RegExp _jsRe = RegExp(r'^[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})\s+(\d{2}):(\d{2}):\d{2}\s+GMT');
  static final RegExp _serialRe = RegExp(r'^\d{5}(\.\d+)?$');
  static const List<String> _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  static const Set<String> _swapOnlyTables = {'transactions', 'messages', 'orders'};

  /// Repairs the "date" column of [rows] in place. Never throws: on any problem the row is kept as received.
  static void fixRows(String table, List<Map<String, Object?>> rows, DateFixStats stats) {
    final bool canonical = table == 'expenses';
    if (!canonical && !_swapOnlyTables.contains(table)) return;

    final List<_DateCell> cells = [];
    for (int i = 0; i < rows.length; i++) {
      final Object? raw = rows[i]['date'];
      if (raw == null) continue;
      if (raw is String && raw.trim().isEmpty) continue;

      final int? id = int.tryParse(rows[i]['id']?.toString() ?? '');
      final int sortKey = id ?? (1 << 40) + i;

      _DateCell? cell;
      try {
        cell = _classify(raw, i, sortKey, canonical);
      } catch (_) {
        cell = null;
      }
      if (cell == null) {
        if (canonical) stats.unreadable++;
        continue;
      }
      cells.add(cell);
    }
    if (cells.isEmpty) return;

    // ---- one decision for the whole table
    bool reverse = false;
    final int ambiguousCount = cells.where((c) => c.ambiguous).length;
    if (ambiguousCount >= 6) {
      final double tvAsIs = _totalVariation(cells, false);
      final double tvReversed = _totalVariation(cells, true);
      if (tvReversed < tvAsIs * 0.7) {
        reverse = true;
      } else if (!(tvAsIs < tvReversed * 0.7)) {
        stats.unverifiedTables.add(table);
      }
    }

    // ---- apply
    int swappedHere = 0;
    for (final _DateCell c in cells) {
      final Map<String, Object?> row = rows[c.rowIndex];
      final String original = row['date'].toString();
      final bool wasReversed = c.monthFirst || (c.ambiguous && reverse);

      if (canonical) {
        final DateTime? dt = c.exact ?? (reverse ? c.reversed : c.asIs);
        if (dt == null) continue;
        row['date'] = _format(dt);
        if (wasReversed) {
          swappedHere++;
        } else if (c.converted) {
          stats.converted++;
        }
      } else if (wasReversed) {
        row['date'] = _swapFirstTwo(original);
        swappedHere++;
      }
    }
    if (swappedHere > 0) {
      stats.swapped += swappedHere;
      stats.swappedTables.add(table);
    }
  }

  static _DateCell? _classify(Object raw, int index, int sortKey, bool canonical) {
    // number straight from JSON: spreadsheet serial day number
    if (raw is num) {
      if (!canonical) return null;
      final DateTime? dt = _fromSerial(raw.toDouble());
      return dt == null ? null : _DateCell(rowIndex: index, sortKey: sortKey, exact: dt, converted: true);
    }

    final String s = raw.toString().trim();
    if (s.isEmpty) return null;

    final _DateCell? text = _classifyText(s, index, sortKey);
    if (text != null) return text;
    if (!canonical) return null; // other tables: only dd-MM text is ever touched

    if (_isoRe.hasMatch(s)) {
      DateTime? dt = DateTime.tryParse(s);
      if (dt == null) return null;
      if (dt.isUtc) dt = dt.toLocal(); // "...Z" / "+05:30" -> time of this phone
      return _DateCell(rowIndex: index, sortKey: sortKey, exact: dt, converted: true);
    }

    final Match? js = _jsRe.firstMatch(s);
    if (js != null) {
      final int month = _months.indexOf(js.group(1)!.toLowerCase()) + 1;
      if (month < 1) return null;
      final DateTime dt = DateTime(
        int.parse(js.group(3)!), month, int.parse(js.group(2)!), int.parse(js.group(4)!), int.parse(js.group(5)!));
      return _DateCell(rowIndex: index, sortKey: sortKey, exact: dt, converted: true);
    }

    if (_serialRe.hasMatch(s)) {
      final DateTime? dt = _fromSerial(double.parse(s));
      return dt == null ? null : _DateCell(rowIndex: index, sortKey: sortKey, exact: dt, converted: true);
    }
    return null;
  }

  static _DateCell? _classifyText(String s, int index, int sortKey) {
    final Match? m = _textRe.firstMatch(s);
    if (m == null) return null;

    final int a = int.parse(m.group(1)!);
    final int b = int.parse(m.group(2)!);
    final int year = int.parse(m.group(3)!);
    int hour = int.tryParse(m.group(4) ?? '0') ?? 0;
    final int minute = int.tryParse(m.group(5) ?? '0') ?? 0;
    final String? ap = m.group(6);
    if (ap != null) {
      if (hour > 12) return null;
      final bool pm = ap.toLowerCase().startsWith('p');
      hour = (hour % 12) + (pm ? 12 : 0);
    }
    if (hour > 23 || minute > 59) return null;

    DateTime? make(int day, int month) {
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      final DateTime d = DateTime(year, month, day, hour, minute);
      return (d.day == day && d.month == month) ? d : null;
    }

    final DateTime? asIs = make(a, b); // a = day, b = month
    final DateTime? reversed = make(b, a); // a = month, b = day

    if (asIs != null && reversed != null) {
      if (a == b) return _DateCell(rowIndex: index, sortKey: sortKey, exact: asIs);
      return _DateCell(rowIndex: index, sortKey: sortKey, asIs: asIs, reversed: reversed);
    }
    if (asIs != null) return _DateCell(rowIndex: index, sortKey: sortKey, exact: asIs);
    if (reversed != null) return _DateCell(rowIndex: index, sortKey: sortKey, exact: reversed, monthFirst: true);
    return null;
  }

  static DateTime? _fromSerial(double v) {
    if (v < 20000 || v > 80000) return null;
    final DateTime d = DateTime.utc(1899, 12, 30).add(Duration(minutes: (v * 1440).round()));
    return DateTime(d.year, d.month, d.day, d.hour, d.minute);
  }

  // Sum of the jumps between neighbours in id order. The correct reading is a smooth timeline.
  static double _totalVariation(List<_DateCell> cells, bool reverse) {
    final List<_DateCell> sorted = List<_DateCell>.from(cells)
    ..sort((x, y) {
      final int c = x.sortKey.compareTo(y.sortKey);
      return c != 0 ? c : x.rowIndex.compareTo(y.rowIndex);
    });

    DateTime? prev;
    double sum = 0;
    for (final _DateCell c in sorted) {
      final DateTime? dt = c.exact ?? (reverse ? c.reversed : c.asIs);
      if (dt == null) continue;
      if (prev != null) sum += dt.difference(prev).inMinutes.abs() / 1440.0;
      prev = dt;
    }
    return sum;
  }

  static String _swapFirstTwo(String s) {
    return s.replaceFirstMapped(
      RegExp(r'^(\s*)(\d{1,2})([-/.])(\d{1,2})'),
      (m) => '${m[1]}${m[4]}${m[3]}${m[2]}',
    );
  }

  // The format the app itself writes: 18-04-2026 09:59 AM
  static String _format(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${two(d.day)}-${two(d.month)}-${d.year.toString().padLeft(4, '0')} ${two(h12)}:${two(d.minute)} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _ImportSummary {
  int tables = 0;
  int rows = 0;
  int droppedCorrupt = 0;
  final DateFixStats dates = DateFixStats();
  final List<String> skippedTables = [];
}

class _DriveResult {
  int downloaded = 0;
  int failed = 0;
}

class ImportPage extends StatefulWidget {
  const ImportPage({Key? key}) : super(key: key);

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {

  // Tables that are restored (same list and same order as before)
  static const List<String> _tables = [
    'customers', 'transactions', 'tempcustomer', 'measurements', 'expenses', 'orders',
    'messages', 'pins', 'price_agreements', 'receipt_calculations', 'expense_keywords'
  ];

  bool _isImportingData = false;
  bool _isImportingImages = false;
  bool _isImportingFromDrive = false;
  String _driveSyncStatus = "";

  bool get _busy => _isImportingData || _isImportingImages || _isImportingFromDrive;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  // ==========================================================
  // 🗂️ SD CARD & INTERNAL STORAGE FINDER (From Add Customer Page)
  // ==========================================================
  Future<Directory> _getTargetDirectory(String subFolder) async {
    debugPrint("📁 [IMPORT] TARGETING 'Pictures/.AshaGrillHouse/$subFolder'");

    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }

    String? sdCardRootPath;
    const String internalRootPath = '/storage/emulated/0';

    try {
      final List<Directory>? extDirs = await getExternalStorageDirectories();
      if (extDirs != null && extDirs.length > 1) {
        final String appSpecificSdPath = extDirs[1].path;
        final int androidIndex = appSpecificSdPath.indexOf('/Android/');
        if (androidIndex != -1) {
          sdCardRootPath = appSpecificSdPath.substring(0, androidIndex);
        }
      }
    } catch (e) {
      debugPrint("❌ Error finding SD card directories: $e");
    }

    Directory targetFolder;

    // ATTEMPT 1: SD Card
    if (sdCardRootPath != null) {
      targetFolder = Directory("$sdCardRootPath/Pictures/.AshaGrillHouse/$subFolder");
      try {
        if (!await targetFolder.exists()) {
          await targetFolder.create(recursive: true);
        }
        return targetFolder;
      } catch (e) {
        debugPrint("⚠️ OS Blocked SD Card 'Pictures' access: $e");
      }
    }

    // ATTEMPT 2: Internal Storage
    targetFolder = Directory("$internalRootPath/Pictures/.AshaGrillHouse/$subFolder");
    if (!await targetFolder.exists()) {
      await targetFolder.create(recursive: true);
    }
    return targetFolder;
  }

  // ==========================================================
  // 💾 WRITE THE TABLES (shared by Google Sheets import and JSON import)
  //
  //  * everything happens in ONE transaction: if anything fails, nothing is changed
  //    (the old code deleted a table first, so a failure could leave it empty)
  //  * only columns that really exist in the local table are written
  //  * "images" values go through ImportImageRefs (receipt references stay untouched)
  // ==========================================================
  Future<_ImportSummary> _writeTables(
    Map<String, dynamic> data,
    Directory customersDir,
    Directory measurementsDir,
    Map<String, String> expectedImageLocations,
  ) async {
    final db = await DBHelper.db;
    final _ImportSummary summary = _ImportSummary();

    // Real columns of each local table (also shows which tables do not exist in this app)
    final Map<String, Set<String>> columnsByTable = {};
    for (final String table in _tables) {
      if (!data.containsKey(table)) continue;
      final info = await db.rawQuery('PRAGMA table_info($table)');
      if (info.isEmpty) {
        summary.skippedTables.add(table);
        continue;
      }
      columnsByTable[table] = info.map((c) => c['name'].toString()).toSet();
    }

    // ---- 1. Prepare everything BEFORE the database is touched
    //         (clean rows, repair dates, remap image paths)
    final Map<String, List<Map<String, Object?>>> prepared = {};
    for (final String table in _tables) {
      final Set<String>? columns = columnsByTable[table];
      if (columns == null) continue;

      final dynamic rawRows = data[table];
      final List<dynamic> rows = rawRows is List ? rawRows : <dynamic>[];

      final List<Map<String, Object?>> cleaned = [];
      for (final dynamic r in rows) {
        if (r is! Map) continue;
        final Map<String, Object?> row = _cleanRow(r, columns);
        if (row.isEmpty) continue; // empty sheet lines
        cleaned.add(row);
      }

      // repair day/month mix-ups and unify the date text
      try {
        ImportDateFixer.fixRows(table, cleaned, summary.dates);
      } catch (e) {
        debugPrint("⚠️ Date repair skipped for $table: $e");
      }

      if (table == 'expenses') {
        for (final Map<String, Object?> row in cleaned) {
          final Object? amount = row['amount'];
          // 1466.0 -> "1466" (the column is text, keep it clean)
          if (amount is num) {
            row['amount'] = amount == amount.truncate() ? amount.toInt().toString() : amount.toString();
          }
        }
      }

      for (final Map<String, Object?> row in cleaned) {
        final Object? images = row['images'];
        if (images != null && images.toString().trim().isNotEmpty) {
          final ImageRemapResult res = ImportImageRefs.remap(
            images.toString(),
            customersDir.path,
            measurementsDir.path,
            expectedImageLocations,
          );
          row['images'] = res.value;
          summary.droppedCorrupt += res.droppedCorrupt;
        }
      }

      prepared[table] = cleaned;
    }

    // ---- 2. Write: ONE transaction, all or nothing
    await db.transaction((txn) async {
      for (final String table in _tables) {
        final List<Map<String, Object?>>? rows = prepared[table];
        if (rows == null) continue;

        await txn.delete(table);

        final Batch batch = txn.batch();
        for (final Map<String, Object?> row in rows) {
          batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
          summary.rows++;
        }
        await batch.commit(noResult: true);
        summary.tables++;
      }
    });

    return summary;
  }

  // Keeps only real columns and converts values SQLite cannot store (true/false, lists, maps)
  Map<String, Object?> _cleanRow(Map raw, Set<String> columns) {
    final Map<String, Object?> out = {};
    raw.forEach((k, v) {
      final String key = k.toString();
      if (!columns.contains(key)) return;
      if (v == null || v is num || v is String) {
        out[key] = v;
      } else if (v is bool) {
        out[key] = v ? 1 : 0;
      } else {
        out[key] = jsonEncode(v);
      }
    });

    // A line that is completely empty in the sheet is not a record
    final bool allBlank = out.values.every((v) => v == null || (v is String && v.trim().isEmpty));
    if (allBlank) return {};

    // "id" must be a whole number (a blank or text id would make SQLite reject the whole import)
    if (out.containsKey('id')) {
      final Object? id = out['id'];
      if (id is String) {
        final int? n = int.tryParse(id.trim()) ?? double.tryParse(id.trim())?.toInt();
        if (n == null) {
          out.remove('id'); // SQLite numbers it by itself
        } else {
          out['id'] = n;
        }
      }
    }
    return out;
  }

  String _summaryText(_ImportSummary s) {
    final StringBuffer b = StringBuffer("Database restored: ${s.rows} records in ${s.tables} tables.");
    if (s.droppedCorrupt > 0) {
      b.write("\nRemoved ${s.droppedCorrupt} damaged receipt reference(s) left by an old import.");
    }
    if (s.skippedTables.isNotEmpty) {
      b.write("\nSkipped (not found in this app): ${s.skippedTables.join(', ')}.");
    }
    final DateFixStats d = s.dates;
    if (d.swapped > 0) {
      b.write("\nDates repaired: ${d.swapped} date(s) had day and month reversed (${d.swappedTables.join(', ')}) - now correct.");
    }
    if (d.converted > 0) {
      b.write("\nConverted ${d.converted} date(s) to dd-MM-yyyy hh:mm AM/PM.");
    }
    if (d.unreadable > 0) {
      b.write("\n${d.unreadable} date(s) could not be read and were kept exactly as received.");
    }
    if (d.unverifiedTables.isNotEmpty) {
      b.write("\nCould not verify the day/month order of: ${d.unverifiedTables.join(', ')} (kept as received).");
    }
    return b.toString();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  // ==========================================
  // ☁️ IMPORT FROM GOOGLE SHEETS & DRIVE
  // ==========================================
  Future<http.Response> _fetchDatabaseFromScript(Map<String, String> cfg) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(cfg['scriptUrl']!))
      ..headers["Content-Type"] = "application/json"
      ..body = jsonEncode({
        ...DBHelper.buildSyncAuth(cfg),
        "action": "fetch_full_database",
      })
      ..followRedirects = false;

      final streamedResponse = await client.send(request).timeout(const Duration(minutes: 2));
      http.Response response = await http.Response.fromStream(streamedResponse);

      // Google Apps Script answers with a 302/303 redirect that has to be followed by hand
      if (response.statusCode == 302 || response.statusCode == 303) {
        final String? redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          response = await http.get(Uri.parse(redirectUrl)).timeout(const Duration(minutes: 2));
        }
      }
      return response;
    } finally {
      client.close();
    }
  }

  void _setStatus(String text) {
    if (!mounted) return;
    setState(() => _driveSyncStatus = text);
  }

  Future<void> _importFromGoogleSheetAndDrive() async {
    if (_busy) return;
    if (!await _confirmReplace("Restoring from Google Sheets")) return;

    setState(() {
      _isImportingFromDrive = true;
      _driveSyncStatus = "Step 1/4: Fetching Google Sheets...";
    });

    try {
      final cfg = await DBHelper.getSyncConfig();
      if (cfg['scriptUrl']!.isEmpty) {
        throw Exception("[IMP-101] Google Script URL is missing. Open System Settings and enter it.");
      }
      if (cfg['secretKey']!.isEmpty) {
        throw Exception("[IMP-111] Secret Key is not set. Open System Settings and enter it.");
      }

      final http.Response scriptResponse = await _fetchDatabaseFromScript(cfg);
      final String? problem = BackupService.explainServerReply(scriptResponse);
      if (problem != null) throw Exception(problem);

      _setStatus("Step 2/4: Parsing Data...");
      dynamic decoded;
      try {
        decoded = jsonDecode(scriptResponse.body);
      } catch (_) {
        decoded = null;
      }
      if (decoded is! Map) {
        throw Exception("Unexpected answer from the Google Script (not JSON). Check the script URL and deployment.");
      }
      if (decoded['status'] == 'error') {
        throw Exception(decoded['message']?.toString() ?? "Google Script returned an error.");
      }
      final dynamic dbRaw = decoded['database'];
      if (dbRaw is! Map) throw Exception("The Google Script did not return a database.");
      final Map<String, dynamic> dbData = Map<String, dynamic>.from(dbRaw);

      _setStatus("Step 3/4: Updating Database...");
      final Directory customersDir = await _getTargetDirectory("customers");
      final Directory measurementsDir = await _getTargetDirectory("measurements");
      final Map<String, String> expectedImageLocations = {};

      final _ImportSummary summary = await _writeTables(dbData, customersDir, measurementsDir, expectedImageLocations);

      // ---- Images: the database is already restored; a problem here must not look like a total failure
      String imageNote = "";
      bool imageProblem = false;
      try {
        _setStatus("Step 4/4: Connecting to Drive...");
        final GoogleSignInAccount? account = await _googleSignIn.signIn();
        if (account == null) throw Exception("Google Sign-In cancelled.");

        final authHeaders = await account.authHeaders;
        final authenticateClient = GoogleAuthClient(authHeaders);
        final driveApi = drive.DriveApi(authenticateClient);

        final folderList = await driveApi.files.list(
          q: "mimeType='application/vnd.google-apps.folder' and name='.AshaGrillHouse' and trashed=false",
          $fields: "files(id)",
        );
        if (folderList.files == null || folderList.files!.isEmpty) {
          throw Exception(".AshaGrillHouse folder not found on Drive.");
        }
        final String mainFolderId = folderList.files!.first.id!;

        _setStatus("Checking customers folder...");
        final _DriveResult rc = await _downloadMissingImages(
          driveApi, mainFolderId, "customers", customersDir, measurementsDir, expectedImageLocations);

        _setStatus("Checking measurements folder...");
        final _DriveResult rm = await _downloadMissingImages(
          driveApi, mainFolderId, "measurements", customersDir, measurementsDir, expectedImageLocations);

        final int downloaded = rc.downloaded + rm.downloaded;
        final int failed = rc.failed + rm.failed;
        imageNote = "Downloaded $downloaded missing image(s)" + (failed > 0 ? " ($failed failed)." : ".");
        imageProblem = failed > 0;
      } catch (e) {
        imageProblem = true;
        imageNote = "Images were NOT downloaded: ${_clean(e)}";
      }

      final String message = "${_summaryText(summary)}\n$imageNote";
      if (imageProblem) {
        _showInfoMsg(message);
      } else {
        _showSuccessMsg(message);
      }
    } catch (e) {
      _showErrorMsg("Sync failed: ${_clean(e)}");
    } finally {
      if (mounted) setState(() => _isImportingFromDrive = false);
    }
  }

  // Downloads the images that are not on the phone yet. One bad file never stops the others,
  // and a half-downloaded file is never kept (it is written to ".part" first, then renamed).
  Future<_DriveResult> _downloadMissingImages(
    drive.DriveApi driveApi,
    String mainFolderId,
    String folderName,
    Directory customersDir,
    Directory measurementsDir,
    Map<String, String> expectedImageLocations,
  ) async {
    final _DriveResult result = _DriveResult();

    final driveFolderReq = await driveApi.files.list(
      q: "mimeType='application/vnd.google-apps.folder' and name='$folderName' and '$mainFolderId' in parents and trashed=false",
      $fields: "files(id)",
    );
    if (driveFolderReq.files == null || driveFolderReq.files!.isEmpty) return result;
    final String folderId = driveFolderReq.files!.first.id!;

    String? pageToken;
    do {
      final fileList = await driveApi.files.list(
        q: "'$folderId' in parents and trashed=false",
        $fields: "nextPageToken, files(id, name)",
        pageSize: 1000,
        pageToken: pageToken,
      );

      if (fileList.files != null) {
        for (final f in fileList.files!) {
          if (f.id == null || f.name == null) continue;
          final String fName = f.name!;
          final String baseDir = folderName == 'measurements' ? measurementsDir.path : customersDir.path;
          final String targetPath = expectedImageLocations[fName] ?? "$baseDir/$fName";

          final File localFile = File(targetPath);
          if (await localFile.exists()) continue;

          _setStatus("Downloading: $fName");
          final File tmp = File("$targetPath.part");
          try {
            final imgMedia = await driveApi.files.get(f.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
            final sink = tmp.openWrite();
            await imgMedia.stream.pipe(sink);
            await sink.close();
            await tmp.rename(targetPath);
            result.downloaded++;
          } catch (e) {
            result.failed++;
            debugPrint("⚠️ Could not download $fName: $e");
            try {
              if (await tmp.exists()) await tmp.delete();
            } catch (_) {}
          }
        }
      }
      pageToken = fileList.nextPageToken;
    } while (pageToken != null);

    return result;
  }

  // ==========================================
  // 📄 LOCAL IMPORT: JSON FILE (Manual)
  // ==========================================
  Future<void> _importDataFromJson() async {
    if (_busy) return;
    if (!await _confirmReplace("Importing this JSON file")) return;

    setState(() => _isImportingData = true);
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return;

      final File file = File(result.files.single.path!);
      final String jsonString = await file.readAsString();

      dynamic decoded;
      try {
        decoded = jsonDecode(jsonString);
      } catch (_) {
        decoded = null;
      }
      if (decoded is! Map) throw Exception("This is not a valid backup file.");
      final Map<String, dynamic> jsonData = Map<String, dynamic>.from(decoded);
      if (!_tables.any((t) => jsonData.containsKey(t))) {
        throw Exception("This file does not contain any known table.");
      }

      final Directory customersDir = await _getTargetDirectory("customers");
      final Directory measurementsDir = await _getTargetDirectory("measurements");

      final _ImportSummary summary = await _writeTables(jsonData, customersDir, measurementsDir, {});
      _showSuccessMsg(_summaryText(summary));
    } catch (e) {
      _showErrorMsg("Data Import failed: ${_clean(e)}");
    } finally {
      if (mounted) setState(() => _isImportingData = false);
    }
  }

  // ==========================================
  // 🗂️ LOCAL IMPORT: ZIP FILE (Images)
  // ==========================================
  Future<void> _importImagesFromZip() async {
    if (_busy) return;
    setState(() => _isImportingImages = true);
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.single.path == null) return;

      final File zipFile = File(result.files.single.path!);
      final List<int> bytes = await zipFile.readAsBytes();
      final Archive archive = ZipDecoder().decodeBytes(bytes);

      final Directory customersDir = await _getTargetDirectory("customers");
      final Directory measurementsDir = await _getTargetDirectory("measurements");

      int count = 0;
      for (final ArchiveFile file in archive) {
        if (!file.isFile) continue;

        final String filename = p.basename(file.name);
        if (filename.isEmpty || filename.startsWith('._')) continue; // skip empty names / macOS junk

        // Check if the file path within the zip contains measurements
        final String lower = file.name.toLowerCase();
        final bool isMeasurement = lower.contains('measurements') || lower.contains('mesurements');
        final Directory targetDir = isMeasurement ? measurementsDir : customersDir;

        final File outFile = File(p.join(targetDir.path, filename));
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        count++;
      }
      _showSuccessMsg("Successfully extracted $count images!");
    } catch (e) {
      _showErrorMsg("Image Import failed: ${_clean(e)}");
    } finally {
      if (mounted) setState(() => _isImportingImages = false);
    }
  }

  // ==========================================
  // 💬 DIALOG & SNACKBARS
  // ==========================================
  // Importing replaces the data on this phone, so ask first
  Future<bool> _confirmReplace(String what) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Replace current data?"),
        content: Text("$what will REPLACE the customers, transactions and other data that is currently on this phone. Your photos are not deleted."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text("Replace"),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _showSnack(String msg, Color color, int seconds) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: seconds),
    ));
  }

  void _showSuccessMsg(String msg) => _showSnack(msg, Colors.green, 6);
  void _showInfoMsg(String msg) => _showSnack(msg, Colors.orange.shade800, 9);
  void _showErrorMsg(String msg) => _showSnack(msg, Colors.redAccent, 8);

  // ==========================================
  // 🎨 UI DESIGN
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Import & Restore", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Restore your data",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              "Import a JSON backup to restore all customers and transactions. Import a ZIP to restore images.",
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 32),

            // ☁️ GOOGLE SCRIPT & DRIVE IMPORT CARD
            _buildImportCard(
              title: "Restore from Sheets & Drive",
              description: "Fetches your live database from Google Sheets and automatically downloads missing images into SD Card.",
              icon: Icons.cloud_sync_rounded,
              color: Colors.blueAccent,
              buttonText: "FETCH FROM SCRIPT",
              isLoading: _isImportingFromDrive,
              disabled: _busy && !_isImportingFromDrive,
              statusText: _driveSyncStatus,
              onTap: _importFromGoogleSheetAndDrive,
            ),

            const SizedBox(height: 24),

            // 📄 DATA IMPORT CARD
            _buildImportCard(
              title: "Import Database (JSON)",
              description: "Restores your customers, measurements, and transactions from a manually downloaded JSON file.",
              icon: Icons.data_object_rounded,
              color: Colors.deepOrange,
              buttonText: "SELECT FILE",
              isLoading: _isImportingData,
              disabled: _busy && !_isImportingData,
              onTap: _importDataFromJson,
            ),

            const SizedBox(height: 24),

            // 🖼️ IMAGE IMPORT CARD
            _buildImportCard(
              title: "Import Images (ZIP)",
              description: "Select a ZIP file to restore images perfectly into their customers and measurements folders.",
              icon: Icons.photo_library_rounded,
              color: Colors.teal,
              buttonText: "SELECT FILE",
              isLoading: _isImportingImages,
              disabled: _busy && !_isImportingImages,
              onTap: _importImagesFromZip,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String buttonText,
    required bool isLoading,
    bool disabled = false,
    String? statusText,
    required VoidCallback onTap,
  }) {
    final VoidCallback? action = (isLoading || disabled) ? null : onTap;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8))],
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: action,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, size: 32, color: color),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: action,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                    ),
                    child: isLoading
                    ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            statusText ?? "Processing...",
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                    : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(buttonText.contains("FETCH") ? Icons.cloud_sync_rounded : Icons.file_upload_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text(buttonText, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
