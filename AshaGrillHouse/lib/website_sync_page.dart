// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:encrypt/encrypt.dart' as enc;
// import '../db_helper.dart';
// //import '../github_config.dart';
//
// class WebsiteSyncService {
//
//   static String _getAesKey(String phone) {
//     return phone.padRight(32, '0').substring(0, 32);
//   }
//
//   static String _encryptText(String plainText, String phone) {
//     final key = enc.Key.fromUtf8(_getAesKey(phone));
//     final iv = enc.IV.fromUtf8("1234567890123456");
//     final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
//     return encrypter.encrypt(plainText, iv: iv).base64;
//   }
//
//   static Future<String> _encryptImageBytes(File imgFile, String phone) async {
//     final key = enc.Key.fromUtf8(_getAesKey(phone));
//     final iv = enc.IV.fromUtf8("1234567890123456");
//     final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
//     final imageBytes = await imgFile.readAsBytes();
//     return encrypter.encryptBytes(imageBytes, iv: iv).base64;
//   }
//
//   // 🔥 NEW HELPER: Safely parses dates formatted as "DD-MM-YYYY" or "YYYY-MM-DD"
//   static DateTime _parseCustomDate(String rawDate) {
//     try {
//       // First try Dart's standard parser (for standard YYYY-MM-DD formats)
//       return DateTime.parse(rawDate);
//     } catch (e) {
//       try {
//         // If it fails, manually parse your custom format: "3-5-2026 7:35 PM"
//         String cleanString = rawDate.trim().toUpperCase();
//         bool isPM = cleanString.contains("PM");
//         bool isAM = cleanString.contains("AM");
//
//         cleanString = cleanString.replaceAll(" PM", "").replaceAll(" AM", "");
//
//         List<String> spaceSplit = cleanString.split(" ");
//         List<String> dateParts = spaceSplit[0].split("-");
//
//         if (dateParts.length == 3) {
//           int day = int.parse(dateParts[0]);
//           int month = int.parse(dateParts[1]);
//           int year = int.parse(dateParts[2]);
//
//           // Handle cases where the year is first (YYYY-MM-DD)
//           if (dateParts[0].length == 4) {
//             year = int.parse(dateParts[0]);
//             day = int.parse(dateParts[2]);
//           }
//
//           int hour = 0;
//           int minute = 0;
//
//           if (spaceSplit.length > 1) {
//             List<String> timeParts = spaceSplit[1].split(":");
//             hour = int.parse(timeParts[0]);
//             minute = int.parse(timeParts[1]);
//
//             if (isPM && hour < 12) hour += 12;
//             if (isAM && hour == 12) hour = 0;
//           }
//
//           return DateTime(year, month, day, hour, minute);
//         }
//         return DateTime.now(); // Fallback if format is completely strange
//       } catch (e2) {
//         return DateTime.now(); // Ultimate fallback so app doesn't crash
//       }
//     }
//   }
//
//   static Future<void> _uploadToGithub(String token, String username, String repo, String path, String contentBase64) async {
//     final url = Uri.parse("https://api.github.com/repos/$username/$repo/contents/$path");
//     final getRes = await http.get(url, headers: {"Authorization": "Bearer $token"});
//
//     String? sha;
//     if (getRes.statusCode == 200) sha = jsonDecode(getRes.body)['sha'];
//
//     final body = {"message": "Auto-sync encrypted data", "content": contentBase64};
//     if (sha != null) body["sha"] = sha;
//
//     await http.put(
//       url,
//       headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
//       body: jsonEncode(body),
//     );
//   }
//
//   static Future<void> _cleanupOldImages(String token, String username, String repo, List<String> activeImagePaths) async {
//     debugPrint("🧹 Starting image cleanup check...");
//     final url = Uri.parse("https://api.github.com/repos/$username/$repo/contents/customers/images");
//     final getRes = await http.get(url, headers: {"Authorization": "Bearer $token"});
//
//     if (getRes.statusCode == 200) {
//       final List files = jsonDecode(getRes.body);
//
//       for (var file in files) {
//         String githubPath = file['path'];
//         String fileSha = file['sha'];
//
//         if (!activeImagePaths.contains(githubPath)) {
//           final deleteUrl = Uri.parse("https://api.github.com/repos/$username/$repo/contents/$githubPath");
//           await http.delete(
//             deleteUrl,
//             headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
//             body: jsonEncode({"message": "Cleanup old unused image", "sha": fileSha})
//           );
//           debugPrint("🗑️ Deleted old image: $githubPath");
//         }
//       }
//     }
//   }
//
//   static Future<void> runBackgroundSync() async {
//     try {
//       debugPrint("=========================================");
//       debugPrint("🚀 STARTING SYNC PROCESS");
//       debugPrint("=========================================");
//
//       final config = await DBHelper.getConfig();
//       if (config == null) {
//         debugPrint("❌ ABORT: No configuration found in database.");
//         return;
//       }
//
//       // 3. Extract the values from the Map (using ?? '' as a fallback in case they are null)
//       String token = config['githubToken'] ?? '';
//       String username = config['githubUsername'] ?? '';
//       String repo = config['githubRepo'] ?? '';
//
//       // 4. Validate that none of the fields are empty
//       if (token.isEmpty || username.isEmpty || repo.isEmpty) {
//         debugPrint("❌ ABORT: Missing GitHub Configuration (Token, Username, or Repo is empty).");
//         return;
//       }
//
//
//       // await GithubConfig.loadConfig();
//       // String token = GithubConfig.token;
//       // String username = GithubConfig.username;
//       // String repo = GithubConfig.repo;
//
//       if (token.isEmpty || username.isEmpty || repo.isEmpty) {
//         debugPrint("❌ ABORT: Missing GitHub Configuration.");
//         return;
//       }
//
//       final customers = await DBHelper.getCustomers();
//       DateTime oneMonthAgo = DateTime.now().subtract(const Duration(days: 30));
//       debugPrint("📅 Cutoff Date for 30-day logic: $oneMonthAgo");
//
//       List<Map<String, dynamic>> finalCustomerList = [];
//       List<String> activeGithubImagePaths = [];
//       Set<int> syncedCustomerIds = {};
//
//       // ================================================================
//       // STEP 1: Traverse Customer Table
//       // ================================================================
//       debugPrint("\n--- 🔍 STEP 1: CHECKING CUSTOMERS TABLE ---");
//       for (var c in customers) {
//         debugPrint("👤 Checking ID: ${c.id} | Name: '${c.name}' | Phone: '${c.phone}'");
//
//         if (c.phone.trim().isEmpty) {
//           debugPrint("   ⏭️ SKIPPED: Phone number is empty.");
//           continue;
//         }
//
//         double due = double.tryParse(c.due.toString()) ?? 0.0;
//         DateTime oldDate = DateTime.now(); // Fallback date
//
//         debugPrint("   💰 Raw Due: '${c.due}' -> Parsed: $due");
//         debugPrint("   📅 Raw CreatedAt: '${c.createdAt}'");
//
//         if (c.createdAt.isNotEmpty) {
//           // 🔥 USING THE NEW SAFE PARSER
//           oldDate = _parseCustomDate(c.createdAt);
//           debugPrint("   ✅ Date Parsed Successfully: $oldDate");
//         } else {
//           debugPrint("   ⚠️ CreatedAt is empty! (Falling back to current date)");
//         }
//
//         if (due > 0 && oldDate.isAfter(oneMonthAgo)) {
//           syncedCustomerIds.add(c.id!);
//           debugPrint("   ➕ ADDED TO SYNC: Due is > 0 and within 30 days.");
//         } else {
//           debugPrint("   ❌ FAILED STEP 1: (Due > 0: ${due > 0}) | (Recent: ${oldDate.isAfter(oneMonthAgo)})");
//         }
//       }
//
//       // ================================================================
//       // STEP 2: Traverse Transaction Table
//       // ================================================================
//       debugPrint("\n--- 🔍 STEP 2: CHECKING TRANSACTIONS TABLE (For remaining) ---");
//       for (var c in customers) {
//         if (syncedCustomerIds.contains(c.id!)) continue;
//         if (c.phone.trim().isEmpty) continue;
//
//         debugPrint("👤 Checking Txns for ID: ${c.id} | Name: '${c.name}'");
//         final transactions = await DBHelper.getTransactions(c.id!);
//
//         if (transactions.isEmpty) {
//           debugPrint("   ⏭️ No transactions found.");
//           continue;
//         }
//
//         bool foundMatchingTxn = false;
//         for (var t in transactions) {
//           double amount = double.tryParse(t['amount']?.toString() ?? '0') ?? 0.0;
//           String rawDate = t['date'].toString();
//           debugPrint("   💳 Txn ID: ${t['id']} | Raw Amount: '$amount' | Raw Date: '$rawDate'");
//
//           // 🔥 USING THE NEW SAFE PARSER
//           DateTime tDate = _parseCustomDate(rawDate);
//
//           if (amount > 0 && tDate.isAfter(oneMonthAgo)) {
//             syncedCustomerIds.add(c.id!);
//             foundMatchingTxn = true;
//             debugPrint("   ➕ ADDED TO SYNC: Found recent transaction with amount > 0! ($tDate)");
//             break;
//           }
//         }
//
//         if (!foundMatchingTxn) {
//           debugPrint("   ❌ FAILED STEP 2: No transactions > 0 within last 30 days.");
//         }
//       }
//
//       // ================================================================
//       // STEP 3: Encrypt and process
//       // ================================================================
//       debugPrint("\n--- 📦 STEP 3: PROCESSING & ENCRYPTING DATA ---");
//       debugPrint("🎯 Total customers flagged for sync: ${syncedCustomerIds.length} -> $syncedCustomerIds");
//
//       for (var c in customers) {
//         if (!syncedCustomerIds.contains(c.id!)) continue;
//
//         debugPrint("🔒 Encrypting data for ID: ${c.id} (${c.name})...");
//         try {
//           final transactions = await DBHelper.getTransactions(c.id!);
//           List<String> encryptedImageUrls = [];
//
//           if (c.images.isNotEmpty) {
//             List<String> paths = c.images.split(",").where((s) => s.trim().isNotEmpty).toList();
//             for (String path in paths) {
//               File imgFile = File(path);
//               if (await imgFile.exists()) {
//                 String fileName = path.split('/').last;
//                 String githubPath = "customers/images/$fileName.txt";
//                 String publicUrl = "https://$username.github.io/$repo/$githubPath";
//
//                 activeGithubImagePaths.add(githubPath);
//
//                 bool needsUpload = true;
//                 try {
//                   final checkRes = await http.head(Uri.parse(publicUrl));
//                   if (checkRes.statusCode == 200) needsUpload = false;
//                 } catch (e) {
//                   // Ignore
//                 }
//
//                 if (needsUpload) {
//                   debugPrint("   🚀 Uploading image: $fileName");
//                   String encryptedBase64String = await _encryptImageBytes(imgFile, c.phone);
//                   String githubPayloadBase64 = base64Encode(utf8.encode(encryptedBase64String));
//                   await _uploadToGithub(token, username, repo, githubPath, githubPayloadBase64);
//                 } else {
//                   debugPrint("   ⏭️ Skipped existing image: $fileName");
//                 }
//                 encryptedImageUrls.add(publicUrl);
//               } else {
//                 debugPrint("   ⚠️ Image file missing locally: $path");
//               }
//             }
//           }
//
//           Map<String, dynamic> customerData = {
//             "name": c.name,
//             "phone": c.phone,
//             "address": c.address,
//             "due": c.due,
//             "images": encryptedImageUrls,
//             "transactions": transactions,
//             "createdAt": c.createdAt,
//             "lastUpdated": DateTime.now().toIso8601String()
//           };
//
//           String encryptedStr = _encryptText(jsonEncode(customerData), c.phone);
//
//           finalCustomerList.add({
//             "id": c.id,
//             "data": encryptedStr
//           });
//
//         } catch (e) {
//           debugPrint("❌ FATAL Error processing customer ${c.id}: $e");
//         }
//       }
//
//       // ================================================================
//       // STEP 4: Final JSON Upload
//       // ================================================================
//       debugPrint("\n--- ☁️ STEP 4: UPLOADING JSON TO GITHUB ---");
//       if (finalCustomerList.isNotEmpty) {
//         String finalJsonContent = jsonEncode({"customers": finalCustomerList});
//         String finalJsonBase64 = base64Encode(utf8.encode(finalJsonContent));
//         await _uploadToGithub(token, username, repo, "customers/customer_details.json", finalJsonBase64);
//         debugPrint("✅ Website Sync Completed. Uploaded ${finalCustomerList.length} customers.");
//       } else {
//         debugPrint("⚠️ Website Sync Completed, but NO CUSTOMERS to upload.");
//       }
//
//       await _cleanupOldImages(token, username, repo, activeGithubImagePaths);
//       debugPrint("🎉 SYNC PROCESS FINISHED SUCCESSFULLY.");
//
//     } catch (e) {
//       debugPrint("❌ MAJOR SCRIPT CRASH in WebsiteSyncService: $e");
//     }
//   }
// }


