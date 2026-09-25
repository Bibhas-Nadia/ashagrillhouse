
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:typed_data'; // 👈 ADD THIS LINE RIGHT HERE

class PaymentPage extends StatefulWidget {
  final GoogleSignInAccount? currentUser; // 👈 Accepts the logged-in user

  const PaymentPage({super.key, this.currentUser});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  // 🖼️ Asset Paths
  final String _qrImagePath = 'assets/images/qr_code.png';
  final String _logoImagePath = 'assets/images/logo.png';

  // 🔗 Gallery Website URL
  final String _galleryUrl = 'https://ashagrillhouse.github.io/site/gallery.html';

  // State Variables
  File? _customQrImage;
  bool _showBusinessCard = false;

  // 🔑 Key used to capture the business card as an image
  final GlobalKey _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSavedQrImage();
  }


  // =======================================================
  // 📤 SHARE QR IMAGE ONLY
  // =======================================================
  Future<void> _shareQrImage() async {
    if (_customQrImage != null) {
      try {
        await Share.shareXFiles(
          [XFile(_customQrImage!.path)],
          text: "Scan to pay Asha Grill House",
        );
      } catch (e) {
        debugPrint("Error sharing QR: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to share QR code"), backgroundColor: Colors.redAccent),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No QR code uploaded to share."), backgroundColor: Colors.orange),
      );
    }
  }




  // =======================================================
  // 💾 LOAD SAVED QR FROM LOCAL STORAGE
  // =======================================================
  Future<void> _loadSavedQrImage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String path = '${directory.path}/custom_qr.png';
      final File file = File(path);

      if (await file.exists()) {
        setState(() {
          _customQrImage = file;
        });
      }
    } catch (e) {
      debugPrint("Error loading QR image: $e");
    }
  }







