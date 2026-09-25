import 'package:flutter/material.dart';
import '../db_helper.dart';

class ConfigarationPage extends StatefulWidget {
  const ConfigarationPage({Key? key}) : super(key: key);

  @override
  _ConfigarationPageState createState() => _ConfigarationPageState();
}

class _ConfigarationPageState extends State<ConfigarationPage> {
  final _formKey = GlobalKey<FormState>();

  final _scriptUrlController = TextEditingController();
  final _currentPassController = TextEditingController();
  final _newPassController = TextEditingController();

  String _storedPassword = "123456"; // Default password stored securely in logic
  String _syncStatus = "checking";

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _scriptUrlController.dispose();
    _currentPassController.dispose();
    _newPassController.dispose();
    super.dispose();
  }

  void _loadConfig() async {
    final config = await DBHelper.getConfig();
    final pass = await DBHelper.getAppPassword();
    final status = await DBHelper.getStatus();

    if (mounted) {
      setState(() {
        // Auto-fill the existing URL so it is easy to view or keep when changing the password
        if (config != null && config['googleScriptUrl'] != null) {
          _scriptUrlController.text = config['googleScriptUrl'];
        }

        // Ensure default logic applies if password is not found in DB
        _storedPassword = (pass == null || pass.isEmpty) ? "123456" : pass;
        _syncStatus = status ?? "deactive";
      });
    }
  }

  bool _verifyScriptUrl(String url) {
    if (url.isEmpty) return false;
    return url.startsWith("https://script.google.com/macros/s/");
  }

  void _saveData() async {
    if (!_formKey.currentState!.validate()) return;

    // Current password is strictly required to authorize any saves
    if (_currentPassController.text.isEmpty) {
      _showSnackBar("Current password is required to save changes!", Colors.red);
      return;
    }

    if (_currentPassController.text != _storedPassword) {
      _showSnackBar("Current password is incorrect!", Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    // Get the URL (whether the user typed a new one or kept the auto-filled one)
    String finalUrl = _scriptUrlController.text.trim();

    // If the new password field is skipped, keep the existing password
    String finalPass = _newPassController.text.isNotEmpty
    ? _newPassController.text
    : _storedPassword;

    bool isValidUrl = _verifyScriptUrl(finalUrl);
    String newStatus = isValidUrl ? "active" : "deactive";

    Map<String, dynamic> configData = {
      "googleScriptUrl": finalUrl,
      "appPassword": finalPass,
      "status": newStatus,
    };

    await DBHelper.saveConfig(configData);

    if (mounted) {
      setState(() {
        _storedPassword = configData['appPassword'];
        _syncStatus = newStatus;

        // Clear password fields for security, keep URL visible
        _currentPassController.clear();
        _newPassController.clear();
        _isLoading = false;
      });

      FocusScope.of(context).unfocus();

      if (isValidUrl) {
        _showSnackBar("Configuration Saved! Google Sync Active.", Colors.green);
      } else {
        _showSnackBar("Saved, but Script URL appears invalid or empty.", Colors.orange);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9), // Soft background color for contrast
      appBar: AppBar(
        title: const Text("System Settings", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Modern Curved Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 20, bottom: 50, left: 20, right: 20),
              decoration: const BoxDecoration(
                color: Colors.deepOrange,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: const Column(
                children: [
                  Icon(Icons.cloud_sync_rounded, size: 55, color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    "Cloud Data & Security",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 5),
                  Text(
                    "Manage your backup link and app access",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            // Form Content Shifted Upwards to float over the header
            Transform.translate(
              offset: const Offset(0, -30),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildStatusBadge(),
                      const SizedBox(height: 20),

                      // Section 1: Google Script URL
                      _buildSectionCard(
                        title: "Google Drive Sync URL",
                        icon: Icons.add_link_rounded,
                        children: [
                          _buildStyledField(
                            controller: _scriptUrlController,
                            label: "Google Apps Script Web App URL",
                            icon: Icons.link_rounded,
                            hint: "https://script.google.com/macros/s/...",
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Section 2: Security
                      _buildSectionCard(
                        title: "App Security",
                        icon: Icons.security_rounded,
                        children: [
                          _buildStyledField(
                            controller: _newPassController,
                            label: "Set New Password (6 digits)",
                            icon: Icons.lock_reset_rounded,
                            isPassword: true,
                            isNumeric: true,
                            hint: "Skip this field to keep current password",
                          ),
                          const Divider(height: 30, color: Colors.black12),
                          _buildStyledField(
                            controller: _currentPassController,
                            label: "Current Password (Required)",
                            icon: Icons.lock_outline,
                            isPassword: true,
                            isNumeric: true,
                            hint: "Required to authorize any changes",
                            isMandatory: true, // Highlights visually
                          ),
                        ],
                      ),

                      const SizedBox(height: 35),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              elevation: 5,
                              shadowColor: Colors.deepOrange.withOpacity(0.4),
                              disabledBackgroundColor: Colors.deepOrange.shade200,
                          ),
                          child: _isLoading
                          ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                          )
                          : const Text(
                            "SAVE CONFIGURATION",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    bool isActive = _syncStatus.toLowerCase() == 'active';
    bool isChecking = _syncStatus == 'checking';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 8)),
        ],
        border: Border.all(
          color: isActive ? Colors.green.shade400 : (isChecking ? Colors.blue.shade400 : Colors.red.shade400),
          width: 1.5
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isChecking)
            const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(
                isActive ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: isActive ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                isChecking
                ? "Loading Status..."
                : "Sync Status: ${isActive ? 'ACTIVE' : 'INACTIVE'}",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isActive ? Colors.green.shade800 : (isChecking ? Colors.blue.shade800 : Colors.red.shade800),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.deepOrange, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStyledField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isNumeric = false,
    String? hint,
    bool isMandatory = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        labelStyle: TextStyle(color: isMandatory ? Colors.deepOrange : Colors.grey.shade600, fontSize: 14, fontWeight: isMandatory ? FontWeight.bold : FontWeight.normal),
        prefixIcon: Icon(icon, color: isMandatory ? Colors.deepOrange : Colors.grey.shade500, size: 22),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isMandatory ? Colors.deepOrange.shade200 : Colors.grey.shade300, width: isMandatory ? 1.5 : 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepOrange, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
      ),
      validator: (value) {
        if (value != null && value.isNotEmpty) {
          if (isNumeric && value.length != 6) return "Password must be exactly 6 digits";
        }
        return null;
      },
    );
  }
}
