/*import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:google_sign_in/google_sign_in.dart';

class DismantlePage extends StatefulWidget {
  @override
  _DismantlePageState createState() => _DismantlePageState();
}

class _DismantlePageState extends State<DismantlePage> {
  bool _isChecked = false;
  bool _isDeleting = false;

  // Initialize Google Sign In instance
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _dismantleEverything() async {
    // Double confirmation popup
    bool? finalConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text("WARNING", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "This is irreversible. All customers, dues, measurements, pictures will be permanently destroyed, and your Google account will be signed out. Are you absolutely sure?",
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("YES, DESTROY", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (finalConfirm != true) return;

    setState(() => _isDeleting = true);

    try {
      // 1️⃣ Delete SQLite Database
      String databasesPath = await getDatabasesPath();
      String dbPath = p.join(databasesPath, 'asha_grill_house.db');
      await deleteDatabase(dbPath);
      debugPrint("✅ Database deleted.");

      // 2️⃣ Delete Images from SD Card & Internal Storage
      Future<void> deleteImages(Directory dir) async {
        if (await dir.exists()) {
          List<FileSystemEntity> files = dir.listSync(recursive: true);
          for (var file in files) {
            if (file is File && (file.path.endsWith('.jpg') || file.path.endsWith('.png') || file.path.endsWith('.jpeg'))) {
              await file.delete();
            }
          }
        }
      }

      Directory? extDir;
      try {
        List<Directory>? extDirectories = await getExternalStorageDirectories(type: StorageDirectory.pictures);
        if (extDirectories != null && extDirectories.isNotEmpty) {
          extDir = extDirectories.length > 1 ? extDirectories[1] : extDirectories[0];
        }
      } catch (e) {
        debugPrint("SD Card error: $e");
      }

      // If SD card not found, fallback to internal documents
      extDir ??= await getApplicationDocumentsDirectory();

      List<Directory> targetDirs = [
        Directory("${extDir.path}/.AshaGrillHouse/customers"),
        Directory("${extDir.path}/.AshaGrillHouse/measurements"),
        Directory("${extDir.path}/customers"),
        Directory("${extDir.path}/measurements")
      ];

      for (var dir in targetDirs) {
        await deleteImages(dir);
      }
      debugPrint("✅ Images deleted.");

      // 3️⃣ Disconnect Google Account (Sign Out)
      try {
        await _googleSignIn.disconnect();
        debugPrint("✅ Google Account disconnected.");
      } catch (e) {
        // Fallback to regular signOut if disconnect fails
        try {
          await _googleSignIn.signOut();
          debugPrint("✅ Google Account signed out.");
        } catch (e2) {
          debugPrint("❌ Failed to sign out: $e2");
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Factory Reset Complete! App is fully wiped."),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _isDeleting = false;
          _isChecked = false;
        });

        // Optionally pop the user back to the home screen after resetting
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Factory Reset", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.redAccent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded, size: 80, color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              "Danger Zone",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.redAccent.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                      const SizedBox(width: 10),
                      Text("What happens?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildBullet("All customer profiles will be deleted."),
                  _buildBullet("All transaction records & dues will be lost."),
                  _buildBullet("All locally saved measurement & customer photos will be erased."),
                  _buildBullet("You will be signed out of your Google Account."),
                  const SizedBox(height: 12),
                  const Text(
                    "Your Google Drive backups will NOT be deleted, but the local app will be completely empty.",
                    style: TextStyle(fontSize: 14, color: Colors.black54, fontStyle: FontStyle.italic),
                  )
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Checkbox for safety
            Container(
              decoration: BoxDecoration(
                color: _isChecked ? Colors.red.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _isChecked ? Colors.redAccent : Colors.grey.shade300),
              ),
              child: CheckboxListTile(
                value: _isChecked,
                activeColor: Colors.redAccent,
                title: const Text(
                  "I understand that this action is permanent and cannot be undone.",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                onChanged: (val) {
                  setState(() {
                    _isChecked = val ?? false;
                  });
                },
              ),
            ),

            const SizedBox(height: 24),

            // Dismantle Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: (_isChecked && !_isDeleting) ? _dismantleEverything : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  disabledBackgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: _isChecked ? 8 : 0,
                    shadowColor: Colors.redAccent.withOpacity(0.5),
                ),
                child: _isDeleting
                ? const CircularProgressIndicator(color: Colors.white)
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.warning_rounded, size: 24),
                    SizedBox(width: 10),
                    Text(
                      "DISMANTLE",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 18)),
          Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade800, fontSize: 15, height: 1.4))),
        ],
      ),
    );
  }
}*/



import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for SystemNavigator.pop()
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Required to clear ghost UI data
// Included to ensure scopes match during logout
import 'package:googleapis/drive/v3.dart' as drive;

class DismantlePage extends StatefulWidget {
  @override
  _DismantlePageState createState() => _DismantlePageState();
}

class _DismantlePageState extends State<DismantlePage> {
  bool _isChecked = false;
  bool _isDeleting = false;

