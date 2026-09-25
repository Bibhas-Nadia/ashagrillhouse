import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'view_report.dart';
import 'dismantle_page.dart';
import 'import_page.dart';
import 'export_page.dart';
import 'payment_page.dart';
import 'clear_online_backup.dart';
import 'backup_status_page.dart';
import 'order_page.dart';
import 'journey_page.dart';
import 'configaration.dart';
import 'documentation_page.dart';
import 'transaction_history_page.dart';
import 'database_studio.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Google Sign-In Setup
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  GoogleSignInAccount? _currentUser;

  @override
  void initState() {
    super.initState();
    // Listen for Google Auth state changes
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      if (mounted) {
        setState(() {
          _currentUser = account;
        });
      }
    });

    // Silently sign in if the user already authorized the app before
    _googleSignIn.signInSilently();
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      debugPrint("Sign in error: $error");
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (error) {
      debugPrint("Sign out error: $error");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Asha Grill House", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // 🖼️ Google Profile Picture (DP) replacing the 3-dot menu
            if (_currentUser != null)
              Builder(
                builder: (context) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(), // Opens drawer when tapping DP
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white24,
                        // 🔥 Updated to use the admin.png asset as the fallback image
                        backgroundImage: _currentUser!.photoUrl != null
                        ? NetworkImage(_currentUser!.photoUrl!) as ImageProvider
                        : const AssetImage('assets/images/admin.png') as ImageProvider,
                      ),
                    ),
                  );
                }
              )
          ],
      ),
      drawer: _buildModernDrawer(context),
      body: SafeArea(
        child: PaymentPage(currentUser: _currentUser),
      ),
    );
  }

  // 🔥 Completely Redesigned Modern Drawer
  Widget _buildModernDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // 🖼️ Unified Drawer Header (Logo + Dynamic User Info)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, bottom: 20, left: 24, right: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepOrange.shade400, Colors.deepOrange.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔹 ALWAYS SHOW LOGO (Regardless of Login State)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 225,
                      height: 70,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox(
                          width: 140,
                          height: 60,
                          child: Center(
                            child: Icon(Icons.restaurant, size: 36, color: Colors.deepOrange),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 🔹 DYNAMIC USER SECTION
                if (_currentUser != null) ...[
                  Text(
                    _currentUser!.displayName ?? "User",
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentUser!.email,
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 36,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _handleSignOut,
                      icon: const Icon(Icons.sync_alt_rounded, size: 18),
                      label: const Text("Change Account / Logout", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ] else ...[
                  const Text(
                    "Not Logged In",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _handleSignIn,
                      icon: const Icon(Icons.login_rounded, size: 20),
                      label: const Text("Sign in with Google", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepOrange.shade700,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ]
              ],
            ),
          ),

          // 📜 Drawer List Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.bar_chart_rounded,
                  title: "Report",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ViewReport())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.receipt_long,
                  title: "Credit History",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>  TransactionHistoryPage())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.list_alt_rounded,
                  title: "Order Page",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderPage())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.file_download_rounded,
                  title: "Import Data",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImportPage())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.ios_share_rounded,
                  title: "Export Data",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExportPage())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.cloud_sync_rounded,
                  title: "Backup Status",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupStatusPage())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.explore_rounded,
                  title: "Journey",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperJourneyPage())),
                ),


                _buildDrawerItem(
                  context,
                  icon: Icons.display_settings,
                  title: "Github Configaration",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>  ConfigarationPage())),
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.description,
                  title: "Documentation",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>  DocumentationPage())),
                ),



                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Color(0xFFE2E8F0), thickness: 1.5),
                ),


                // ☁️ CLEAR ONLINE BACKUPS BUTTON
                _buildDrawerItem(
                  context,
                  icon: Icons.storage_rounded,
                  title: "Database Studio",
                  iconColor: Colors.orange,
                  textColor: Colors.orange.shade800,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DbStudioPage())),
                ),


                // ☁️ CLEAR ONLINE BACKUPS BUTTON
                _buildDrawerItem(
                  context,
                  icon: Icons.cloud_off_rounded,
                  title: "Clear Google Drive",
                  iconColor: Colors.orange,
                  textColor: Colors.orange.shade800,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClearOnlineBackupPage())),
                ),

                // 🗑️ FACTORY RESET
                _buildDrawerItem(
                  context,
                  icon: Icons.delete_forever_rounded,
                  title: "Factory Reset",
                  iconColor: Colors.redAccent,
                  textColor: Colors.redAccent,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DismantlePage())),
                ),
              ],
            ),
          ),

          // 🏷️ Footer (Version number updated to 2.2.0)
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Text(
              "App Version 2.8.0",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // 🛠️ Helper method to build large, easy-to-touch list items
  Widget _buildDrawerItem(
    BuildContext context, {
      required IconData icon,
      required String title,
      required VoidCallback onTap,
      Color? iconColor,
      Color? textColor,
    }) {
    final Color activeIconColor = iconColor ?? Colors.deepOrange;
    final Color activeTextColor = textColor ?? const Color(0xFF0F172A);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          splashColor: activeIconColor.withOpacity(0.1),
          highlightColor: activeIconColor.withOpacity(0.05),
          onTap: () {
            Navigator.pop(context); // Close the drawer first
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: activeIconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: activeIconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: activeTextColor,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
    }
}
