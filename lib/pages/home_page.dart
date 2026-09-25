
import 'package:flutter/material.dart';

import 'view_report.dart';
import 'dismantle_page.dart';
import 'import_page.dart';
import 'export_page.dart';
import 'payment_page.dart';
import 'backup_status_page.dart';
import 'order_page.dart';
//import 'journey_page.dart';
import 'configaration.dart';
import 'documentation_page.dart';
import 'transaction_history_page.dart';
import 'database_studio.dart';
import 'geometry_calculator_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Asha Grill House",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // 🖼️ Owner's Image at the top right
            Builder(
              builder: (context) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: GestureDetector(
                    onTap: () => Scaffold.of(context).openDrawer(),
                    child: const CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white24,
                      backgroundImage: AssetImage('assets/images/admin.png'), // Loads owner image from assets
                    ),
                  ),
                );
              },
            ),
          ],
      ),
      drawer: _buildModernDrawer(context),
      body: const SafeArea(
        child: PaymentPage(),
      ),
    );
  }

  // 🔥 Completely Redesigned Modern Drawer
  Widget _buildModernDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // 🖼️ Unified Drawer Header (Logo Only)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, bottom: 30, left: 24, right: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepOrange.shade400, Colors.deepOrange.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 220,
                      height: 70,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox(
                          width: 140,
                          height: 60,
                          child: Center(
                            child: Icon(Icons.handyman_rounded, size: 40, color: Colors.deepOrange),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 📜 Drawer List Items & Introduction
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              physics: const BouncingScrollPhysics(),
              children: [
                // 🌟 Beautiful Business Introduction Card (Shortened)
                _buildIntroCard(),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  child: Text(
                    "MENU",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

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
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionHistoryPage())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.list_alt_rounded,
                  title: "Order Page",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderPage())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.list_alt_rounded,
                  title: "Geometry Calculation",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GeometryCalculatorPage())),
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
                // _buildDrawerItem(
                //   context,
                //   icon: Icons.explore_rounded,
                //   title: "Journey",
                //   onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperJourneyPage())),
                // ),
                _buildDrawerItem(
                  context,
                  icon: Icons.display_settings,
                  title: "Configuration",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConfigarationPage())),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.description,
                  title: "Documentation",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentationPage())),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Color(0xFFE2E8F0), thickness: 1.5),
                ),

                // ☁️ DATABASE STUDIO
                _buildDrawerItem(
                  context,
                  icon: Icons.storage_rounded,
                  title: "Database Studio",
                  iconColor: Colors.orange,
                  textColor: Colors.orange.shade800,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DbStudioPage())),
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

          // 🏷️ Footer
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0, top: 8.0),
            child: Text(
              "App Version 3.1.0",
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // 🌟 Helper method for the Shortened Introduction Card
  Widget _buildIntroCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepOrange.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.deepOrange.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ASHA GRILL HOUSE",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.deepOrange,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Expert Craftsmanship Since 2015",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
              fontStyle: FontStyle.italic,
            ),
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFF1F5F9)),

          Row(
            children: [
              Icon(Icons.person, size: 16, color: Colors.deepOrange.shade300),
              const SizedBox(width: 8),
              const Text(
                "Biggyan Das",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const Spacer(),
              Icon(Icons.phone, size: 16, color: Colors.deepOrange.shade300),
              const SizedBox(width: 6),
              const Text(
                "9932134803",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
              ),
            ],
          ),

          const SizedBox(height: 12),

          const Text(
            "Quality iron and steel fabrication in Muragachha with fair pricing, durable design, and on-time service.",
            style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
            textAlign: TextAlign.justify,
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
      margin: const EdgeInsets.only(bottom: 10),
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
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                )
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
                  child: Icon(icon, color: activeIconColor, size: 22),
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
