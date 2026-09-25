import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../db_helper.dart';
import '../backup_service.dart'; // Ensure this points to the file containing BackupService

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

class ExportPage extends StatefulWidget {
  @override
  _ExportPageState createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  bool _isExportingData = false;
  bool _isExportingImages = false;
  bool _isUploadingToDrive = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  @override
  void initState() {
    super.initState();
  }

  // ==========================================
  // 📄 EXPORT DATABASE AS JSON (LOCAL SHARE)
  // ==========================================
  Future<void> _exportDataAsJson() async {
    setState(() => _isExportingData = true);

    try {
      final db = await DBHelper.db;
      Map<String, dynamic> fullBackup = {};

      List<String> tables = ['customers', 'transactions', 'tempcustomer', 'measurements', 'expenses', 'orders','messages','pins','price_agreements','receipt_calculations','expense_keywords'];

      for (String table in tables) {
        try {
          final List<Map<String, dynamic>> records = await db.query(table);
          fullBackup[table] = records;
        } catch (e) {
          print("Table $table might not exist yet, skipping.");
        }
      }

      String jsonString = const JsonEncoder.withIndent('  ').convert(fullBackup);

      Directory tempDir = await getTemporaryDirectory();
      String filePath = p.join(tempDir.path, 'asha_grill_data_backup.json');
      File backupFile = File(filePath);
      await backupFile.writeAsString(jsonString);

      if (mounted) {
        await Share.shareXFiles([XFile(filePath)], text: 'Asha Grill House - Database JSON Backup');
        _showSuccessMsg("Data exported successfully!");
      }
    } catch (e) {
      _showErrorMsg("Data Export failed: $e");
    } finally {
      setState(() => _isExportingData = false);
    }
  }