  // Added the exact scope you use for backup so it fully disconnects
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  Future<void> _dismantleEverything() async {
    // Double confirmation popup
    bool? finalConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text("WARNING", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "This is irreversible. All customers, dues, measurements, pictures will be permanently destroyed, and your Google account will be signed out. Are you absolutely sure?",
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("YES, DESTROY", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (finalConfirm != true) return;

    setState(() => _isDeleting = true);

    // We will catch errors but ensure ALL steps try to run
    List<String> warningMessages = [];

    // ======================================================
    // 1️⃣ Delete SQLite Database & ALL Hidden Caches
    // ======================================================
    try {
      String databasesPath = await getDatabasesPath();
      String dbPath = p.join(databasesPath, 'customer.db');

      // A. Delete the main database file
      await databaseFactory.deleteDatabase(dbPath);

      // B. 🚨 CRITICAL FIX: Delete the hidden SQLite WAL (Write-Ahead Log) cache files
      // If these aren't deleted, Android/iOS will magically restore your data!
      File walFile = File('$dbPath-wal');
      File shmFile = File('$dbPath-shm');
      File journalFile = File('$dbPath-journal');

      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();
      if (await journalFile.exists()) await journalFile.delete();

      debugPrint("✅ Database and all hidden cache files completely destroyed.");
    } catch (e) {
      warningMessages.add("DB Issue");
      debugPrint("❌ Database Deletion error: $e");
    }

    // ======================================================
    // 1.5️⃣ Wipe SharedPreferences (Ghost UI Data)
    // ======================================================
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // This wipes any locally saved settings, PINs, or cached UI data
      debugPrint("✅ SharedPreferences cleared.");
    } catch (e) {
      debugPrint("❌ SharedPreferences error: $e");
    }

    // ======================================================
    // 2️⃣ Delete Images and Folders from ALL Storages
    // ======================================================
    try {
      List<Directory> baseDirectories = [];

      // Get internal app directory
      baseDirectories.add(await getApplicationDocumentsDirectory());

      // Get external SD Card directories (Wrapped in try-catch in case of permission issues)
      try {
        List<Directory>? extDirectories = await getExternalStorageDirectories(type: StorageDirectory.pictures);
        if (extDirectories != null && extDirectories.isNotEmpty) {
          baseDirectories.addAll(extDirectories);
        }
      } catch (e) {
        debugPrint("External Directory fetch error (safe to ignore): $e");
      }

      // Look for these specific folders to completely wipe
      List<String> foldersToWipe = [
        '.AshaGrillHouse',
        'AshaGrillHouse', // Kept your old folder name just in case
        'customers',
        'measurements'
      ];

      for (var baseDir in baseDirectories) {
        for (var folderName in foldersToWipe) {
          Directory targetDir = Directory(p.join(baseDir.path, folderName));

          if (await targetDir.exists()) {
            try {
              // Delete the entire folder at once recursively (Faster & Safer)
              await targetDir.delete(recursive: true);
              debugPrint("✅ Deleted folder: ${targetDir.path}");
            } catch (e) {
              debugPrint("❌ Could not delete folder ${targetDir.path}: $e");
            }
          }
        }
      }
    } catch (e) {
      warningMessages.add("File Cleanup Issue");
      debugPrint("❌ General File Cleanup Error: $e");
    }

    // ======================================================
    // 3️⃣ Disconnect Google Account (Sign Out)
    // ======================================================
    try {
      // First, check if the user is signed in locally
      bool isSignedIn = await _googleSignIn.isSignedIn();

      if (!isSignedIn) {
        // If not signed in locally, they might still have an active token online. Attempt silent sign-in to properly wipe it.
        await _googleSignIn.signInSilently();
        isSignedIn = await _googleSignIn.isSignedIn();
      }

      if (isSignedIn) {
        try {
          await _googleSignIn.disconnect(); // Revokes token completely
          debugPrint("✅ Google Account disconnected completely.");
        } catch (e) {
          await _googleSignIn.signOut(); // Fallback if disconnect fails
          debugPrint("✅ Google Account signed out locally.");
        }
      }
    } catch (e) {
      warningMessages.add("Sign-Out Issue");
      debugPrint("❌ Google Sign Out Error: $e");
    }

    // ======================================================
    // 🏁 Final UI Updates & App Exit
    // ======================================================
    if (mounted) {
      setState(() {
        _isDeleting = false;
        _isChecked = false;
      });

      if (warningMessages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Factory Reset Complete! App is closing..."),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("App wiped and closing. (Warnings: ${warningMessages.join(', ')})"),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // Force close the app to dump all old data from memory!
      Future.delayed(const Duration(seconds: 2), () {
        SystemNavigator.pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Factory Reset", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.redAccent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded, size: 80, color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              "Danger Zone",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.redAccent.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                      const SizedBox(width: 10),
                      Text("What happens?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildBullet("All customer profiles will be deleted."),
                  _buildBullet("All transaction records & dues will be lost."),
                  _buildBullet("All locally saved measurement & customer photos will be erased."),
                  _buildBullet("You will be signed out of your Google Account."),
                  const SizedBox(height: 12),
                  const Text(
                    "Your Google Drive backups will NOT be deleted, but the local app will be completely empty.",
                    style: TextStyle(fontSize: 14, color: Colors.black54, fontStyle: FontStyle.italic),
                  )
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Checkbox for safety
            Container(
              decoration: BoxDecoration(
                color: _isChecked ? Colors.red.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _isChecked ? Colors.redAccent : Colors.grey.shade300),
              ),
              child: CheckboxListTile(
                value: _isChecked,
                activeColor: Colors.redAccent,
                title: const Text(
                  "I understand that this action is permanent and cannot be undone.",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                onChanged: (val) {
                  setState(() {
                    _isChecked = val ?? false;
                  });
                },
              ),
            ),

            const SizedBox(height: 24),

            // Dismantle Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: (_isChecked && !_isDeleting) ? _dismantleEverything : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  disabledBackgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: _isChecked ? 8 : 0,
                    shadowColor: Colors.redAccent.withOpacity(0.5),
                ),
                child: _isDeleting
                ? const CircularProgressIndicator(color: Colors.white)
                : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_rounded, size: 24),
                    SizedBox(width: 10),
                    Text(
                      "DISMANTLE",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 18)),
          Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade800, fontSize: 15, height: 1.4))),
        ],
      ),
    );
  }
}
