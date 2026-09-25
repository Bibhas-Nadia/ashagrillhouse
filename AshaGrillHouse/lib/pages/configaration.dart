import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../db_helper.dart';

class ConfigarationPage extends StatefulWidget {
  @override
  _ConfigarationPageState createState() => _ConfigarationPageState();
}

class _ConfigarationPageState extends State<ConfigarationPage> {
  final _formKey = GlobalKey<FormState>();

  final _tokenController = TextEditingController();
  final _userController = TextEditingController();
  final _repoController = TextEditingController();
  final _currentPassController = TextEditingController();
  final _newPassController = TextEditingController();

  // Keep stored values in memory to avoid overwriting them with blanks
  String? _storedToken;
  String? _storedUser;
  String? _storedRepo;
  String? _storedPassword;
  String _githubStatus = "checking"; // Used for UI display

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() async {
    // Because of the updated DBHelper methods, we fetch them individually
    final config = await DBHelper.getConfig();
    final pass = await DBHelper.getAppPassword();
    final status = await DBHelper.getStatus();

    if (mounted) {
      setState(() {
        // Load into memory, but DO NOT populate controllers to keep the UI clean!
        if (config != null) {
          _storedToken = config['githubToken'];
          _storedUser = config['githubUsername'];
          _storedRepo = config['githubRepo'];
        }
        _storedPassword = pass;
        _githubStatus = status ?? "deactive"; // Default to deactive if null
      });
    }
  }

  // Verify GitHub credentials using the GitHub API
  Future<bool> _verifyGitHubConnection(String token, String username, String repo) async {
    if (token.isEmpty || username.isEmpty || repo.isEmpty) return false;

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$username/$repo'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );
      // Status 200 means the repository exists and the token has access
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("GitHub Verification Error: $e");
      return false;
    }
  }

  void _saveData() async {
    if (_formKey.currentState!.validate()) {
      // Verify current password if one exists in DB
      if (_storedPassword != null && _storedPassword!.isNotEmpty) {
        if (_currentPassController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please enter current password to save changes!"), backgroundColor: Colors.red),
          );
          return;
        }
        if (_currentPassController.text != _storedPassword) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Current password is incorrect!"), backgroundColor: Colors.red),
          );
          return;
        }
      }

      setState(() => _isLoading = true);

      // Determine final values (use typed ones if present, else fallback to memory)
      String finalToken = _tokenController.text.isNotEmpty ? _tokenController.text : (_storedToken ?? "");
      String finalUser = _userController.text.isNotEmpty ? _userController.text : (_storedUser ?? "");
      String finalRepo = _repoController.text.isNotEmpty ? _repoController.text : (_storedRepo ?? "");
      String finalPass = _newPassController.text.isNotEmpty ? _newPassController.text : (_storedPassword ?? "");

      // Verify connection to GitHub API
      bool isValidConnection = await _verifyGitHubConnection(finalToken, finalUser, finalRepo);
      String newStatus = isValidConnection ? "active" : "deactive";

      // Save new values
      Map<String, dynamic> configData = {
        "githubToken": finalToken,
        "githubUsername": finalUser,
        "githubRepo": finalRepo,
        "appPassword": finalPass,
        "status": newStatus, // 🔥 Now passing the calculated status
      };

      await DBHelper.saveConfig(configData);

      if (mounted) {
        setState(() {
          // Update stored variables with the newly saved data
          _storedToken = configData['githubToken'];
          _storedUser = configData['githubUsername'];
          _storedRepo = configData['githubRepo'];
          _storedPassword = configData['appPassword'];
          _githubStatus = newStatus;

          // Ensure all fields are cleared immediately after saving
          _tokenController.clear();
          _userController.clear();
          _repoController.clear();
          _currentPassController.clear();
          _newPassController.clear();

          _isLoading = false;
        });

        // Clear keyboard focus to dismiss the keyboard
        FocusScope.of(context).unfocus();

        // Show appropriate success/error message based on GitHub validation
        if (isValidConnection) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Configuration Saved! GitHub Connection Active."), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Saved, but GitHub connection failed. Check credentials."),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("System Settings", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Gradient Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              decoration: const BoxDecoration(
                color: Colors.deepOrange,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: const Column(
                children: [
                  Icon(Icons.settings_input_component, size: 50, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    "GitHub & Security Config",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Status Badge
                    _buildStatusBadge(),
                    const SizedBox(height: 20),

                    // GitHub Section
                    _buildSectionCard(
                      title: "Source Control",
                      children: [
                        _buildStyledField(_tokenController, "GitHub Access Token", Icons.vpn_key, hint: "Leave blank to keep existing"),
                        _buildStyledField(_userController, "GitHub Username", Icons.person_outline, hint: "Leave blank to keep existing"),
                        _buildStyledField(_repoController, "Repository Name", Icons.folder_special_outlined, hint: "Leave blank to keep existing"),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Security Section
                    _buildSectionCard(
                      title: "Security",
                      children: [
                        _buildStyledField(
                          _currentPassController,
                          "Current Password (6 digits)",
                          Icons.lock_outline,
                          isPassword: true,
                          isNumeric: true,
                          hint: "Required to save changes",
                        ),
                        _buildStyledField(
                          _newPassController,
                          "Set New Password (6 digits)",
                          Icons.lock_reset_rounded,
                          isPassword: true,
                          isNumeric: true,
                          hint: "Leave blank to keep existing",
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            elevation: 4,
                            disabledBackgroundColor: Colors.deepOrange.shade200,
                        ),
                        child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
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
          ],
        ),
      ),
    );
  }

  // 🔥 NEW: Stylized Status Badge showing Database Status
  Widget _buildStatusBadge() {
    bool isActive = _githubStatus.toLowerCase() == 'active';
    bool isChecking = _githubStatus == 'checking';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : (isChecking ? Colors.blue.shade50 : Colors.red.shade50),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isActive ? Colors.green.shade300 : (isChecking ? Colors.blue.shade300 : Colors.red.shade300),
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
                : "GitHub Status: ${isActive ? 'ACTIVE' : 'INACTIVE'}",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.green.shade800 : (isChecking ? Colors.blue.shade800 : Colors.red.shade800),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 1),
          ),
          const Divider(height: 25),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStyledField(
    TextEditingController controller,
    String label,
    IconData icon,
    {bool isPassword = false, bool isNumeric = false, String? hint}
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          prefixIcon: Icon(icon, color: Colors.deepOrange, size: 22),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.deepOrange, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
        validator: (value) {
          if (value != null && value.isNotEmpty) {
            if (isNumeric && value.length != 6) return "Must be exactly 6 digits";
          }
          return null;
        },
      ),
    );
  }
}