import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as enc;
import '../db_helper.dart';

class WebsiteSyncService {

  static String _getAesKey(String phone) {
    return phone.padRight(32, '0').substring(0, 32);
  }

  static String _encryptText(String plainText, String phone) {
    final key = enc.Key.fromUtf8(_getAesKey(phone));
    final iv = enc.IV.fromUtf8("1234567890123456");
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.encrypt(plainText, iv: iv).base64;
  }

  static Future<String> _encryptImageBytes(File imgFile, String phone) async {
    final key = enc.Key.fromUtf8(_getAesKey(phone));
    final iv = enc.IV.fromUtf8("1234567890123456");
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final imageBytes = await imgFile.readAsBytes();
    return encrypter.encryptBytes(imageBytes, iv: iv).base64;
  }

  static DateTime _parseCustomDate(String rawDate) {
    try {
      return DateTime.parse(rawDate);
    } catch (e) {
      try {
        String cleanString = rawDate.trim().toUpperCase();
        bool isPM = cleanString.contains("PM");
        bool isAM = cleanString.contains("AM");

        cleanString = cleanString.replaceAll(" PM", "").replaceAll(" AM", "");

        List<String> spaceSplit = cleanString.split(" ");
        List<String> dateParts = spaceSplit[0].split("-");

        if (dateParts.length == 3) {
          int day = int.parse(dateParts[0]);
          int month = int.parse(dateParts[1]);
          int year = int.parse(dateParts[2]);

          if (dateParts[0].length == 4) {
            year = int.parse(dateParts[0]);
            day = int.parse(dateParts[2]);
          }

          int hour = 0;
          int minute = 0;

          if (spaceSplit.length > 1) {
            List<String> timeParts = spaceSplit[1].split(":");
            hour = int.parse(timeParts[0]);
            minute = int.parse(timeParts[1]);

            if (isPM && hour < 12) hour += 12;
            if (isAM && hour == 12) hour = 0;
          }

          return DateTime(year, month, day, hour, minute);
        }
        return DateTime.now();
      } catch (e2) {
        return DateTime.now();
      }
    }
  }

