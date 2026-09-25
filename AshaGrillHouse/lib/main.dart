
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 👈 IMPORTED FOR EXITING APP
import 'package:app_links/app_links.dart';

// Import your pages
import 'pages/home_page.dart';
import 'pages/customers_page.dart';
import 'pages/expenses_page.dart';
import 'pages/measurement_page.dart';
import 'pages/splash_screen.dart';
import 'pages/payment_page.dart';
import 'auto_backup_service.dart';

// 1. Define a Global Navigator Key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Customer App",
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        // CHANGED: Perfect grayish-white background
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: SplashScreen(),
      routes: {
        '/payment': (context) => const PaymentPage(),
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

// Update your MainScreenState definition:
class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int index = 0;
  late AppLinks _appLinks;

  DateTime? currentBackPressTime; // 👈 NEW: Variable to track back button presses

  final List<Widget> pages = [
    HomePage(),
    CustomersPage(),
    MeasurementPage(),
    ExpensesPage(),
  ];

  @override
  void initState() {
    super.initState();
    _initDeepLinks();

    // Start listening to app lifecycle globally
    WidgetsBinding.instance.addObserver(this);

    // Trigger backup when app completely starts
    _triggerGlobalBackup();
  }

  @override
  void dispose() {
    // Stop listening when app closes entirely
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Trigger backup when app comes back from background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerGlobalBackup();
    }
  }

  // This function handles the deep link logic
  void _initDeepLinks() {
    _appLinks = AppLinks();

    // Handle link when app is in background or foreground
    _appLinks.uriLinkStream.listen((uri) {
      _handleNavigation(uri);
    });

    // Handle link when app is opened from a completely closed state
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleNavigation(uri);
    });
  }

  void _handleNavigation(Uri uri) {
    // If the link is https://ashagrillhouse.github.io/site/admin
    if (uri.path == '/admin' || uri.path == '/site/admin') {
      navigatorKey.currentState?.pushNamed('/admin');
    }
  }

  // The global backup runner
  Future<void> _triggerGlobalBackup() async {
    print("==================STARTING AUTO BACKUP======================");
    BackupStatus status = await AutoBackupService.checkAndRunDailyBackup();

    if (!mounted) return;

    // Show a small message ONLY on brand new success
    if (status == BackupStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 12),
              Text("Daily backup saved to Cloud!"),
            ],
          ),
          backgroundColor: Colors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
      print("==================== SUCCESS BACKUP =========================");
    }
    else
    {
      print("==================== ERROR BACKUP =========================");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 👈 NEW: Wrap the entire Scaffold in a PopScope
    return PopScope(
      canPop: false, // Prevent immediate exit
      onPopInvoked: (bool didPop) {
        if (didPop) return;

        DateTime now = DateTime.now();
        if (currentBackPressTime == null ||
          now.difference(currentBackPressTime!) > const Duration(seconds: 2)) {

          currentBackPressTime = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Press back again to close app"),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
          } else {
            SystemNavigator.pop(); // Close app on double tap
          }
      },
      child: Scaffold(
        body: pages[index],
        // Adding a subtle shadow to the navigation bar itself
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: index,
            elevation: 0,

            backgroundColor: Colors.white,

            // CHANGED: Dark colors so the text is visible on white background
            selectedItemColor: Colors.deepOrange,
            unselectedItemColor: Colors.grey,

            // Decreased font size slightly to tighten padding
            selectedFontSize: 18.0,
            unselectedFontSize: 16.0,

            type: BottomNavigationBarType.fixed,
            onTap: (i) => setState(() => index = i),

            // Using a helper method to keep code perfectly clean and apply shadows
            items: [
              _buildNavItem('assets/images/home.png', 'হোম'),
              _buildNavItem('assets/images/hisab.png', 'হিসাব'),
              _buildNavItem('assets/images/maf.png', 'মাপ'),
              _buildNavItem('assets/images/khoroch.png', 'খরচ'),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to perfectly align images, decrease padding, and add shadows
  BottomNavigationBarItem _buildNavItem(String imagePath, String label) {
    return BottomNavigationBarItem(
      // Unselected State
      icon: Container(
        margin: const EdgeInsets.only(bottom: 1), // Reduces padding between image and text
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1), // Light shadow
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Image.asset(imagePath, width: 38, height: 38),
      ),

      // Selected State (Slightly larger with a stronger shadow)
      activeIcon: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12), // Stronger shadow
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Image.asset(imagePath, width: 45, height: 45),
      ),
      label: label,
    );
  }
}
