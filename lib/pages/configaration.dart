import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db_helper.dart';

class ConfigarationPage extends StatefulWidget {
  const ConfigarationPage({Key? key}) : super(key: key);

  @override
  _ConfigarationPageState createState() => _ConfigarationPageState();
}

class _ConfigarationPageState extends State<ConfigarationPage> {
  static const String _urlPrefix = "https://script.google.com/macros/s/";

  final _formKey = GlobalKey<FormState>();

  final _scriptUrlController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _currentPassController = TextEditingController();
  final _newPassController = TextEditingController();

  String _storedPassword = "123456"; // Default password if none saved yet
  String _syncStatus = "checking";

  bool _isLoading = false;
  bool _showSecret = false;
  bool _showNewPass = false;
  bool _showCurrentPass = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _scriptUrlController.dispose();
    _secretKeyController.dispose();
    _currentPassController.dispose();
    _newPassController.dispose();
    super.dispose();
  }

  // ==========================================
  // LOAD
  // ==========================================
  Future<void> _loadConfig() async {
    try {
      final cfg = await DBHelper.getSyncConfig();
      final pass = await DBHelper.getAppPassword();

      if (!mounted) return;
      setState(() {
        _scriptUrlController.text = cfg['scriptUrl'] ?? "";
        _secretKeyController.text = cfg['secretKey'] ?? "";

        _storedPassword = (pass == null || pass.isEmpty) ? "123456" : pass;

        // Sync is only "active" when BOTH the URL and the secret key are usable
        final bool urlOk = _validateScriptUrl(cfg['scriptUrl']) == null;
        final bool keyOk = (cfg['secretKey'] ?? "").isNotEmpty;
        _syncStatus = (urlOk && keyOk) ? "active" : "deactive";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncStatus = "deactive");
      _showSnackBar("[CFG-800] Could not load saved settings: $e", Colors.red);
    }
  }

  // ==========================================
  // VALIDATORS  (each message starts with an error code)
  // ==========================================
  String? _validateScriptUrl(String? value) {
    final url = (value ?? "").trim();
    if (url.isEmpty) {
      return "[CFG-101] Script URL is required.";
    }
    final uri = Uri.tryParse(url);
    if (uri == null || url.contains(RegExp(r'\s'))) {
      return "[CFG-102] This is not a valid link (remove any spaces or line breaks).";
    }
    if (!url.startsWith(_urlPrefix)) {
      return "[CFG-103] URL must start with $_urlPrefix";
    }
    if (uri.path.endsWith('/dev')) {
      return "[CFG-104] This is a test (/dev) link. Deploy the script as a Web App and use the link ending in /exec.";
    }
    if (!uri.path.endsWith('/exec')) {
      return "[CFG-105] URL must end with /exec (copy the Web App URL from the Apps Script deployment).";
    }
    return null;
  }

  String? _validateSecretKey(String? value) {
    final key = (value ?? "").trim();
    if (key.isEmpty) {
      return "[CFG-111] Secret Key is required.";
    }
    if (key.contains(RegExp(r'\s'))) {
      return "[CFG-112] Secret Key must not contain spaces or line breaks.";
    }
    if (key.length < 8) {
      return "[CFG-113] Secret Key is too short (minimum 8 characters).";
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    final v = value ?? "";
    if (v.isEmpty) return null; // skipped = keep current password
    if (!RegExp(r'^\d{6}$').hasMatch(v)) {
      return "[CFG-211] New password must be exactly 6 digits.";
    }
    return null;
  }

  String? _validateCurrentPassword(String? value) {
    final v = value ?? "";
    if (v.isEmpty) {
      return "[CFG-201] Current password is required to save changes.";
    }
    if (v != _storedPassword) {
      return "[CFG-202] Current password is incorrect.";
    }
    return null;
  }

  // ==========================================
  // SAVE
  // ==========================================
  Future<void> _saveData() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      _showSnackBar("[CFG-001] Please fix the highlighted fields and try again.", Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String url = _scriptUrlController.text.trim();
      final String key = _secretKeyController.text.trim();

      // If the new password field is skipped, keep the existing password
      final String finalPass =
      _newPassController.text.isNotEmpty ? _newPassController.text : _storedPassword;

      await DBHelper.saveConfig({
        "googleScriptUrl": url,
        "secretKey": key,
        "appPassword": finalPass,
        "status": "active", // URL + key already passed validation
      });

      if (!mounted) return;
      setState(() {
        _storedPassword = finalPass;
        _syncStatus = "active";
        _currentPassController.clear();
        _newPassController.clear();
        _isLoading = false;
      });

      _showSnackBar("Configuration saved. Google Sync is active.", Colors.green);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar("[CFG-900] Could not save settings: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text("System Settings",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                          backgroundColor: Colors.deepOrange,
                     elevation: 0,
                     centerTitle: true,
                     iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Curved header
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

                      // Section 1: Google Apps Script connection
                      _buildSectionCard(
                        title: "Google Script Connection",
                        icon: Icons.add_link_rounded,
                        children: [
                          _buildStyledField(
                            controller: _scriptUrlController,
                            label: "Google Apps Script Web App URL",
                            icon: Icons.link_rounded,
                            hint: "https://script.google.com/macros/s/.../exec",
                            helper: "Apps Script → Deploy → Web app URL (ends with /exec).",
                            keyboardType: TextInputType.url,
                            validator: _validateScriptUrl,
                          ),
                          const SizedBox(height: 18),
                          _buildStyledField(
                            controller: _secretKeyController,
                            label: "Secret Key",
                            icon: Icons.vpn_key_rounded,
                            hint: "Same key that is saved in your Apps Script",
                            helper: "Must match the key inside your Google Apps Script exactly.",
                            obscure: !_showSecret,
                            onToggleObscure: () => setState(() => _showSecret = !_showSecret),
                            validator: _validateSecretKey,
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
                            hint: "Skip this field to keep current password",
                            obscure: !_showNewPass,
                            onToggleObscure: () => setState(() => _showNewPass = !_showNewPass),
                            keyboardType: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            validator: _validateNewPassword,
                          ),
                          const Divider(height: 30, color: Colors.black12),
                          _buildStyledField(
                            controller: _currentPassController,
                            label: "Current Password (Required)",
                            icon: Icons.lock_outline,
                            hint: "Required to authorize any changes",
                            obscure: !_showCurrentPass,
                            onToggleObscure: () => setState(() => _showCurrentPass = !_showCurrentPass),
                            keyboardType: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            isMandatory: true,
                            validator: _validateCurrentPassword,
                          ),
                        ],
                      ),

                      const SizedBox(height: 35),

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
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Text("SAVE CONFIGURATION",
                                       style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
    final bool isActive = _syncStatus.toLowerCase() == 'active';
    final bool isChecking = _syncStatus == 'checking';

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
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
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
                isChecking ? "Loading Status..." : "Sync Status: ${isActive ? 'ACTIVE' : 'INACTIVE'}",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isActive ? Colors.green.shade800 : (isChecking ? Colors.blue.shade800 : Colors.red.shade800),
                ),
              ),
            ],
          ),
          if (!isActive && !isChecking) ...[
            const SizedBox(height: 8),
            Text(
              "Enter a valid Script URL and Secret Key, then save to enable Google backup & restore.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ],
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
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800, letterSpacing: 0.5),
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
    required String? Function(String?) validator,
    bool obscure = false,
    VoidCallback? onToggleObscure, // when set, shows the show/hide eye button
    String? hint,
    String? helper,
    bool isMandatory = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    final bool isSecretField = onToggleObscure != null;

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType ?? TextInputType.text,
      inputFormatters: formatters,
      autocorrect: false,
      enableSuggestions: !isSecretField,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        errorMaxLines: 4,
        helperStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        labelStyle: TextStyle(
          color: isMandatory ? Colors.deepOrange : Colors.grey.shade600,
          fontSize: 14,
          fontWeight: isMandatory ? FontWeight.bold : FontWeight.normal,
        ),
        prefixIcon: Icon(icon, color: isMandatory ? Colors.deepOrange : Colors.grey.shade500, size: 22),
        suffixIcon: isSecretField
        ? IconButton(
          icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                     color: Colors.grey.shade500, size: 20),
                     onPressed: onToggleObscure,
        )
        : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isMandatory ? Colors.deepOrange.shade200 : Colors.grey.shade300, width: isMandatory ? 1.5 : 1),
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
      validator: validator,
    );
  }
}
