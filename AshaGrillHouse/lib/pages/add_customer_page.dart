



import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:call_log/call_log.dart';

import '../db_helper.dart';
import '../models/customer.dart';
import '../utils/app_popup.dart';
import '../utils/sms_helper.dart';
import 'customer_detail_page.dart';

class AddCustomerPage extends StatefulWidget {
  @override
  _AddCustomerPageState createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final due = TextEditingController();
  bool sendSms = true;

  List<File> images = [];
  final picker = ImagePicker();

  late stt.SpeechToText speech;
  TextEditingController? activeMicController; // 🟢 এটি যোগ করুন

  @override
  void initState() {
    super.initState();
    // Removed: due.text = "0"; (Now defaults to empty, backend handles the 0)
    speech = stt.SpeechToText();
  }

  // 🎤 START VOICE
  void startListening(TextEditingController controller) async {
    bool available = await speech.initialize();

    if (available) {
      setState(() => activeMicController = controller); // 🟢 কারেন্ট কন্ট্রোলার সেট করা হলো

      speech.listen(
        localeId: "bn_IN", // Bengali
        onResult: (result) {
          setState(() {
            controller.text = result.recognizedWords;
          });
        },
      );
    }
  }

  void stopListening() {
    speech.stop();
    setState(() => activeMicController = null); // 🟢 মাইক অফ হলে ক্লিয়ার করা হলো
  }

  // 📷
  // pickImages() async {
  //   final picked = await picker.pickMultiImage();
  //   if (picked.isNotEmpty) {
  //     setState(() {
  //       images.addAll(picked.map((e) => File(e.path)));
  //     });
  //   }
  // }
  //
  // pickCamera() async {
  //   final picked = await picker.pickImage(source: ImageSource.camera);
  //   if (picked != null) {
  //     setState(() => images.add(File(picked.path)));
  //   }
  // }


  // 📷 Pick Multiple Images from Gallery (COMPRESSED)
  pickImages() async {
    final picked = await picker.pickMultiImage(
      imageQuality: 50, // 🔥 Reduces quality to 50% (saves massive storage)
    maxWidth: 1080,   // 🔥 Shrinks 4K images down to max 1080px width
    maxHeight: 1080,  // 🔥 Shrinks 4K images down to max 1080px height
    );
    if (picked.isNotEmpty) {
      setState(() {
        images.addAll(picked.map((e) => File(e.path)));
      });
    }
  }

  // 📷 Pick Single Image from Camera (COMPRESSED)
  pickCamera() async {
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50, // 🔥 Reduces quality to 50%
      maxWidth: 1080,   // 🔥 Limits width to 1080px
      maxHeight: 1080,  // 🔥 Limits height to 1080px
    );
    if (picked != null) {
      setState(() => images.add(File(picked.path)));
    }
  }






  // Future<String> getDir() async {
  //   final dir = await getApplicationDocumentsDirectory();
  //   final folder = Directory("${dir.path}/customers");
  //   if (!await folder.exists()) {
  //     await folder.create(recursive: true);
  //   }
  //   return folder.path;
  // }

/*
  Future<String> getDir() async {
    // Get all external storage directories
    List<Directory>? extDirectories = await getExternalStorageDirectories(type: StorageDirectory.pictures);

    Directory targetDir;

    if (extDirectories != null && extDirectories.isNotEmpty) {
      // If length > 1, it means a physical SD Card is inserted!
      if (extDirectories.length > 1) {
        targetDir = extDirectories[1]; // 🔥 Picks the physical SD Card
        print("Saving to SD Card: ${targetDir.path}");
      } else {
        targetDir = extDirectories[0]; // Fallback to Internal Shared Storage
        print("No SD Card found, saving to Internal Shared: ${targetDir.path}");
      }
    } else {
      // Ultimate fallback if Android denies external storage
      targetDir = await getApplicationDocumentsDirectory();
    }

    final folder = Directory("${targetDir.path}/customers");

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    return folder.path;
  }
*/

