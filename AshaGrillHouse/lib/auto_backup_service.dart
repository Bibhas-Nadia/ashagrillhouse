
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'db_helper.dart';

// 🔥 Change this import to point to your new service file!
// Make sure the path is correct depending on where you saved it.
import 'website_sync_page.dart';

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
}

enum BackupStatus {
  alreadyDone,
  success,
  failedSilently,
  inProgress,
  notConfigured
}

class AutoBackupService {
  static bool _isBackupRunning = false;

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  static Future<BackupStatus> checkAndRunDailyBackup() async {

    bool isEnabled = await DBHelper.isBackupEnabled();
    if (!isEnabled) {
      return BackupStatus.notConfigured;
    }

    if (_isBackupRunning) return BackupStatus.inProgress;
    _isBackupRunning = true;

    try {
      await Future.delayed(const Duration(seconds: 3));

      final DateTime now = DateTime.now();
      final String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final String fullDateStr = "$todayStr ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      // 1. Check current status from DB
      final currentStatusData = await DBHelper.getBackupStatus();


      if (currentStatusData != null) {
        String lastDate = currentStatusData['date']?.toString() ?? '';
        String lastStatus = currentStatusData['status']?.toString() ?? '';

        if (lastDate.startsWith(todayStr) && lastStatus == 'success') {
          _isBackupRunning = false;
          return BackupStatus.alreadyDone;
        }
      }

      // ==========================================
      // 🚀 STEP 1: RAW DRIVE BACKUP (For App Restoration)
      // ==========================================
      String? errorMsg = await _performGoogleDriveBackup(fullDateStr);

      if (errorMsg != null) {
        // Failed Raw Backup
        await DBHelper.logBackupStatus(fullDateStr, "Raw Backup Failed: $errorMsg", "failed");
        _isBackupRunning = false;
        return BackupStatus.failedSilently;
      }

      // ==========================================
      // 🌐 STEP 2: SECURE WEB PORTAL SYNC (For Website)
      // ==========================================
      try {
        // Automatically runs in the background. No parameters or UI needed.
        // await WebsiteSyncService.runBackgroundSync();

        // If both succeeded, log final success!
        await DBHelper.logBackupStatus(fullDateStr, "None", "success");
        _isBackupRunning = false;

         WebsiteSyncService.runBackgroundSync(); // it is added========================================================

        return BackupStatus.success;

      } catch (e) {
        // Failed Web Sync
        await DBHelper.logBackupStatus(fullDateStr, "Web Sync Failed: $e", "failed");
        _isBackupRunning = false;
        return BackupStatus.failedSilently;
      }

    } catch (e) {
      final DateTime now = DateTime.now();
      final String fullDateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      await DBHelper.logBackupStatus(fullDateStr, "Critical Auto-Backup Crash: $e", "failed");
      _isBackupRunning = false;
      return BackupStatus.failedSilently;
    }
  }

