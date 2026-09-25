
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
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

class ClearOnlineBackupPage extends StatefulWidget {
  @override
  _ClearOnlineBackupPageState createState() => _ClearOnlineBackupPageState();
}

class _ClearOnlineBackupPageState extends State<ClearOnlineBackupPage> {
  bool _isChecked = false;
  bool _isDeleting = false;
  String? _cachedPin; // To store the fetched PIN

  // Request the necessary scope right here
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  @override
  void initState() {
    super.initState();
    _initSequence();
  }

  // Load PIN first, then show the dialog
  Future<void> _initSequence() async {
    // Direct database fetch
    String? dbPin = await DBHelper.getAppPassword();

    if (mounted) {
      setState(() {
        // Use 123456 if DB returns null or empty
        _cachedPin = (dbPin == null || dbPin.isEmpty) ? "123456" : dbPin;
      });
      _promptPin();
    }
  }

  // ==========================================================
  // 🔐 PIN VERIFICATION DIALOG
  // ==========================================================
  void _promptPin() {
    TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Admin PIN Required"),
            content: TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: "Enter PIN",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text("CANCEL"),
              ),
              ElevatedButton(
                onPressed: () {
                  String input = pinController.text.trim();

                  // 1. Block empty input
                  if (input.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("PIN cannot be empty!"), backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  // 2. Verify against cached PIN (or default 123456)
                  if (input == _cachedPin) {
                    Navigator.pop(context); // Success
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Incorrect PIN!"), backgroundColor: Colors.red),
                    );
                  }
                },
                child: const Text("VERIFY"),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // 🗑️ DELETE GOOGLE DRIVE FOLDER
  // ==========================================================
  Future<void> _deleteOnlineBackups() async {
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
          "This will permanently delete the '.AshaGrillHouse' folder from your Google Drive. All online backups will be lost. Proceed?",
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
            child: const Text("YES, DELETE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (finalConfirm != true) return;

    setState(() => _isDeleting = true);

    try {
      // 1️⃣ Authenticate with Google Drive (removed unimplemented scope checks)
      GoogleSignInAccount? account = await _googleSignIn.signInSilently();
      account ??= await _googleSignIn.signIn();

      if (account == null) {
        throw Exception("Google Sign-In required to delete backups.");
      }

      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 2️⃣ Search for the '.AshaGrillHouse' folder
      var folderList = await driveApi.files.list(
        q: "name='.AshaGrillHouse' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        $fields: "files(id, name)",
      );

      if (folderList.files == null || folderList.files!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No online backup folder found in Google Drive!"),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _isDeleting = false);
        return;
      }

      // 3️⃣ Delete the folder(s) (Wipes folder + all contents inside)
      int deletedCount = 0;
      for (var folder in folderList.files!) {
        await driveApi.files.delete(folder.id!);
        deletedCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Online Backup successfully deleted!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _isDeleting = false;
          _isChecked = false;
        });
        Navigator.pop(context); // Go back to previous screen
      }
    } catch (e) {
      debugPrint("Delete Error: $e");

      String errorMessage = "Error: $e";

      // Look for the 403 error to give the user a helpful message
      if (e.toString().contains("403") || e.toString().toLowerCase().contains("insufficient")) {
        errorMessage = "Permission Denied! You manually renamed this folder in Drive. Please open the Google Drive app and delete it manually.";
      }

      if (mounted) {
        // Show dialog for 403 error as it requires user action
        if (errorMessage.contains("Permission Denied")) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Manual Action Required"),
              content: Text(errorMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                )
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }

        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Clear Google Drive Backups", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.orange.shade700,
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
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cloud_off_rounded, size: 80, color: Colors.orange.shade800),
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              "Clear Backups",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade300, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.orange.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.drive_folder_upload, color: Colors.orange.shade700, size: 24),
                      const SizedBox(width: 10),
                      Text("What happens?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildBullet("The '.AshaGrillHouse' folder will be completely removed from your Google Drive."),
                  _buildBullet("All backed up JSON data and customer images will be permanently erased online."),
                  _buildBullet("Your local app data (on this phone) will NOT be affected."),
                  const SizedBox(height: 12),
                  const Text(
                    "Use this if your Drive is getting full or if you want to force a completely fresh backup on the next sync.",
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
                  "I understand that this will wipe my Google Drive backup.",
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
                onPressed: (_isChecked && !_isDeleting) ? _deleteOnlineBackups : null,
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
                    Icon(Icons.delete_forever_rounded, size: 24),
                    SizedBox(width: 10),
                    Text(
                      "DELETE BACKUPS",
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
          Icon(Icons.cloud_done_outlined, color: Colors.orange.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade800, fontSize: 15, height: 1.4))),
        ],
      ),
    );
  }
}