// 📞 FETCH RECENT CALLS
Future<void> _showRecentCalls() async {
  // Request permission first
  PermissionStatus status = await Permission.phone.request();

  if (status.isGranted) {
    Iterable<CallLogEntry> entries = await CallLog.get();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Recent Calls",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length > 20 ? 20 : entries.length, // Show top 20
                  itemBuilder: (context, index) {
                    CallLogEntry entry = entries.elementAt(index);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.deepOrange.shade100,
                        child: const Icon(Icons.phone, color: Colors.deepOrange),
                      ),
                      title: Text(entry.name ?? "Unknown"),
                      subtitle: Text(entry.number ?? ""),
                      onTap: () {
                        if (entry.number != null) {
                          // Clean the number (remove spaces, symbols, and +91)
                          String cleanNumber = entry.number!.replaceAll(RegExp(r'\D'), '');
                          if (cleanNumber.length > 10) {
                            // Extract just the last 10 digits
                            cleanNumber = cleanNumber.substring(cleanNumber.length - 10);
                          }

                          setState(() {
                            phone.text = cleanNumber;
                          });
                        }
                        Navigator.pop(context); // Close the bottom sheet
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  } else {
    AppPopup.show(
      context,
      message: "Call log permission denied",
      icon: Icons.error_outline,
      color: Colors.redAccent,
    );
  }
}


// ==========================================================
// 🗂️ DIRECTORY FINDER (PUBLIC 'PICTURES' FOLDER PRIORITY)
// ==========================================================
Future<String> getDir() async {
  print("==================================================");
  print("📁 [STORAGE SEARCH] TARGETING 'Pictures' FOLDER");
  print("==================================================");

  // 1. Ensure permissions are requested
  if (await Permission.manageExternalStorage.isDenied) {
    print("⚠️ Requesting Manage External Storage Permission...");
    await Permission.manageExternalStorage.request();
  }
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }

  String? sdCardRootPath;
  String internalRootPath = '/storage/emulated/0';

  try {
    print("🔍 Scanning device volumes...");
    final List<Directory>? extDirs = await getExternalStorageDirectories();

    if (extDirs != null && extDirs.length > 1) {
      String appSpecificSdPath = extDirs[1].path;
      int androidIndex = appSpecificSdPath.indexOf('/Android/');
      if (androidIndex != -1) {
        sdCardRootPath = appSpecificSdPath.substring(0, androidIndex);
        print("💾 SD Card TRUE ROOT found: $sdCardRootPath");
      }
    } else {
      print("📱 No SD Card detected.");
    }
  } catch (e) {
    print("❌ Error finding SD card directories: $e");
  }

  Directory targetFolder;

  // --------------------------------------------------------
  // ATTEMPT 1: Force SD Card "Pictures" Folder
  // --------------------------------------------------------
  if (sdCardRootPath != null) {
    targetFolder = Directory("$sdCardRootPath/Pictures/.AshaGrillHouse/customers");

    try {
      if (!await targetFolder.exists()) {
        print("🔨 Attempting to create folder in SD Card 'Pictures'...");
        await targetFolder.create(recursive: true);
      }
      print("✅ SUCCESS: Using SD Card: ${targetFolder.path}");
      print("==================================================");
      return targetFolder.path; // Stop here and return SD path

    } catch (e) {
      print("⚠️ OS Blocked SD Card 'Pictures' access: $e");
      print("🔄 FALLING BACK to Internal Storage...");
    }
  }

  // --------------------------------------------------------
  // ATTEMPT 2: Fallback to Internal Storage "Pictures" Folder
  // --------------------------------------------------------
  targetFolder = Directory("$internalRootPath/Pictures/.AshaGrillHouse/customers");

  try {
    if (!await targetFolder.exists()) {
      print("🔨 Creating folder in Internal Storage 'Pictures'...");
      await targetFolder.create(recursive: true);
    }
    print("✅ SUCCESS: Using Internal Storage: ${targetFolder.path}");
  } catch (e) {
    print("❌ CRITICAL ERROR creating folder in Internal Storage: $e");
  }

  print("==================================================");
  return targetFolder.path;
}





  Future<String> saveImages(int id) async {
    final path = await getDir();
    List<String> list = [];

    for (int i = 0; i < images.length; i++) {
      String newPath = "$path/cust_${id}_$i.jpg";
      await images[i].copy(newPath);
      list.add(newPath);
    }

    return list.join(",");
  }

  save() async {
    if (name.text.trim().isEmpty) {
      AppPopup.show(
        context,
        message: "Name is required",
        icon: Icons.error_outline,
        color: Colors.redAccent,
      );
      return;
    }

    if (phone.text.isNotEmpty && phone.text.length != 10) {
      AppPopup.show(
        context,
        message: "Invalid phone number",
        icon: Icons.phone_disabled_rounded,
        color: Colors.redAccent,
      );
      return;
    }

    String fullPhone = phone.text.isEmpty ? "" : "+91${phone.text.trim()}";

    // 🔍 CHECK DUPLICATE
    bool exists = await DBHelper.customerExists(
      name.text.trim(),
      fullPhone,
      address.text.trim(),
    );

    if (exists) {
      AppPopup.show(
        context,
        message: "Customer already exists!",
        icon: Icons.warning_amber_rounded,
        color: Colors.orange,
      );
      return;
    }

    int id = DateTime.now().millisecondsSinceEpoch;
    String imgPaths = await saveImages(id);

    String now =
    "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year} "
    "${DateTime.now().hour}:${DateTime.now().minute}";

        /*// 🔥 If due is empty, insert "0" into the database
        String finalDue = due.text.trim().isEmpty ? "0" : due.text.trim();

        await DBHelper.insert(Customer(
          name: name.text.trim(),
          phone: fullPhone,
          address: address.text.trim(),
          due: finalDue,
          images: imgPaths,
          createdAt: now,
        ));

        AppPopup.show(
          context,
          message: "Customer Saved Successfully",
          icon: Icons.check_circle_rounded,
          color: Colors.green,
        );

        // ✅ SMS PART
        String customerName = name.text.trim();
        String customerPhone = phone.text.trim();
        double dueAmount = double.tryParse(finalDue) ?? 0;

        if (sendSms && customerPhone.isNotEmpty && dueAmount > 0) {
          String msg = SmsHelper.buildDueMessage(
            name: customerName,
            amount: dueAmount.toStringAsFixed(0),
          );

          await SmsHelper.sendSMS(
            phone: customerPhone,
            message: msg,
          );
          print("SMS sent Successfully");
        }

        // CLEAR FORM
        name.clear();
        phone.clear();
        address.clear();
        due.clear(); // Clear instead of setting to "0"

        setState(() => images.clear());*/

///////////////////////////////

        String customerName = name.text.trim();
        String customerPhone = fullPhone;
        String finalDue = due.text.trim().isEmpty ? "0" : due.text.trim();


//         int generatedId = await DBHelper.insert(Customer(
//           name: name.text.trim(),
//           phone: fullPhone,
//           address: address.text.trim(),
//           due: finalDue,
//           images: imgPaths,
//           createdAt: now,
//         ));
//

        Customer newCustomer = Customer(
          name: customerName,
          phone: customerPhone,
          address: address.text.trim(),
          due: finalDue,
          images: imgPaths,
          createdAt: now,
        );

        int generatedId = await DBHelper.insert(newCustomer);
        newCustomer.id = generatedId;


        double dueAmount = double.tryParse(finalDue) ?? 0;

        if (sendSms && customerPhone.isNotEmpty && dueAmount > 0) {
          // String msg = SmsHelper.buildDueMessage(
          //   name: customerName,
          //   amount: dueAmount.toStringAsFixed(0),
          // );
          String? status = await DBHelper.getStatus();

          String msg;

          // 2. Check if status is "active"
          if (status == "active") {
            // Message for Active Status
            msg = "Dear $customerName\nYour bill is generated. "
            "Your current due is Rs. ${dueAmount}. "
            "If any queries, contact us.\n\n- Asha Grill House\n"
            "View details: https://ashagrillhouse.github.io/site/receipt.html?q=${customerPhone.replaceAll(RegExp(r'\D'), '').substring(customerPhone.replaceAll(RegExp(r'\D'), '').length - 10)}";

          }
          else {
            // 3. Message for Inactive or any other status
            msg = "Dear $customerName\nYour bill is generated. "
            "Your current due is Rs. ${dueAmount}. "
            "If any queries, contact us.\n\n- Asha Grill House";
          }



          await SmsHelper.sendSMS(
            phone: customerPhone,
            message: msg,
          );

          await DBHelper.insertMessage(generatedId,msg,now);

          print("SMS sent Successfully");
        }

        // SHOW SUCCESS POPUP
        AppPopup.show(
          context,
          message: "Customer Saved Successfully",
          icon: Icons.check_circle_rounded,
          color: Colors.green,
        );

        // CLEAR FORM
        name.clear();
        phone.clear();
        address.clear();
        due.clear();
        setState(() => images.clear());



        if (!mounted) return;
        print("=========================READY TO REDIRECT============================");
        // 👇 NEW: Wait slightly so the user can read the success popup
        await Future.delayed(const Duration(milliseconds: 2000));
        print("=========================TRY TO REDIRECT============================");
        // 👇 NEW: Redirect directly to the Customer Details Page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CustomerDetailPage(c: newCustomer),
          ),
        );
  } // <-- End of save() method