  // ==========================================
  // ☁️ BACKUP JSON & IMAGES TO GOOGLE DRIVE
  // ==========================================
  // Future<String?> _getOrCreateFolder(drive.DriveApi driveApi, String folderName, {String? parentId}) async {
  //   String query = "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false";
  //   if (parentId != null) {
  //     query += " and '$parentId' in parents";
  //   }
  //
  //   var fileList = await driveApi.files.list(q: query, $fields: "files(id, name)");
  //   if (fileList.files != null && fileList.files!.isNotEmpty) {
  //     return fileList.files!.first.id;
  //   }
  //
  //   var folder = drive.File();
  //   folder.name = folderName;
  //   folder.mimeType = "application/vnd.google-apps.folder";
  //   if (parentId != null) {
  //     folder.parents = [parentId];
  //   }
  //
  //   var createdFolder = await driveApi.files.create(folder);
  //   return createdFolder.id;
  // }
/*
  Future<void> _backupToGoogleDrive() async {
    setState(() => _isUploadingToDrive = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Connecting to Google Drive... Please wait."), duration: Duration(seconds: 3))
    );

    try {
      // 1. Sign In
      GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        _showErrorMsg("Google Sign-In Cancelled.");
        setState(() => _isUploadingToDrive = false);
        return;
      }

      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 2. Create/Get Folders (Main + SEPARATE Customers & Measurements folders)
      String? mainFolderId = await _getOrCreateFolder(driveApi, ".AshaGrillHouse");
      if (mainFolderId == null) throw Exception("Could not create main folder");

      String? customersFolderId = await _getOrCreateFolder(driveApi, "customers", parentId: mainFolderId);
      String? measurementsFolderId = await _getOrCreateFolder(driveApi, "measurements", parentId: mainFolderId);
      if (customersFolderId == null || measurementsFolderId == null) throw Exception("Could not create subfolders");

      // 3. Generate JSON
      final db = await DBHelper.db;
      Map<String, dynamic> fullBackup = {};
      List<String> tables = ['customers', 'transactions', 'tempcustomer', 'measurements', 'expenses', 'orders','messages','pins','price_agreements','receipt_calculations','expense_keywords'];

      for (String table in tables) {
        try {
          fullBackup[table] = await db.query(table);
        } catch (e) {
          print("Table $table skipped.");
        }
      }

      String jsonString = const JsonEncoder.withIndent('  ').convert(fullBackup);
      Directory tempDir = await getTemporaryDirectory();
      String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      String jsonFileName = 'asha_grill_house_backup_$timestamp.json';
      File jsonFile = File(p.join(tempDir.path, jsonFileName));
      await jsonFile.writeAsString(jsonString);

      // Upload JSON
      var driveJsonFile = drive.File();
      driveJsonFile.name = jsonFileName;
      driveJsonFile.parents = [mainFolderId];
      await driveApi.files.create(
        driveJsonFile,
        uploadMedia: drive.Media(jsonFile.openRead(), jsonFile.lengthSync()),
      );

      // 4. 🔥 FETCH EXISTING IMAGES ON DRIVE (Separated) TO SKIP DUPLICATES
      Future<Set<String>> fetchExistingFiles(String folderId) async {
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

      Set<String> existingCustomerFiles = await fetchExistingFiles(customersFolderId);
      Set<String> existingMeasurementFiles = await fetchExistingFiles(measurementsFolderId);

      // 5. 🔥 FIND ALL LOCAL IMAGES TO UPLOAD
      Set<String> localFilesToUpload = {};
      Directory baseDir = await _getBaseStorageDir();

      // Check standard and AshaGrillHouse subdirectories
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

      // Also read EXACT paths from Database to be 100% sure we don't miss anything
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

      // 6. UPLOAD IMAGES TO CORRECT SUBFOLDERS
      int imageCount = 0;
      int skippedCount = 0;

      for (String filePath in localFilesToUpload) {
        File file = File(filePath);
        String fileName = p.basename(file.path);

        // Determine correct folder based on path
        bool isMeasurement = filePath.toLowerCase().contains('/measurements/') || filePath.toLowerCase().contains('/mesurements/');
        String targetFolderId = isMeasurement ? measurementsFolderId : customersFolderId;
        Set<String> existingFilesCheck = isMeasurement ? existingMeasurementFiles : existingCustomerFiles;

        // 🔥 CHECK IF FILE ALREADY EXISTS ON DRIVE
        if (existingFilesCheck.contains(fileName)) {
          skippedCount++;
          continue; // SKIP THIS UPLOAD
        }

        var driveImageFile = drive.File();
        driveImageFile.name = fileName;
        driveImageFile.parents = [targetFolderId];

        await driveApi.files.create(
          driveImageFile,
          uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
        );

        existingFilesCheck.add(fileName); // Prevent uploading identical duplicates in the same run
        imageCount++;
      }

      String msg = "Backup Complete! JSON uploaded.\nUploaded $imageCount new images.";
      if (skippedCount > 0) msg += "\n(Skipped $skippedCount images already on Drive)";
      _showSuccessMsg(msg);

    } catch (e) {
      _showErrorMsg("Drive Backup error: $e");
    } finally {
      setState(() => _isUploadingToDrive = false);
    }
  }*/



// ==========================================
// ☁️ BACKUP TO GOOGLE SHEETS & DRIVE (BACKGROUND)
// ==========================================
// ☁️ BACKUP TO GOOGLE SHEETS & DRIVE (BACKGROUND)
// ==========================================
Future<void> _backupToGoogleDrive() async {
  // Start loading state
  setState(() => _isUploadingToDrive = true);

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("Your current data is now backing up in the background, please wait..."),
      duration: Duration(seconds: 4),
      backgroundColor: Colors.blueAccent,
      behavior: SnackBarBehavior.floating,
    ),
  );

  try {
    // Trigger the background service
    await BackupService.autoBackupOnAppOpen();

    // Wait a few seconds so the user actually sees the loading spinner
    // while the background microtask runs, then reset the button.
    await Future.delayed(const Duration(seconds: 4));

    if (mounted) {
      _showSuccessMsg("Background sync initiated successfully!");
    }
  } catch (e) {
    if (mounted) _showErrorMsg("Background backup failed to start: $e");
  } finally {
    // Stop loading state and revert the button
    if (mounted) setState(() => _isUploadingToDrive = false);
  }
}




  // ==========================================================
  // 🗂️ GET BASE STORAGE DIRECTORY (SD CARD AWARE)
  // ==========================================================
  Future<Directory> _getBaseStorageDir() async {
    Directory? targetDir;
    try {
      List<Directory>? extDirectories = await getExternalStorageDirectories(type: StorageDirectory.pictures);
      if (extDirectories != null && extDirectories.isNotEmpty) {
        if (extDirectories.length > 1) {
          targetDir = extDirectories[1]; // SD Card
        } else {
          targetDir = extDirectories[0]; // Internal Shared
        }
      }
    } catch (e) {
      print("Error getting external storage: $e");
    }

    if (targetDir == null) {
      targetDir = await getApplicationDocumentsDirectory();
    }
    return targetDir;
  }

  // ==========================================
  // 🗂️ EXPORT IMAGES AS ZIP ARCHIVE (LOCAL SHARE)
  // ==========================================
  Future<void> _exportImagesAsZip() async {
    setState(() => _isExportingImages = true);

    try {
      var encoder = ZipFileEncoder();
      Directory tempDir = await getTemporaryDirectory();
      String zipPath = p.join(tempDir.path, 'asha_grill_images_backup.zip');
      encoder.create(zipPath);

      int imageCount = 0;
      Set<String> filesToZip = {};
      Directory baseDir = await _getBaseStorageDir();

      // Check standard and AshaGrillHouse subdirectories
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
              filesToZip.add(file.path);
            }
          }
        }
      }

      // Read paths directly from DB just like Drive backup
      final db = await DBHelper.db;
      void extractPathsFromDB(List<Map<String, dynamic>> records) {
        for (var row in records) {
          if (row['images'] != null && row['images'].toString().isNotEmpty) {
            List<String> paths = row['images'].toString().split(',');
            for (String pt in paths) {
              if (pt.trim().isNotEmpty && File(pt.trim()).existsSync()) {
                filesToZip.add(pt.trim());
              }
            }
          }
        }
      }
      extractPathsFromDB(await db.query('customers'));
      extractPathsFromDB(await db.query('measurements'));

      for (String filePath in filesToZip) {
        File file = File(filePath);
        String folderName = filePath.toLowerCase().contains('measurements') || filePath.toLowerCase().contains('mesurements')
        ? 'measurements' : 'customers';
        encoder.addFile(file, '$folderName/${p.basename(file.path)}');
        imageCount++;
      }

      encoder.close();

      if (imageCount == 0) {
        _showErrorMsg("No images found to backup.");
        setState(() => _isExportingImages = false);
        return;
      }

      if (mounted) {
        await Share.shareXFiles([XFile(zipPath)], text: 'Asha Grill House - Images Backup ($imageCount images)');
        _showSuccessMsg("Successfully zipped $imageCount images!");
      }
    } catch (e) {
      _showErrorMsg("Image Export failed: $e");
    } finally {
      setState(() => _isExportingImages = false);
    }
  }

  // Helpers for Snackbars
  void _showSuccessMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
  }

  void _showErrorMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
  }

  // ==========================================
  // 🎨 UI DESIGN
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Export & Backup", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.deepOrange,
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
              "Secure your data",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              "Back up your data directly to Google Drive, or export it manually to share via other apps.",
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 32),

            // ☁️ GOOGLE DRIVE EXPORT CARD
            // ☁️ GOOGLE SHEET & DRIVE EXPORT CARD
            _buildExportCard(
              title: "Backup to Google Sheet & Drive",
              description: "Uploads your database text to Google Sheets and saves your active images to Google Drive. Runs seamlessly in the background.",
              icon: Icons.add_to_drive_rounded,
              color: Colors.blueAccent,
              buttonText: "UPLOAD TO SHEET & DRIVE",
              isLoading: _isUploadingToDrive,
              onTap: _backupToGoogleDrive,
            ),

            const SizedBox(height: 24),

            // 📄 DATA EXPORT CARD
            _buildExportCard(
              title: "Export Text Data (JSON)",
              description: "Exports all customers, measurements, and transactions into a clean JSON file. Easily readable and editable on any computer.",
              icon: Icons.data_object_rounded,
              color: Colors.deepOrange,
              buttonText: "SHARE FILE",
              isLoading: _isExportingData,
              onTap: _exportDataAsJson,
            ),

            const SizedBox(height: 24),

            // 🖼️ IMAGE EXPORT CARD
            _buildExportCard(
              title: "Export Images (ZIP)",
              description: "Finds all camera captures and canvas drawings in your app and compresses them into a single ZIP file containing separated 'customers' and 'measurements' folders.",
              icon: Icons.photo_library_rounded,
              color: Colors.teal,
              buttonText: "SHARE FILE",
              isLoading: _isExportingImages,
              onTap: _exportImagesAsZip,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String buttonText,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
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
          onTap: isLoading ? null : onTap,
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
                Text(
                  description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                    ),
                    child: isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(buttonText.contains("DRIVE") ? Icons.cloud_done : Icons.ios_share_rounded, size: 20),
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