  // ==========================================
  // ☁️ MAIN BACKUP LOGIC (NO UI)
  // ==========================================
  static Future<String?> _performGoogleDriveBackup(String fullDateStr) async {
    try {
      // 1. SILENT Sign In (Needs previous authorization from user via Export/Import Page)
      GoogleSignInAccount? account = await _googleSignIn.signInSilently();
      if (account == null) {
        return "Google Sign-In required. User must export manually once to authorize background backups.";
      }

      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 2. Create/Get Folders
      String? mainFolderId = await _getOrCreateFolder(driveApi, ".AshaGrillHouse");
      if (mainFolderId == null) return "Could not create .AshaGrillHouse main folder";

      String? customersFolderId = await _getOrCreateFolder(driveApi, "customers", parentId: mainFolderId);
      String? measurementsFolderId = await _getOrCreateFolder(driveApi, "measurements", parentId: mainFolderId);
      if (customersFolderId == null || measurementsFolderId == null) return "Could not create subfolders";

      // 3. Generate JSON Data
      final db = await DBHelper.db;
      Map<String, dynamic> fullBackup = {};
      List<String> tables = ['customers', 'transactions', 'tempcustomer', 'measurements', 'expenses', 'orders','messages','pins','price_agreements','receipt_calculations','expense_keywords'];

      for (String table in tables) {
        try {
          fullBackup[table] = await db.query(table);
        } catch (e) {
          // Ignore tables that might not exist
        }
      }

      String jsonString = const JsonEncoder.withIndent('  ').convert(fullBackup);
      Directory tempDir = await getTemporaryDirectory();
      String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      String jsonFileName = 'asha_grill_house_backup_$timestamp.json';
      File jsonFile = File(p.join(tempDir.path, jsonFileName));
      await jsonFile.writeAsString(jsonString);

      // 4. Upload JSON
      var driveJsonFile = drive.File();
      driveJsonFile.name = jsonFileName;
      driveJsonFile.parents = [mainFolderId];
      await driveApi.files.create(
        driveJsonFile,
        uploadMedia: drive.Media(jsonFile.openRead(), jsonFile.lengthSync()),
      );

      // 5. Fetch Existing Images (To skip duplicates)
      Set<String> existingCustomerFiles = await _fetchExistingFiles(driveApi, customersFolderId);
      Set<String> existingMeasurementFiles = await _fetchExistingFiles(driveApi, measurementsFolderId);

      // 6. Find Local Images (Filesystem + DB Paths)
      Set<String> localFilesToUpload = {};
      Directory baseDir = await _getBaseStorageDir();

      List<Directory> targetDirs = [
        Directory("${baseDir.path}/.AshaGrillHouse/customers"),
        Directory("${baseDir.path}/.AshaGrillHouse/measurements"),
        Directory("${baseDir.path}/customers"),
        Directory("${baseDir.path}/measurements")
      ];

      for (var dir in targetDirs) {
        if (dir.existsSync()) {
          List<FileSystemEntity> files = dir.listSync(recursive: true);
          for (var file in files) {
            if (file is File && (file.path.endsWith('.jpg') || file.path.endsWith('.png') || file.path.endsWith('.jpeg'))) {
              localFilesToUpload.add(file.path);
            }
          }
        }
      }

      void extractPathsFromDB(List<dynamic>? records) {
        if (records == null) return;
        for (var row in records) {
          if (row['images'] != null && row['images'].toString().isNotEmpty) {
            List<String> paths = row['images'].toString().split(',');
            for (String pt in paths) {
              String cleanPath = pt.trim();
              if (cleanPath.isNotEmpty && File(cleanPath).existsSync()) {
                localFilesToUpload.add(cleanPath);
              }
            }
          }
        }
      }
      extractPathsFromDB(fullBackup['customers']);
      extractPathsFromDB(fullBackup['measurements']);

      // 7. Upload Images to Correct Folders
      for (String filePath in localFilesToUpload) {
        File file = File(filePath);
        String fileName = p.basename(file.path);

        bool isMeasurement = filePath.toLowerCase().contains('/measurements/') || filePath.toLowerCase().contains('/mesurements/');
        String targetFolderId = isMeasurement ? measurementsFolderId : customersFolderId;
        Set<String> existingFilesCheck = isMeasurement ? existingMeasurementFiles : existingCustomerFiles;

        // Skip if already on drive
        if (existingFilesCheck.contains(fileName)) {
          continue;
        }

        var driveImageFile = drive.File();
        driveImageFile.name = fileName;
        driveImageFile.parents = [targetFolderId];

        await driveApi.files.create(
          driveImageFile,
          uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
        );

        existingFilesCheck.add(fileName);
      }

      return null; // Return null means SUCCESS

    } catch (e) {
      return e.toString(); // Return error string
    }
  }

  // ==========================================================
  // 🗂️ HELPERS
  // ==========================================================
  static Future<String?> _getOrCreateFolder(drive.DriveApi driveApi, String folderName, {String? parentId}) async {
    String query = "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false";
    if (parentId != null) query += " and '$parentId' in parents";

    var fileList = await driveApi.files.list(q: query, $fields: "files(id, name)");
    if (fileList.files != null && fileList.files!.isNotEmpty) return fileList.files!.first.id;

    var folder = drive.File();
    folder.name = folderName;
    folder.mimeType = "application/vnd.google-apps.folder";
    if (parentId != null) folder.parents = [parentId];

    var createdFolder = await driveApi.files.create(folder);
    return createdFolder.id;
  }

  static Future<Set<String>> _fetchExistingFiles(drive.DriveApi driveApi, String folderId) async {
    Set<String> existing = {};
    String? pageToken;
    do {
      var fileList = await driveApi.files.list(
        q: "'$folderId' in parents and trashed=false",
        $fields: "nextPageToken, files(name)",
        pageSize: 1000,
        pageToken: pageToken,
      );
      if (fileList.files != null) {
        for (var f in fileList.files!) {
          if (f.name != null) existing.add(f.name!);
        }
      }
      pageToken = fileList.nextPageToken;
    } while (pageToken != null);
    return existing;
  }

  static Future<Directory> _getBaseStorageDir() async {
    Directory? targetDir;
    try {
      List<Directory>? extDirectories = await getExternalStorageDirectories(type: StorageDirectory.pictures);
      if (extDirectories != null && extDirectories.isNotEmpty) {
        targetDir = extDirectories.length > 1 ? extDirectories[1] : extDirectories[0];
      }
    } catch (e) {
      print("Error getting external storage: $e");
    }
    return targetDir ?? await getApplicationDocumentsDirectory();
  }
}