/////////////////////////////














  //}



  // Update your input widget signature to include this:
  Widget input({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool mic = false,
    Widget? customSuffix, // 🔥 NEW PARAMETER
    TextInputType type = TextInputType.text,
    int? maxLength, // <-- Change to nullable
    String? prefix,
    String? hint,
    void Function(String)? onChanged, // <-- ADD THIS
  }){
    return Padding(
      padding: const EdgeInsets.only(bottom: 9), // Slightly increased spacing
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLength: maxLength,
        onChanged: onChanged, // <-- ADD THIS
        // 🔥 FIX: Increased typed text size to 16
        style: const TextStyle(fontSize: 16, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          // 🔥 FIX: Increased hint text size to 16
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          // 🔥 FIX: Increased label text size from 13 to 15
          labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.w500),
          prefixText: prefix,
          // 🔥 FIX: Increased prefix size (like "+91") to 16
          prefixStyle: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.bold),
          prefixIcon: Icon(icon, color: Colors.deepOrange.shade300, size: 22), // Scaled icon slightly


          // 🔥 UPDATED SUFFIX LOGIC
          // suffixIcon: customSuffix ?? (mic
          // ? IconButton(
          //   icon: Icon(
          //     isListening ? Icons.mic : Icons.mic_none,
          //     color: isListening ? Colors.redAccent : Colors.grey.shade400,
          //     size: 26,
          //   ),
          //   onPressed: () {
          //     isListening ? stopListening() : startListening(controller);
          //   },
          // )
          // : null),

          // 🔥 UPDATED SUFFIX LOGIC
          suffixIcon: customSuffix ?? (mic
          ? IconButton(
            icon: Icon(
              activeMicController == controller ? Icons.mic : Icons.mic_none,
              color: activeMicController == controller ? Colors.redAccent : Colors.grey.shade400,
              size: 26,
            ),
            onPressed: () {
              if (activeMicController == controller) {
                stopListening(); // একই মাইক আবার চাপলে বন্ধ হবে
              } else {
                if (activeMicController != null) speech.stop(); // অন্য মাইক চললে তা বন্ধ করে নতুনটি ধরবে
                startListening(controller);
              }
            },
          )
          : null),



          counterText: "", // Hide the counter
          filled: true,
          fillColor: Colors.white,
          // 🔥 FIX: Increased vertical padding to make field taller for bigger text
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.deepOrange, width: 2),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("নতুন খদ্দেরের হিসাব ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20)), // Bumped app bar text
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20), // Responsive padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // 📝 Form Section
            input(
              label: "Customer Name *",
              icon: Icons.person_rounded,
              controller: name,
              mic: true,
            ),

            // input(
            //   label: "Phone Numberr",
            //   icon: Icons.phone_rounded,
            //   controller: phone,
            //   type: TextInputType.number,
            //   maxLength: 10,
            //   prefix: "+91  ",
            //   // 🔥 ADD THIS LINE:
            //   customSuffix: IconButton(
            //     icon: const Icon(Icons.history_rounded, color: Colors.deepOrange),
            //     onPressed: _showRecentCalls,
            //     tooltip: "Fetch from call log",
            //   ),
            // ),

            input(
              label: "Phone Number",
              icon: Icons.phone_rounded,
              controller: phone,
              type: TextInputType.number,
              maxLength: 100, // Use a high number so pasted text isn't cut off before cleaning
              prefix: "+91  ",
              customSuffix: IconButton(
                icon: const Icon(Icons.history_rounded, color: Colors.deepOrange),
                onPressed: _showRecentCalls,
                tooltip: "Fetch from call log",
              ),
              onChanged: (val) {
                // 1. Remove everything except numbers (strips spaces, dashes, + signs)
                String cleanDigits = val.replaceAll(RegExp(r'\D'), '');

                // 2. If user pasted a number with +91 or 0 at the start, remove it
                if (cleanDigits.length > 10) {
                  if (cleanDigits.startsWith('91')) {
                    cleanDigits = cleanDigits.substring(2);
                  } else if (cleanDigits.startsWith('0')) {
                    cleanDigits = cleanDigits.substring(1);
                  }
                }

                // 3. Force exact 10 digits
                if (cleanDigits.length > 10) {
                  cleanDigits = cleanDigits.substring(cleanDigits.length - 10);
                }

                // 4. Update the text field and keep cursor at the end
                if (val != cleanDigits) {
                  phone.text = cleanDigits;
                  phone.selection = TextSelection.fromPosition(
                    TextPosition(offset: phone.text.length),
                  );
                }
              },
            ),






            input(
              label: "Address",
              icon: Icons.location_on_rounded,
              controller: address,
              mic: true,
            ),
            input(
              label: "Due Amount",
              icon: Icons.currency_rupee_rounded,
              controller: due,
              hint: "1000", // Watermark hint
              type: const TextInputType.numberWithOptions(decimal: true),
            ),

            const SizedBox(height: 8),

            // 📸 Image Attachment Section
            const Text(
              "Attachments",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)), // Bumped size
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: pickImages,
                    icon: const Icon(Icons.photo_library_rounded, size: 22),
                    label: const FittedBox(child: Text("Gallery", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))), // Bumped size
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withOpacity(0.1),
                      foregroundColor: Colors.blueAccent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16), // Made button taller
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: pickCamera,
                    icon: const Icon(Icons.camera_alt_rounded, size: 22),
                    label: const FittedBox(child: Text("Camera", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))), // Bumped size
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.withOpacity(0.1),
                      foregroundColor: Colors.teal,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16), // Made button taller
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Display Images Grid
            if (images.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: images.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (_, i) {
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            images[i],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => images.removeAt(i)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(5),
                            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 20),

              // 📱 SMS Toggle Card
              GestureDetector(
                onTap: () => setState(() => sendSms = !sendSms),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // Increased vertical padding
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200, width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10), // Bigger icon padding
                        decoration: BoxDecoration(color: sendSms ? Colors.deepOrange.withOpacity(0.1) : Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.sms_rounded, color: sendSms ? Colors.deepOrange : Colors.grey, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Send SMS Notification",
                          style: TextStyle(color: Colors.grey.shade800, fontSize: 16, fontWeight: FontWeight.w600), // Bumped text size
                        ),
                      ),
                      Switch(
                        value: sendSms,
                        activeColor: Colors.deepOrange,
                        onChanged: (val) => setState(() => sendSms = val),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28), // Added a bit more space before the save button

              // 💾 Huge Save Button
              ElevatedButton(
                onPressed: save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: Colors.deepOrange.withOpacity(0.5),
                    minimumSize: const Size(double.infinity, 56), // Made slightly taller for better tap area
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                ),
                child: const Text(
                  "SAVE CUSTOMER",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2), // Bumped font size
                ),
              ),

              const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