  static Future<void> _uploadToGithub(String token, String username, String repo, String path, String contentBase64) async {
    final url = Uri.parse("https://api.github.com/repos/$username/$repo/contents/$path");
    final getRes = await http.get(url, headers: {"Authorization": "Bearer $token"});

    String? sha;
    if (getRes.statusCode == 200) sha = jsonDecode(getRes.body)['sha'];

    final body = {"message": "Auto-sync encrypted data", "content": contentBase64};
    if (sha != null) body["sha"] = sha;

    await http.put(
      url,
      headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
      body: jsonEncode(body),
    );
  }

  static Future<void> _cleanupOldImages(String token, String username, String repo, List<String> activeImagePaths) async {
    debugPrint("🧹 Starting image cleanup check...");
    final url = Uri.parse("https://api.github.com/repos/$username/$repo/contents/customers/images");
    final getRes = await http.get(url, headers: {"Authorization": "Bearer $token"});

    if (getRes.statusCode == 200) {
      final List files = jsonDecode(getRes.body);

      for (var file in files) {
        String githubPath = file['path'];
        String fileSha = file['sha'];

        if (!activeImagePaths.contains(githubPath)) {
          final deleteUrl = Uri.parse("https://api.github.com/repos/$username/$repo/contents/$githubPath");
          await http.delete(
            deleteUrl,
            headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
            body: jsonEncode({"message": "Cleanup old unused image", "sha": fileSha})
          );
          debugPrint("🗑️ Deleted old image: $githubPath");
        }
      }
    }
  }

