import 'package:flutter/material.dart';

class DeveloperJourneyPage extends StatelessWidget {
  const DeveloperJourneyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text("My App Journey", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.deepOrange.shade600,
        foregroundColor: Colors.white,
          elevation: 0,
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 🔹 HEADER SECTION
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 30, top: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepOrange.shade600, Colors.orangeAccent.shade400],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepOrange.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: const Column(
                children: [
                  Icon(Icons.timeline_rounded, size: 60, color: Colors.white),
                  SizedBox(height: 15),
                  Text(
                    "Asha Grill House POS",
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "From Arch Linux to a fully functional POS system. Every single step of the journey from April 9 to April 19.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
          ),

          // 🔹 TIMELINE SECTION
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final step = journeySteps[index];
                  final isLast = index == journeySteps.length - 1;
                  return _TimelineTile(
                    step: step,
                    isLast: isLast,
                    delay: Duration(milliseconds: (index % 10) * 100), // Staggered animation batch
                  );
                },
                childCount: journeySteps.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 🔹 TIMELINE TILE WIDGET
class _TimelineTile extends StatelessWidget {
  final JourneyStep step;
  final bool isLast;
  final Duration delay;

  const _TimelineTile({
    required this.step,
    required this.isLast,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutQuart,
      builder: (context, double value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left side: Line and Icon
            SizedBox(
              width: 50,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: step.color.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: step.color, width: 2),
                    ),
                    child: Icon(step.icon, color: step.color, size: 20),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 3,
                        color: step.color.withOpacity(0.3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 15),

            // Right side: Content Card
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 25.0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.date,
                        style: TextStyle(
                          color: step.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
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
}

// 🔹 DATA MODEL
class JourneyStep {
  final String date;
  final String title;
  final IconData icon;
  final Color color;

  JourneyStep({
    required this.date,
    required this.title,
    required this.icon,
    required this.color,
  });
}

// 🔹 EXACT STEP-BY-STEP JOURNEY DATA
final List<JourneyStep> journeySteps = [
  JourneyStep(date: "09.04.26", title: "Problem identification", icon: Icons.psychology_rounded, color: Colors.blue),
  JourneyStep(date: "09.04.26", title: "Learned Flutter from YouTube", icon: Icons.play_circle_fill_rounded, color: Colors.red),
  JourneyStep(date: "09.04.26", title: "Installed Flutter in my Arch Linux", icon: Icons.terminal_rounded, color: Colors.deepPurple),
  JourneyStep(date: "09.04.26", title: "Ran first Flutter code", icon: Icons.code_rounded, color: Colors.blueAccent),

  JourneyStep(date: "10.04.26", title: "Ran code in my original mobile", icon: Icons.smartphone_rounded, color: Colors.teal),
  JourneyStep(date: "10.04.26", title: "Understood the widgets and its elements", icon: Icons.widgets_rounded, color: Colors.orange),
  JourneyStep(date: "10.04.26", title: "Ready to create a project", icon: Icons.rocket_launch_rounded, color: Colors.deepOrange),

  JourneyStep(date: "11.04.26", title: "Listed Asha Grill House problems", icon: Icons.assignment_late_rounded, color: Colors.brown),
  JourneyStep(date: "11.04.26", title: "Brainstormed the solutions", icon: Icons.lightbulb_rounded, color: Colors.yellow.shade700),
  JourneyStep(date: "11.04.26", title: "Mapped workflows to a digital solution", icon: Icons.schema_rounded, color: Colors.indigo),

  JourneyStep(date: "12.04.26", title: "Made a page to click image and store customer details", icon: Icons.camera_alt_rounded, color: Colors.pink),
  JourneyStep(date: "12.04.26", title: "Needed to manage money in database", icon: Icons.account_balance_wallet_rounded, color: Colors.green),
  JourneyStep(date: "12.04.26", title: "Learned SQLite", icon: Icons.storage_rounded, color: Colors.cyan),
  JourneyStep(date: "12.04.26", title: "Implemented database", icon: Icons.save_rounded, color: Colors.blueGrey),

  JourneyStep(date: "13.04.26", title: "Added measurement page", icon: Icons.straighten_rounded, color: Colors.purple),
  JourneyStep(date: "13.04.26", title: "Understood all problems & digitalized it", icon: Icons.transform_rounded, color: Colors.blueAccent),

  JourneyStep(date: "14.04.26", title: "Understood expenses list", icon: Icons.receipt_long_rounded, color: Colors.redAccent),
  JourneyStep(date: "14.04.26", title: "Digitalized it & made a page for it", icon: Icons.mobile_screen_share_rounded, color: Colors.deepOrangeAccent),

  JourneyStep(date: "15.04.26", title: "Made an order list items", icon: Icons.list_alt_rounded, color: Colors.teal),
  JourneyStep(date: "15.04.26", title: "Inquiries of all items & listed them", icon: Icons.format_list_bulleted_rounded, color: Colors.indigo),
  JourneyStep(date: "15.04.26", title: "Made pages for the lists", icon: Icons.pages_rounded, color: Colors.blue),

  JourneyStep(date: "16.04.26", title: "Made Payment identification / Payment page", icon: Icons.qr_code_scanner_rounded, color: Colors.green),

  JourneyStep(date: "17.04.26", title: "Needed to make online backup", icon: Icons.cloud_upload_rounded, color: Colors.cyan),
  JourneyStep(date: "17.04.26", title: "Made import and export page", icon: Icons.import_export_rounded, color: Colors.orange),
  JourneyStep(date: "17.04.26", title: "Searched for free & reliable cloud storage", icon: Icons.cloud_queue_rounded, color: Colors.blueGrey),
  JourneyStep(date: "17.04.26", title: "Chose GitHub and implemented it", icon: Icons.code_off_rounded, color: Colors.black87), // Used standard icon for code/git
  JourneyStep(date: "17.04.26", title: "Setup auto backup page", icon: Icons.sync_rounded, color: Colors.purple),

  JourneyStep(date: "18.04.26", title: "Made Admin page & gathered all in same page", icon: Icons.admin_panel_settings_rounded, color: Colors.deepOrange),
  JourneyStep(date: "18.04.26", title: "Configuration page to setup GitHub credentials", icon: Icons.settings_rounded, color: Colors.grey.shade700),

  JourneyStep(date: "19.04.26", title: "Worked on bugs and errors", icon: Icons.bug_report_rounded, color: Colors.red),
  JourneyStep(date: "19.04.26", title: "Tested, found errors, fixed with style", icon: Icons.brush_rounded, color: Colors.pinkAccent),
  JourneyStep(date: "19.04.26", title: "Now again in testing...", icon: Icons.science_rounded, color: Colors.amber.shade700),
  JourneyStep(date: "31.05.26", title: "Tested, found errors, fixed with style", icon: Icons.brush_rounded, color: Colors.pinkAccent),
  JourneyStep(date: "1.06.26", title: "Made an Billing page", icon: Icons.list_alt_rounded, color: Colors.teal),
  JourneyStep(date: "IN FUTURE", title: "Still developing...", icon: Icons.more_horiz_rounded, color: Colors.blue),
];
