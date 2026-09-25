import 'dart:io';
import 'dart:convert';
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

class ImportPage extends StatefulWidget {
  @override
  _ImportPageState createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  bool _isImportingData = false;
  bool _isImportingImages = false;
  bool _isImportingFromDrive = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  @override
  void initState() {
    super.initState();
  }

  // ==========================================================
  // 🗂️ SD CARD & INTERNAL STORAGE FINDER (From Add Customer Page)
  // ==========================================================
  Future<Directory> _getTargetDirectory(String subFolder) async {
    print("==================================================");
    print("📁 [IMPORT] TARGETING 'Pictures/.AshaGrillHouse/$subFolder'");
    print("==================================================");

    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }

    String? sdCardRootPath;
    String internalRootPath = '/storage/emulated/0';

    try {
      final List<Directory>? extDirs = await getExternalStorageDirectories();
      if (extDirs != null && extDirs.length > 1) {
        String appSpecificSdPath = extDirs[1].path;
        int androidIndex = appSpecificSdPath.indexOf('/Android/');
        if (androidIndex != -1) {
          sdCardRootPath = appSpecificSdPath.substring(0, androidIndex);
        }
      }
    } catch (e) {
      print("❌ Error finding SD card directories: $e");
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
        print("⚠️ OS Blocked SD Card 'Pictures' access: $e");
      }
    }

    // ATTEMPT 2: Internal Storage
    targetFolder = Directory("$internalRootPath/Pictures/.AshaGrillHouse/$subFolder");
    if (!await targetFolder.exists()) {
      await targetFolder.create(recursive: true);
    }
    return targetFolder;
  }

  // ==========================================
  // ☁️ IMPORT FROM GOOGLE DRIVE (JSON + SEPARATE IMAGE FOLDERS)
  // ==========================================
  Future<void> _importFromGoogleDrive() async {
    setState(() => _isImportingFromDrive = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Connecting to Google Drive... Please wait."), duration: Duration(seconds: 3))
    );

    try {
      // 1. Sign In
      GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        _showErrorMsg("Google Sign-In Cancelled.");
        setState(() => _isImportingFromDrive = false);
        return;
      }

      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 2. Find AshaGrillHouse main folder
      var folderList = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and name='.AshaGrillHouse' and trashed=false",
        $fields: "files(id, name)"
      );
      if (folderList.files == null || folderList.files!.isEmpty) {
        throw Exception(".AshaGrillHouse folder not found on Google Drive.");
      }
      String mainFolderId = folderList.files!.first.id!;

      // 3. Find latest JSON file
      var jsonList = await driveApi.files.list(
        q: "'$mainFolderId' in parents and name contains '.json' and trashed=false",
        orderBy: "createdTime desc",
        $fields: "files(id, name)"
      );
      if (jsonList.files == null || jsonList.files!.isEmpty) {
        throw Exception("No JSON backup file found in the Drive folder.");
      }
      String jsonFileId = jsonList.files!.first.id!;

      // 4. Download and Parse JSON
      var response = await driveApi.files.get(jsonFileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      List<int> dataStore = [];
      await for (var data in response.stream) {
        dataStore.addAll(data);
      }
      String jsonString = utf8.decode(dataStore);
      Map<String, dynamic> jsonData = jsonDecode(jsonString);

      // 5. Setup Local Directories & Map DB Paths
      Directory customersDir = await _getTargetDirectory("customers");
      Directory measurementsDir = await _getTargetDirectory("measurements");

      final db = await DBHelper.db;
      List<String> tables = ['customers', 'transactions', 'tempcustomer', 'measurements', 'expenses', 'orders','messages','pins','price_agreements','receipt_calculations','expense_keywords'];

      Map<String, String> expectedImageLocations = {};

      for (String table in tables) {
        if (jsonData.containsKey(table)) {
          await db.delete(table); // Clear existing local table

          for (var row in jsonData[table]) {
            if (row.containsKey('images') && row['images'] != null && row['images'].toString().isNotEmpty) {
              List<String> oldPaths = row['images'].toString().split(',');
              List<String> newPaths = [];
              for (String oldP in oldPaths) {
                if (oldP.trim().isEmpty) continue;
                String fName = p.basename(oldP.trim());

                // Read the exact subfolder from the old path mapping
                String targetDirPath = customersDir.path;
                if (oldP.toLowerCase().contains('/measurements/') || oldP.toLowerCase().contains('/mesurements/')) {
                  targetDirPath = measurementsDir.path;
                }

                String newTargetLocalPath = "$targetDirPath/$fName";
                newPaths.add(newTargetLocalPath);
                expectedImageLocations[fName] = newTargetLocalPath;
              }
              row['images'] = newPaths.join(',');
            }
            await db.insert(table, row);
          }
        }
      }

      // 6. Function to download all images from a specific Drive folder
      Future<int> downloadDriveFolderImages(String folderName) async {
        int count = 0;
        var driveFolderReq = await driveApi.files.list(
          q: "mimeType='application/vnd.google-apps.folder' and name='$folderName' and '$mainFolderId' in parents and trashed=false",
          $fields: "files(id, name)"
        );

        if (driveFolderReq.files == null || driveFolderReq.files!.isEmpty) return 0;
        String folderId = driveFolderReq.files!.first.id!;

        String? pageToken;
        do {
          var fileList = await driveApi.files.list(
            q: "'$folderId' in parents and trashed=false",
            $fields: "nextPageToken, files(id, name)",
            pageSize: 1000,
            pageToken: pageToken,
          );

          if (fileList.files != null) {
            for (var f in fileList.files!) {
              if (f.id == null || f.name == null) continue;
              String fName = f.name!;

              String targetPath;
              if (expectedImageLocations.containsKey(fName)) {
                targetPath = expectedImageLocations[fName]!;
              } else {
                String subF = folderName;
                String baseDir = subF == "measurements" ? measurementsDir.path : customersDir.path;
                targetPath = "$baseDir/$fName";
              }

              File localFile = File(targetPath);
              if (!localFile.existsSync()) {
                var imgMedia = await driveApi.files.get(f.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
                var sink = localFile.openWrite();
                await imgMedia.stream.pipe(sink);
                await sink.close();
                count++;
              }
            }
          }
          pageToken = fileList.nextPageToken;
        } while (pageToken != null);
        return count;
      }

      // 7. Download from both separated Drive folders
      int downloadedCustomers = await downloadDriveFolderImages("customers");
      int downloadedMeasurements = await downloadDriveFolderImages("measurements");
      int totalImages = downloadedCustomers + downloadedMeasurements;

      _showSuccessMsg("Import Complete! Database loaded.\nDownloaded $totalImages new images.");

    } catch (e) {
      _showErrorMsg("Drive Import failed: $e");
    } finally {
      setState(() => _isImportingFromDrive = false);
    }
  }

  // ==========================================
  // 📄 LOCAL IMPORT: JSON FILE (Manual)
  // ==========================================
  Future<void> _importDataFromJson() async {
    setState(() => _isImportingData = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String jsonString = await file.readAsString();
        Map<String, dynamic> jsonData = jsonDecode(jsonString);

        final db = await DBHelper.db;
        Directory customersDir = await _getTargetDirectory("customers");
        Directory measurementsDir = await _getTargetDirectory("measurements");

        List<String> tables = ['customers', 'transactions', 'tempcustomer', 'measurements', 'expenses', 'orders','messages','pins','price_agreements','receipt_calculations','expense_keywords'];

        for (String table in tables) {
          if (jsonData.containsKey(table)) {
            await db.delete(table);
            for (var row in jsonData[table]) {

              if (row.containsKey('images') && row['images'] != null && row['images'].toString().isNotEmpty) {
                List<String> oldPaths = row['images'].toString().split(',');
                List<String> newPaths = [];
                for (String oldP in oldPaths) {
                  if (oldP.trim().isEmpty) continue;
                  String fName = p.basename(oldP.trim());

                  String targetDirPath = customersDir.path;
                  if (oldP.toLowerCase().contains('/measurements/') || oldP.toLowerCase().contains('/mesurements/')) {
                    targetDirPath = measurementsDir.path;
                  }
                  newPaths.add("$targetDirPath/$fName");
                }
                row['images'] = newPaths.join(',');
              }
              await db.insert(table, row);
            }
          }
        }
        _showSuccessMsg("Database imported successfully!");
      }
    } catch (e) {
      _showErrorMsg("Data Import failed: $e");
    } finally {
      setState(() => _isImportingData = false);
    }
  }

  // ==========================================
  // 🗂️ LOCAL IMPORT: ZIP FILE (Images)
  // ==========================================
  Future<void> _importImagesFromZip() async {
    setState(() => _isImportingImages = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null) {
        File zipFile = File(result.files.single.path!);
        List<int> bytes = zipFile.readAsBytesSync();
        Archive archive = ZipDecoder().decodeBytes(bytes);

        Directory customersDir = await _getTargetDirectory("customers");
        Directory measurementsDir = await _getTargetDirectory("measurements");

        int count = 0;
        for (ArchiveFile file in archive) {
          if (file.isFile) {
            // Check if file path within the zip contains measurements
            bool isMeasurement = file.name.toLowerCase().contains('measurements') || file.name.toLowerCase().contains('mesurements');
            Directory targetDir = isMeasurement ? measurementsDir : customersDir;

            String filename = p.basename(file.name);
            File outFile = File(p.join(targetDir.path, filename));
            outFile.createSync(recursive: true);
            outFile.writeAsBytesSync(file.content as List<int>);
            count++;
          }
        }
        _showSuccessMsg("Successfully extracted $count images!");
      }
    } catch (e) {
      _showErrorMsg("Image Import failed: $e");
    } finally {
      setState(() => _isImportingImages = false);
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

            // ☁️ GOOGLE DRIVE IMPORT CARD
            _buildImportCard(
              title: "Restore from Google Drive",
              description: "Fetches your latest database and automatically downloads all missing images into SD Card/Pictures.",
              icon: Icons.cloud_download_rounded,
              color: Colors.blueAccent,
              buttonText: "FETCH FROM DRIVE",
              isLoading: _isImportingFromDrive,
              onTap: _importFromGoogleDrive,
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
                Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5)),
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