  static Future<void> runBackgroundSync() async {
    try {
      debugPrint("=========================================");
      debugPrint("🚀 STARTING SYNC PROCESS");
      debugPrint("=========================================");

      final config = await DBHelper.getConfig();
      if (config == null) {
        debugPrint("❌ ABORT: No configuration found in database.");
        return;
      }

      String token = config['githubToken'] ?? '';
      String username = config['githubUsername'] ?? '';
      String repo = config['githubRepo'] ?? '';

      if (token.isEmpty || username.isEmpty || repo.isEmpty) {
        debugPrint("❌ ABORT: Missing GitHub Configuration (Token, Username, or Repo is empty).");
        return;
      }

      final customers = await DBHelper.getCustomers();
      DateTime oneMonthAgo = DateTime.now().subtract(const Duration(days: 30));
      debugPrint("📅 Cutoff Date for 30-day logic: $oneMonthAgo");

      List<Map<String, dynamic>> finalCustomerList = [];
      List<String> activeGithubImagePaths = [];
      Set<int> syncedCustomerIds = {};

      // ================================================================
      // STEP 1: Traverse Customer Table & Bill History JSONs
      // ================================================================
      debugPrint("\n--- 🔍 STEP 1: CHECKING CUSTOMERS & RECEIPT CALCULATIONS ---");
      for (var c in customers) {
        debugPrint("👤 Checking ID: ${c.id} | Name: '${c.name}' | Phone: '${c.phone}'");

        if (c.phone.trim().isEmpty) {
          debugPrint("   ⏭️ SKIPPED: Phone number is empty.");
          continue;
        }

        double due = double.tryParse(c.due.toString()) ?? 0.0;
        DateTime oldDate = DateTime.now();

        debugPrint("   💰 Raw Due: '${c.due}' -> Parsed: $due");
        debugPrint("   📅 Raw CreatedAt: '${c.createdAt}'");

        if (c.createdAt.isNotEmpty) {
          oldDate = _parseCustomDate(c.createdAt);
          debugPrint("   ✅ Date Parsed Successfully: $oldDate");
        } else {
          debugPrint("   ⚠️ CreatedAt is empty! (Falling back to current date)");
        }

        // Feature 1: Keep original logic (profile created within 30 days with balance due)
        if (due > 0 && oldDate.isAfter(oneMonthAgo)) {
          syncedCustomerIds.add(c.id!);
          debugPrint("   ➕ ADDED TO SYNC: Due is > 0 and account created within 30 days.");
          continue;
        }

        // 🔥 FIX FIX FIX: Interrogate JSON receipt log file for newly minted invoices
        String? savedJson = await DBHelper.getReceiptCalculation(c.id!);
        if (savedJson != null && savedJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(savedJson);
            if (decoded is Map && decoded.containsKey('savedBills')) {
              List<dynamic> savedBills = decoded['savedBills'] ?? [];
              bool hasRecentBill = false;

              for (var bill in savedBills) {
                String? billDateStr = bill['date'];
                if (billDateStr != null && billDateStr.isNotEmpty) {
                  DateTime billDate = _parseCustomDate(billDateStr);
                  if (billDate.isAfter(oneMonthAgo)) {
                    hasRecentBill = true;
                    break;
                  }
                }
              }

              if (hasRecentBill) {
                syncedCustomerIds.add(c.id!);
                debugPrint("   ➕ ADDED TO SYNC: Found a newly generated bill in receipt_calculations within 30 days!");
                continue;
              }
            }
          } catch (e) {
            debugPrint("   ⚠️ Error parsing internal receipt calculations JSON for customer ${c.id}: $e");
          }
        }

        debugPrint("   ❌ FAILED STEP 1: Neither profile creation nor active bills are within 30 days.");
      }

      // ================================================================
      // STEP 2: Traverse Transaction Table (For remaining profiles)
      // ================================================================
      debugPrint("\n--- 🔍 STEP 2: CHECKING TRANSACTIONS TABLE (For remaining) ---");
      for (var c in customers) {
        if (syncedCustomerIds.contains(c.id!)) continue;
        if (c.phone.trim().isEmpty) continue;

        debugPrint("👤 Checking Txns for ID: ${c.id} | Name: '${c.name}'");
        final transactions = await DBHelper.getTransactions(c.id!);

        if (transactions.isEmpty) {
          debugPrint("   ⏭️ No transactions found.");
          continue;
        }

        bool foundMatchingTxn = false;
        for (var t in transactions) {
          double amount = double.tryParse(t['amount']?.toString() ?? '0') ?? 0.0;
          String rawDate = t['date'].toString();
          debugPrint("   💳 Txn ID: ${t['id']} | Raw Amount: '$amount' | Raw Date: '$rawDate'");

          DateTime tDate = _parseCustomDate(rawDate);

          if (amount > 0 && tDate.isAfter(oneMonthAgo)) {
            syncedCustomerIds.add(c.id!);
            foundMatchingTxn = true;
            debugPrint("   ➕ ADDED TO SYNC: Found recent transaction with amount > 0! ($tDate)");
            break;
          }
        }

        if (!foundMatchingTxn) {
          debugPrint("   ❌ FAILED STEP 2: No transactions > 0 within last 30 days.");
        }
      }

      // ================================================================
      // STEP 3: Encrypt and process flagged items
      // ================================================================
      debugPrint("\n--- 📦 STEP 3: PROCESSING & ENCRYPTING DATA ---");
      debugPrint("🎯 Total customers flagged for sync: ${syncedCustomerIds.length} -> $syncedCustomerIds");

      for (var c in customers) {
        if (!syncedCustomerIds.contains(c.id!)) continue;

        debugPrint("🔒 Encrypting data for ID: ${c.id} (${c.name})...");
        try {
          final transactions = await DBHelper.getTransactions(c.id!);
          List<String> encryptedImageUrls = [];

          if (c.images.isNotEmpty) {
            List<String> paths = c.images.split(",").where((s) => s.trim().isNotEmpty).toList();
            for (String path in paths) {
              File imgFile = File(path);
              if (await imgFile.exists()) {
                String fileName = path.split('/').last;
                String githubPath = "customers/images/$fileName.txt";
                String publicUrl = "https://$username.github.io/$repo/$githubPath";

                activeGithubImagePaths.add(githubPath);

                bool needsUpload = true;
                try {
                  final checkRes = await http.head(Uri.parse(publicUrl));
                  if (checkRes.statusCode == 200) needsUpload = false;
                } catch (e) {
                  // Ignore URL failures gracefully
                }

                if (needsUpload) {
                  debugPrint("   🚀 Uploading image: $fileName");
                  String encryptedBase64String = await _encryptImageBytes(imgFile, c.phone);
                  String githubPayloadBase64 = base64Encode(utf8.encode(encryptedBase64String));
                  await _uploadToGithub(token, username, repo, githubPath, githubPayloadBase64);
                } else {
                  debugPrint("   ⏭️ Skipped existing image: $fileName");
                }
                encryptedImageUrls.add(publicUrl);
              } else {
                debugPrint("   ⚠️ Image file missing locally: $path");
              }
            }
          }

          Map<String, dynamic> customerData = {
            "name": c.name,
            "phone": c.phone,
            "address": c.address,
            "due": c.due,
            "images": encryptedImageUrls,
            "transactions": transactions,
            "createdAt": c.createdAt,
            "lastUpdated": DateTime.now().toIso8601String()
          };

          String encryptedStr = _encryptText(jsonEncode(customerData), c.phone);

          finalCustomerList.add({
            "id": c.id,
            "data": encryptedStr
          });

        } catch (e) {
          debugPrint("❌ FATAL Error processing customer ${c.id}: $e");
        }
      }

      // ================================================================
      // STEP 4: Final JSON Upload to Git Ecosystem
      // ================================================================
      debugPrint("\n--- ☁️ STEP 4: UPLOADING JSON TO GITHUB ---");
      if (finalCustomerList.isNotEmpty) {
        String finalJsonContent = jsonEncode({"customers": finalCustomerList});
        String finalJsonBase64 = base64Encode(utf8.encode(finalJsonContent));
        await _uploadToGithub(token, username, repo, "customers/customer_details.json", finalJsonBase64);
        debugPrint("✅ Website Sync Completed. Uploaded ${finalCustomerList.length} customers.");
      } else {
        debugPrint("⚠️ Website Sync Completed, but NO CUSTOMERS to upload.");
      }

      await _cleanupOldImages(token, username, repo, activeGithubImagePaths);
      debugPrint("🎉 SYNC PROCESS FINISHED SUCCESSFULLY.");

    } catch (e) {
      debugPrint("❌ MAJOR SCRIPT CRASH in WebsiteSyncService: $e");
    }
  }
}
