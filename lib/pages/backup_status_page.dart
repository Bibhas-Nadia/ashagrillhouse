import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';

class BackupStatusPage extends StatefulWidget {
  const BackupStatusPage({super.key});

  @override
  State<BackupStatusPage> createState() => _BackupStatusPageState();
}

class _BackupStatusPageState extends State<BackupStatusPage> {
  bool _isLoading = true;
  bool _isBackupEnabled = false;
  String _backupDate = "Never";
  String _status = "none";
  String _issue = "No data";

  @override
  void initState() {
    super.initState();
    _loadBackupStatus();
  }

  Future<void> _loadBackupStatus() async {
    setState(() => _isLoading = true);

    try {
      // Load the toggle settings
      final bool enabledSetting = await DBHelper.isBackupEnabled();

      // Fetch status directly from the database table
      final Map<String, dynamic>? backupData = await DBHelper.getBackupStatus();

      setState(() {
        _isBackupEnabled = enabledSetting;
        if (backupData != null) {
          _backupDate = backupData['date']?.toString() ?? 'Unknown Date';
      _status = backupData['status']?.toString() ?? 'failed';
      _issue = backupData['issue']?.toString() ?? 'unknown_error';
        } else {
          _backupDate = "No backups attempted yet";
          _status = "none";
          _issue = "none";
        }
      });
    } catch (e) {
      setState(() {
        _status = "error";
        _issue = "data_corrupted";
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Handle saving toggle switch value changes
  Future<void> _toggleBackup(bool value) async {
    setState(() {
      _isBackupEnabled = value;
    });
    await DBHelper.setBackupEnabled(value);
  }

  Map<String, dynamic> _getStatusVisuals() {
    if (!_isBackupEnabled) {
      return {
        'color': Colors.grey.shade600,
        'icon': Icons.cloud_off_rounded,
        'title': 'Backups Disabled',
        'message': 'Automatic cloud backups are turned off. Your changes are saved locally only.',
      };
    }

    if (_status == 'success') {
      return {
        'color': Colors.green.shade600,
        'icon': Icons.cloud_done_rounded,
        'title': 'Backup Successful',
        'message': 'Your database is safely backed up to the cloud.',
      };
    } else if (_status == 'failed') {
      if (_issue.contains('network') || _issue.contains('SocketException')) {
        return {
          'color': Colors.orange.shade600,
          'icon': Icons.wifi_off_rounded,
          'title': 'Network Issue',
          'message': 'Could not connect to the internet (or connection is too slow).',
        };
      } else {
        return {
          'color': Colors.red.shade600,
          'icon': Icons.error_outline_rounded,
          'title': 'Upload Failed',
          'message': 'There was a problem syncing with the server.',
        };
      }
    } else if (_status == 'none') {
      return {
        'color': Colors.blueGrey,
        'icon': Icons.cloud_sync_rounded,
        'title': 'No Backup Yet',
        'message': 'The app has not attempted a backup yet today.',
      };
    } else {
      return {
        'color': Colors.grey.shade600,
        'icon': Icons.help_outline_rounded,
        'title': 'Unknown Status',
        'message': 'Something went wrong while reading the status.',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final visuals = _getStatusVisuals();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text("Cloud Backup Status", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadBackupStatus,
              tooltip: "Refresh Status",
            )
          ],
      ),
      body: _isLoading
      ? const Center(child: CircularProgressIndicator())
      : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: SwitchListTile(
                  activeColor: Colors.indigo,
                  title: const Text(
                    "Enable Cloud Backup",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Text(
                    _isBackupEnabled ? "App will auto-save data online" : "Saving data offline only",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  value: _isBackupEnabled,
                  onChanged: _toggleBackup,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: visuals['color'].withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                visuals['icon'],
                size: 80,
                color: visuals['color'],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              visuals['title'],
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: visuals['color'],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    "Last Attempt: $_backupDate",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              visuals['message'],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Status Info: $_issue",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontFamily: 'monospace'),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isBackupEnabled ? Colors.indigo.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _isBackupEnabled ? Colors.indigo.shade100 : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: _isBackupEnabled ? Colors.indigo.shade400 : Colors.grey.shade600
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isBackupEnabled
                      ? "Backups happen automatically once a day in the background. If a network issue occurs, the app will try again the next time you open it."
                      : "Cloud sync is disabled. Turn it back on anytime to restart automatic scheduled background cloud saves.",
                      style: TextStyle(
                        fontSize: 13,
                        color: _isBackupEnabled ? Colors.indigo : Colors.grey.shade700
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
