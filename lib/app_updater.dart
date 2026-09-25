import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ota_update/ota_update.dart';
import 'package:device_info_plus/device_info_plus.dart';

class AppUpdater {
  static const String jsonUrl = "https://ashagrillhouse.github.io/site/app/update.json";

  static Future<void> checkForUpdate(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    // 1. Get current version as a raw String (e.g., "3.0.0")
    String currentVersion = packageInfo.version.replaceAll(RegExp(r'[^0-9.]'), '');

    // Load offline saved states (using a new key to avoid conflicts with the old double type)
    String savedTargetVersion = prefs.getString('target_version_str') ?? "0.0.0";
    String savedApkUrl = prefs.getString('apk_url') ?? "";
    String savedUpdateText = prefs.getString('update_text') ?? "New Update Available!";
    String savedDeadlineStr = prefs.getString('deadline_str') ?? "";

    // 2. Try to fetch fresh data from GitHub Pages
    try {
      final response = await http.get(Uri.parse(jsonUrl));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        // Safely extract version as a String (handles both "3.0.1" and 3.0)
        String newVersion = data['version'].toString();
        String updateText = data['update'];
        String deadlineStr = data['deadline'] ?? "";

        if (_isNewVersionGreater(newVersion, currentVersion)) {
          bool is64Bit = true;
          if (Platform.isAndroid) {
            DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
            AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
            is64Bit = androidInfo.supported64BitAbis.isNotEmpty;
          }

          String apkUrl = is64Bit ? data['apk_url_64'] : data['apk_url_32'];

          // Save requirement to persistent memory (Offline support)
          await prefs.setString('target_version_str', newVersion);
          await prefs.setString('apk_url', apkUrl);
          await prefs.setString('update_text', updateText);
          await prefs.setString('deadline_str', deadlineStr);

          // Update local variables for immediate display
          savedTargetVersion = newVersion;
          savedApkUrl = apkUrl;
          savedUpdateText = updateText;
          savedDeadlineStr = deadlineStr;
        } else {
          // If app is fully updated, clear saved state
          await _clearUpdateData(prefs);
          return;
        }
      }
    } catch (e) {
      debugPrint("Update check failed. Using offline saved state. Error: $e");
    }

    // 3. Display logic (Works both online & offline)
    if (_isNewVersionGreater(savedTargetVersion, currentVersion) && savedApkUrl.isNotEmpty) {
      DateTime? deadlineDate = _parseDeadline(savedDeadlineStr);

      // If time has passed the deadline, force the update!
      bool isForceUpdate = deadlineDate != null ? DateTime.now().isAfter(deadlineDate) : false;

      if (context.mounted) {
        _showUpdateDialog(
          context,
          savedUpdateText,
          savedApkUrl,
          savedDeadlineStr,
          isForceUpdate,
        );
      }
    } else if (!_isNewVersionGreater(savedTargetVersion, currentVersion)) {
      await _clearUpdateData(prefs);
    }
  }

  // 🔥 NEW MATHEMTICAL VERSION COMPARISON LOGIC
  // Returns true if newVersion > currentVersion (e.g., "3.0.1" > "3.0.0")
  static bool _isNewVersionGreater(String newVersion, String currentVersion) {
    List<int> newV = newVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> currV = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Pad arrays to ensure we always compare 3 parts (Major.Minor.Patch)
    while (newV.length < 3) newV.add(0);
    while (currV.length < 3) currV.add(0);

    for (int i = 0; i < 3; i++) {
      if (newV[i] > currV[i]) return true;  // e.g., 3.1.0 > 3.0.0
      if (newV[i] < currV[i]) return false; // e.g., 2.9.0 < 3.0.0
    }
    return false; // They are exactly equal
  }

  // Parses "26/08/26 09:50pm" into a Dart DateTime object
  static DateTime? _parseDeadline(String deadlineStr) {
    try {
      final parts = deadlineStr.trim().split(' ');
      if (parts.length < 2) return null;

      final dateParts = parts[0].split('/');
      int day = int.parse(dateParts[0]);
      int month = int.parse(dateParts[1]);
      int year = int.parse(dateParts[2]);
      if (year < 100) year += 2000;

      String timeStr = parts[1].toLowerCase();
      bool isPm = timeStr.contains('pm');
      bool isAm = timeStr.contains('am');
      timeStr = timeStr.replaceAll('am', '').replaceAll('pm', '');

      final timeParts = timeStr.split(':');
      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1]);

      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      debugPrint("Error parsing deadline date: $e");
      return null;
    }
  }

  static Future<void> _clearUpdateData(SharedPreferences prefs) async {
    await prefs.remove('target_version_str');
    await prefs.remove('target_version'); // Clean up old double key
    await prefs.remove('apk_url');
    await prefs.remove('update_text');
    await prefs.remove('deadline_str');
  }

  static void _showUpdateDialog(
    BuildContext context,
    String updateText,
    String apkUrl,
    String deadlineStr,
    bool isForceUpdate
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: !isForceUpdate,
          child: _UpdateDialogWidget(
            changelog: updateText,
            apkUrl: apkUrl,
            deadlineStr: deadlineStr,
            isForceUpdate: isForceUpdate,
          ),
        );
      },
    );
  }
}

class _UpdateDialogWidget extends StatefulWidget {
  final String changelog;
  final String apkUrl;
  final String deadlineStr;
  final bool isForceUpdate;

  const _UpdateDialogWidget({
    required this.changelog,
    required this.apkUrl,
    required this.deadlineStr,
    required this.isForceUpdate,
  });

  @override
  State<_UpdateDialogWidget> createState() => _UpdateDialogWidgetState();
}

class _UpdateDialogWidgetState extends State<_UpdateDialogWidget> {
  String _statusMessage = "";
  double _progress = 0.0;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _statusMessage = widget.isForceUpdate
    ? "Deadline passed! Update required to continue."
    : "Deadline: ${widget.deadlineStr}";
  }

  void _startDownload() {
    setState(() {
      _isDownloading = true;
      _statusMessage = "Starting Download...";
      _progress = 0.0;
    });

    try {
      OtaUpdate().execute(widget.apkUrl, destinationFilename: 'app_update.apk').listen(
        (OtaEvent event) {
          setState(() {
            if (event.status == OtaStatus.DOWNLOADING) {
              _progress = double.parse(event.value ?? "0") / 100;
              _statusMessage = "Downloading... ${event.value}%";
            } else if (event.status == OtaStatus.INSTALLING) {
              _statusMessage = "Opening Installer...";
              _progress = 1.0;
              _isDownloading = false;
            } else {
              _statusMessage = "Failed. Please try again.";
              _isDownloading = false;
            }
          });
        },
      );
    } catch (e) {
      setState(() {
        _statusMessage = "Download Failed!";
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.isForceUpdate ? "🚨 Mandatory Update" : "⚠️ Update Available",
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.changelog, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 20),
          Text(
            _statusMessage,
            style: TextStyle(
              color: widget.isForceUpdate ? Colors.red.shade700 : Colors.deepOrange.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          if (_isDownloading)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey.shade300,
              color: Colors.deepOrange,
              minHeight: 8,
            ),
        ],
      ),
      actions: [
        if (!widget.isForceUpdate && !_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Skip for now", style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          if (!_isDownloading)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _startDownload,
              child: const Text("Download & Install", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
      ],
    );
  }
}
