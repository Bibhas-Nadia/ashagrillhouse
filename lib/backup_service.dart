import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'db_helper.dart';

class BackupService {
  static const String SECRET_API_KEY = "89faa837458e8dbc66de416fa04f9466b462d2b77a2b3065d9d6e7cc58288777";
  // 🟢 Add this lock variable
  static bool _isSyncing = false;

  static Future<http.Response> _postToGoogle(String scriptUrl, Map<String, dynamic> body) async {
    final client = http.Client();
    try {
      // Use http.Request to disable auto-redirects. Standard http.post auto-follows
      // and loses the payload/headers, which breaks Google Apps Script APIs.
      final request = http.Request('POST', Uri.parse(scriptUrl))
      ..headers["Content-Type"] = "application/json"
      ..body = jsonEncode(body)
      ..followRedirects = false;

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      // Manually handle the 302/303 redirect that Google Apps Script uses
      if (response.statusCode == 302 || response.statusCode == 303) {
        String? redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          return await http.get(Uri.parse(redirectUrl));
        }
      }
      return response;
    } finally {
      client.close();
    }
  }

  static Future<void> autoBackupOnAppOpen() async {
    // 🟢 Prevent overlapping backups
    if (_isSyncing) {
      debugPrint("⏳ Backup already in progress. Skipping duplicate request.");
      return;
    }

    _isSyncing = true; // 🟢 Lock the sync process


    // Removed Future.microtask so this Future actually awaits completion when called.
    String currentDate = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());

    try {
      bool isEnabled = await DBHelper.isBackupEnabled();
      if (!isEnabled) {
        debugPrint("⚠️ Backup skipped: Disabled by user.");
        return;
      }

      final config = await DBHelper.getConfig();
      String scriptUrl = config?['googleScriptUrl']?.toString().trim() ?? "";

      if (scriptUrl.isEmpty || !scriptUrl.startsWith("https://script.google.com/macros/s/")) {
        await DBHelper.saveBackupStatus(currentDate, "failed", "Invalid Google Script URL.");
        return;
      }

      debugPrint("🔄 Starting True Sync Engine...");
      final dbClient = await DBHelper.db;

      // 1. Gather all active images from local database
      List<String> allTableNames = await DBHelper.getAllTableNames();
      Set<String> activeImageFilenames = {};
      Map<String, String> localFileMap = {};

      for (String tableName in allTableNames) {
        if (tableName.startsWith('sqlite_') || tableName == 'android_metadata') continue;

        final columns = await dbClient.rawQuery("PRAGMA table_info($tableName)");
        bool hasImagesColumn = columns.any((col) => col['name'] == 'images');

        if (hasImagesColumn) {
          final rows = await dbClient.query(tableName, where: 'images != "" AND images IS NOT NULL');
          for (var row in rows) {
            String imgPaths = row['images'].toString();
            for (String path in imgPaths.split(',')) {
              String trimmedPath = path.trim();
              if (trimmedPath.isEmpty) continue;

              String fileName = trimmedPath.split('/').last;
              activeImageFilenames.add(fileName);
              localFileMap[fileName] = trimmedPath;
            }
          }
        }
      }

      // 2. Gather text data
      Map<String, dynamic> businessData = {};
      for (String tableName in allTableNames) {
        if (tableName.startsWith('sqlite_') || tableName == 'android_metadata') continue;
        businessData[tableName] = await dbClient.query(tableName);
      }

      // 3. Send Text + Image Status to Google
      final textResponse = await _postToGoogle(scriptUrl, {
        "apiKey": SECRET_API_KEY,
        "action": "full_text_backup",
        "database": businessData,
        "active_images": activeImageFilenames.toList()
      });

      if (textResponse.statusCode != 200 || !textResponse.body.contains("success")) {
        throw Exception("Backup failed: ${textResponse.body}");
      }

      // 4. Read True Missing Files from Google Server (with safety net for bad JSON)
      Map<String, dynamic> responseData;
      try {
        responseData = jsonDecode(textResponse.body);
      } catch (e) {
        throw Exception("Invalid JSON response from server. Body: ${textResponse.body}");
      }

      List<dynamic> rawMissingImages = responseData['missing_images'] ?? [];
      List<String> trueMissingImages = rawMissingImages.map((e) => e.toString()).toList();

      debugPrint("✅ Text synced. Server reports ${trueMissingImages.length} missing images.");

      // 5. Upload strictly the missing files
      for (String fileName in trueMissingImages) {
        String? filePath = localFileMap[fileName];
        if (filePath == null) continue;

        File file = File(filePath);
        if (await file.exists()) {
          String base64Image = base64Encode(await file.readAsBytes());

          final imgResponse = await _postToGoogle(scriptUrl, {
            "apiKey": SECRET_API_KEY,
            "action": "upload_image",
            "filename": fileName,
            "mimeType": "image/jpeg",
            "base64": base64Image
          });

          if (imgResponse.statusCode == 200) {
            debugPrint("📸 Successfully restored to Drive: $fileName");
          } else {
            debugPrint("⚠️ Failed to restore image: $fileName (Status: ${imgResponse.statusCode})");
          }
        }
      }

      // Deletion step removed from Flutter: Google Apps Script handles orphans in real-time now!

      await DBHelper.saveBackupStatus(currentDate, "success", "none");
      debugPrint("🎉 True Synchronization complete!");

    } catch (e) {
      debugPrint("📡 Sync Error: $e");
      await DBHelper.saveBackupStatus(currentDate, "failed", e.toString());
    }finally {
      // 🟢 Unlock the sync process whether it succeeded or failed
      _isSyncing = false;
    }
  }
}