//========================================================================
// =======================================================
// 📤 UPLOAD NEW QR IMAGE FROM GALLERY
// =======================================================
Future<void> _uploadQrImage() async {
  try {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final directory = await getApplicationDocumentsDirectory();
      final String newPath = '${directory.path}/custom_qr.png';

      // 1. Copy the new image over the old one
      final File newFile = await File(pickedFile.path).copy(newPath);

      // 🔥 2. CLEAR FLUTTER'S IMAGE CACHE
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 3. Temporarily set to null to force the UI to drop the old image
      setState(() {
        _customQrImage = null;
      });

      // 4. Wait a tiny fraction of a second, then load the new image
      await Future.delayed(const Duration(milliseconds: 50));

      setState(() {
        _customQrImage = newFile;
        _showBusinessCard = false; // Switch view to see the new QR
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("QR Code updated successfully!"), backgroundColor: Colors.green),
        );
      }
    }
  } catch (e) {
    debugPrint("Error picking image: $e");
  }
}
//========================================================================























  // =======================================================
  // 🔗 EXTERNAL LINK LAUNCHERS
  // =======================================================
  Future<void> _launchGalleryWebsite() async {
    final Uri url = Uri.parse(_galleryUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Could not launch gallery: $e");
    }
  }

  // =======================================================
  // 📤 SHARE BUSINESS CARD AS IMAGE
  // =======================================================
  Future<void> _shareBusinessCard() async {
    try {
      // 1. Capture the widget as a RenderRepaintBoundary
      RenderRepaintBoundary boundary = _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      // 2. Convert boundary to image
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); // 3.0 for high resolution

      // 3. Convert image to byte data (PNG format)
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        // 4. Save bytes to a temporary file
        final directory = await getTemporaryDirectory();
        final String filePath = '${directory.path}/ashagrillhouse_card.png';
        final File file = File(filePath);
        await file.writeAsBytes(byteData.buffer.asUint8List());

        // 5. Share the image file natively
        await Share.shareXFiles([XFile(filePath)], text: "Connect with Asha Grill House!");
      }
    } catch (e) {
      debugPrint("Error sharing card: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to share card"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // =======================================================
  // 📇 BUILD BUSINESS CARD VIEW
  // =======================================================
  Widget _buildBusinessCard() {
    return Stack(
      children: [
        // 📸 Wrap the card in a RepaintBoundary to take a screenshot of it
        RepaintBoundary(
          key: _cardKey,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade800, Colors.indigoAccent.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header: Profile & Name
                Row(
                  children: [
                    // 🖼️ Dynamic Google Account DP
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white24,
                        backgroundImage: widget.currentUser?.photoUrl != null
                        ? NetworkImage(widget.currentUser!.photoUrl!)
                        : null,
                        child: widget.currentUser?.photoUrl == null
                        ? const Icon(Icons.person, size:28, color: Colors.white)
                        : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Biggyan Das", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          Text("Asha Grill House", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    // Invisible spacer so the share button doesn't overlap text when captured
                    const SizedBox(width: 30),
                  ],
                ),
                const SizedBox(height: 5),
                const Divider(color: Colors.white30),
                const SizedBox(height: 5),

                // Contact Details
                const Row(
                  children: [
                    Icon(Icons.phone, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text("+91 9932134803", style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 5),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text("Post Office Daspara, Muragachha, Nadia, 741154", style: TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                  ],
                ),

                const SizedBox(height: 5),
                const Divider(color: Colors.white30),
                const SizedBox(height: 5),

                // Ad Message
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                    "এখানে শাটার, গ্রিল, উইন্ডো, কলপসিবল গেট, ষ্টীল এর যাবতীয় কাজ সুদক্ষ কারীগর দ্বারা করা হয় এবং অর্ডার অনুযায়ী সাপ্লাই করা হয়। ",
                    style: TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 5),

                // Footer: Small QR & URL
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        "https://ashagrillhouse.github.io/site",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: Image.asset(
                        _qrImagePath,
                        height: 50,
                        width: 50,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.qr_code, size: 40),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),

        // 📤 SHARE BUTTON (Positioned over the top right corner)
        Positioned(
          top: 20,
          right: 30,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.share_rounded, color: Colors.white),
              tooltip: "Share Business Card",
              onPressed: _shareBusinessCard,
            ),
          ),
        ),
      ],
    );
  }

  // =======================================================
  // 🔲 BUILD QR CODE VIEW
  // =======================================================
  // Widget _buildQrView() {
  //   return Column(
  //     children: [
  //       const Text(
  //         "Asha Grill House",
  //         style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
  //       ),
  //       const SizedBox(height: 8),
  //       const Text(
  //         "Pay directly at shop",
  //         style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w600),
  //       ),
  //       const SizedBox(height: 12),
  //
  //       // QR Code Container
  //       Container(
  //         padding: const EdgeInsets.all(15),
  //         decoration: BoxDecoration(
  //           color: Colors.white,
  //           borderRadius: BorderRadius.circular(32),
  //           boxShadow: [
  //             BoxShadow(color: Colors.indigo.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 10))
  //           ],
  //         ),
  //         child: ClipRRect(
  //           borderRadius: BorderRadius.circular(15),
  //           child: _customQrImage != null
  //           ? Image.file(
  //             _customQrImage!,
  //             key: UniqueKey(),
  //             height: 210,
  //             width: 210,
  //             fit: BoxFit.cover,
  //           )
  //           : Container(
  //             height: 210,
  //             width: 210,
  //             color: Colors.grey.shade100,
  //             child: const Column(
  //               mainAxisAlignment: MainAxisAlignment.center,
  //               children: [
  //                 Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.grey),
  //                 SizedBox(height: 10),
  //                 Text("No QR Uploaded", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
  //                 Text("Please upload a QR", style: TextStyle(color: Colors.grey, fontSize: 12)),
  //               ],
  //             ),
  //           ),
  //         ),
  //       ),
  //
  //       const SizedBox(height: 20),
  //       const Row(
  //         mainAxisAlignment: MainAxisAlignment.center,
  //         children: [
  //           Icon(Icons.verified_user_rounded, color: Colors.green, size: 22),
  //           SizedBox(width: 8),
  //           Text("Secure UPI Payment", style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
  //         ],
  //       ),
  //     ],
  //   );
  // }




  // =======================================================
  // 🔲 BUILD QR CODE VIEW
  // =======================================================
  Widget _buildQrView() {
    return Column(
      children: [
        const Text(
          "Asha Grill House",
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        const Text(
          "Pay directly at shop",
          style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),

        // 👇 REPLACE YOUR EXISTING QR CONTAINER WITH THIS STACK 👇
        Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(color: Colors.indigo.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 10))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: _customQrImage != null
                ? Image.file(
                  _customQrImage!,
                  key: UniqueKey(),
                  height: 210,
                  width: 210,
                  fit: BoxFit.cover,
                )
                : Container(
                  height: 210,
                  width: 210,
                  color: Colors.grey.shade100,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.grey),
                      SizedBox(height: 10),
                      Text("No QR Uploaded", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      Text("Please upload a QR", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

            // 📤 SHARE BUTTON (Positioned over the top right corner of the QR box)
            if (_customQrImage != null) // Only show the share button if an image exists
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50, // Subtle background so it's visible over the white box
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.share_rounded, color: Colors.indigoAccent),
                    tooltip: "Share QR Code",
                    onPressed: _shareQrImage,
                  ),
                ),
              ),
          ],
        ),
        // 👆 END OF REPLACEMENT 👆

        const SizedBox(height: 20),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_rounded, color: Colors.green, size: 22),
            SizedBox(width: 8),
            Text("Secure UPI Payment", style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }






  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // 🔹 TOP ROW: Left Logo & Right Gallery Button
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset(
                    _logoImagePath,
                    height: 45,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.restaurant, size: 40, color: Colors.indigoAccent),
                  ),
                  TextButton.icon(
                    onPressed: _launchGalleryWebsite,
                    icon: const Icon(Icons.photo_library_rounded, color: Colors.indigoAccent),
                    label: const Text("Gallery", style: TextStyle(color: Colors.indigoAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),

          // 🔹 CENTER CONTENT: Toggles between QR Code and Business Card
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _showBusinessCard ? _buildBusinessCard() : _buildQrView(),
              ),
            ),
          ),
        ],
      ),

      // 🔹 BOTTOM ACTION BUTTONS
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.indigoAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.indigo.shade100, width: 2)),
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 24),
                label: const Text("Upload QR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: _uploadQrImage,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: Colors.indigoAccent,
                  foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.indigoAccent.withOpacity(0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: Icon(_showBusinessCard ? Icons.qr_code : Icons.badge_rounded, size: 24),
                label: Text(_showBusinessCard ? "Show QR" : "Show Card", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () {
                  setState(() {
                    _showBusinessCard = !_showBusinessCard;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
