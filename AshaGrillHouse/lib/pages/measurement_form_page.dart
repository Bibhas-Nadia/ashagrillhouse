

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/measurement.dart';
import '../db_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class MeasurementFormPage extends StatefulWidget {
  final Measurement customer;

  const MeasurementFormPage({Key? key, required this.customer}) : super(key: key);

  @override
  _MeasurementFormPageState createState() => _MeasurementFormPageState();
}

class _MeasurementFormPageState extends State<MeasurementFormPage> {
  final _formKey = GlobalKey<FormState>();

  final List<TextEditingController> _heightControllers = [TextEditingController()];
  final List<TextEditingController> _lengthControllers = [TextEditingController()];
  final TextEditingController _noteController = TextEditingController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  // Camera & Image state
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    for (var c in _heightControllers) {
      c.dispose();
    }
    for (var c in _lengthControllers) {
      c.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  // 🎤 Toggle Speech to Text
  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (val) => setState(() => _isListening = false),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          localeId: "bn_IN",
          onResult: (val) {
            setState(() {
              _noteController.text = val.recognizedWords;
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }




/*
  // ==========================================================
  // 🗂️ DIRECTORY FINDER (SD CARD SUPPORT)
  // ==========================================================
  Future<String> _getDir() async {
    print("==================================================");
    print("🗂️ [MEASUREMENT] STARTING STORAGE SEARCH");
    print("==================================================");

    Directory? targetDir;

    try {
      print("🔍 Searching for external storage directories...");
      List<Directory>? extDirectories = await getExternalStorageDirectories(type: StorageDirectory.pictures);

      if (extDirectories != null && extDirectories.isNotEmpty) {
        // Prioritize physical SD card (Index 1)
        if (extDirectories.length > 1) {
          print("💾 SUCCESS: Physical SD Card detected! Selecting Volume 1.");
          targetDir = extDirectories[1];
        } else {
          print("📱 NOTICE: No physical SD Card found. Using Internal Shared Storage (Volume 0).");
          targetDir = extDirectories[0];
        }
      }
    } catch (e) {
      print("❌ ERROR: Failed to get external storage: $e");
    }

    // Fallback
    if (targetDir == null) {
      targetDir = await getApplicationDocumentsDirectory();
    }

    // Target folder is 'customers' so all your app's images stay together
    final String finalPath = "${targetDir.path}/measurements";
    final folder = Directory(finalPath);

    if (!await folder.exists()) {
      await folder.create(recursive: true);
      print("✅ Folder created successfully.");
    }

    return folder.path;
  }*/




// ==========================================================
// 🗂️ DIRECTORY FINDER (PUBLIC 'PICTURES' FOLDER PRIORITY)
// ==========================================================
Future<String> _getDir() async {
  print("==================================================");
  print("📁 [STORAGE SEARCH] TARGETING 'Pictures' FOLDER FOR MEASUREMENTS");
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
    // Adjusted path to store measurements instead of customers
    targetFolder = Directory("$sdCardRootPath/Pictures/.AshaGrillHouse/measurements");

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
  // Adjusted path to store measurements instead of customers
  targetFolder = Directory("$internalRootPath/Pictures/.AshaGrillHouse/measurements");

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







  // ==========================================================
  // 📸 TAKE PICTURE (COMPRESS & SAVE TO SD CARD)
  // ==========================================================
  Future<void> _takePicture() async {
    try {
      print("📸 Starting camera for measurement...");
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50,  // 🔥 Reduced for massive storage saving
        maxWidth: 1080,    // 🔥 Scales down 4K/8K images
        maxHeight: 1080,   // 🔥 Scales down 4K/8K images
      );

      if (pickedFile != null) {
        print("✅ Image captured! Temporary cache path: ${pickedFile.path}");

        // 1. Find the permanent folder (SD Card /customers)
        String permanentDirPath = await _getDir();

        // 2. Generate a unique filename for this measurement
        String uniqueFileName = "MEASURE_${widget.customer.id}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        String permanentFilePath = "$permanentDirPath/$uniqueFileName";

        // 3. Copy the file from temporary cache to the permanent SD folder
        File cachedImage = File(pickedFile.path);
        await cachedImage.copy(permanentFilePath);

        print("💾 Image successfully saved to permanent path:");
        print("   ▶ $permanentFilePath");

        // 4. Update the state with the PERMANENT file
        setState(() {
          _imageFile = File(permanentFilePath);
        });
      } else {
        print("⚠️ User canceled camera.");
      }
    } catch (e) {
      print("❌ ERROR in _takePicture: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to take picture: $e")),
      );
    }
  }










  // 🗑️ Remove the selected picture
  void _removePicture() {
    setState(() {
      _imageFile = null;
    });
  }

  // 💾 Save the Form (🔥 UPDATED VALIDATION LOGIC)
  // 💾 Save the Form (কমা দিয়ে সেপারেট করে সিঙ্গেল স্ট্রিং হিসেবে সেভ হবে)
  void _saveForm() async {
    // সব ভ্যালুগুলোকে ফিল্টার করে কমা দিয়ে একসাথে যুক্ত করা হচ্ছে
    String combinedHeight = _heightControllers
    .map((c) => c.text.trim())
    .where((text) => text.isNotEmpty)
    .join(', ');

    String combinedLength = _lengthControllers
    .map((c) => c.text.trim())
    .where((text) => text.isNotEmpty)
    .join(', ');

    // ১. চেক করা হচ্ছে যেকোনো একটি ফিল্ডে ডাটা আছে কিনা
    bool isAnyFieldFilled = combinedHeight.isNotEmpty ||
    combinedLength.isNotEmpty ||
    _noteController.text.trim().isNotEmpty ||
    _imageFile != null;

    if (!isAnyFieldFilled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill at least one field (Height, Length, Note, or Image)."),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    // ৪. ডাটাবেজে সিঙ্গেল স্ট্রিং আকারে পাঠানো হলো
    await DBHelper.insertDetailedMeasurement({
      'customerId': widget.customer.id,
      'height': combinedHeight, // যেমন: "12-3, 35.4-3, 12.6"
      'length': combinedLength, // যেমন: "10, 15-2"
      'note': _noteController.text.trim(),
      'images': _imageFile?.path ?? '',
      'createdAt': DateTime.now().toIso8601String(),
    });

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Measurement saved successfully!"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }









  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: AppBar(
        title: const Text("নতুন মাপ", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 👤 Top Section: Compact Customer Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.deepOrange.withOpacity(0.15),
                    child: const Icon(Icons.person, color: Colors.deepOrange, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.customer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${widget.customer.phone} • ${widget.customer.address}",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 📝 Form Fields
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Dimensions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),

                  // Height & Length Row
                  // Row(
                  //   children: [
                  //     Expanded(child: _buildTextField(_heightController, "Height", Icons.height)),
                  //     const SizedBox(width: 16),
                  //     Expanded(child: _buildTextField(_lengthController, "Length", Icons.straighten)),
                  //   ],
                  // ),

                  // 🟢 Height & Length Dynamic Columns Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Height Column List
                      Expanded(
                        child: Column(
                          children: [
                            ...List.generate(_heightControllers.length, (index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _buildDynamicTextField(_heightControllers[index], "Height ${index + 1}", Icons.height),
                                    ),
                                    if (_heightControllers.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                        onPressed: () {
                                          setState(() {
                                            _heightControllers[index].dispose();
                                            _heightControllers.removeAt(index);
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              );
                            }),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _heightControllers.add(TextEditingController());
                                });
                              },
                              icon: const Icon(Icons.add_circle_outline, color: Colors.deepOrange, size: 20),
                              label: const Text("Add Height", style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Length Column List
                      Expanded(
                        child: Column(
                          children: [
                            ...List.generate(_lengthControllers.length, (index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _buildDynamicTextField(_lengthControllers[index], "Length ${index + 1}", Icons.straighten),
                                    ),
                                    if (_lengthControllers.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                        onPressed: () {
                                          setState(() {
                                            _lengthControllers[index].dispose();
                                            _lengthControllers.removeAt(index);
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              );
                            }),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _lengthControllers.add(TextEditingController());
                                });
                              },
                              icon: const Icon(Icons.add_circle_outline, color: Colors.deepOrange, size: 20),
                              label: const Text("Add Length", style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),


                  const SizedBox(height: 20),

                  const Text("Additional Details", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),

                  // Note Field with Mic
                  TextFormField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Notes / Description",
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 40.0), // Align icon to top
                        child: Icon(Icons.note_alt_outlined),
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(bottom: 40.0), // Align icon to top
                        child: IconButton(
                          icon: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: _isListening ? Colors.red : Colors.grey.shade600
                          ),
                          onPressed: _toggleListening,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200, width: 1)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.deepOrange.shade300, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text("Attach Image", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),

                  // 📸 Image Picker Section
                  _buildImageSection(),

                  const SizedBox(height: 32),

                  // 💾 Save Button
                  ElevatedButton(
                    onPressed: _saveForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      elevation: 4,
                      shadowColor: Colors.deepOrange.withOpacity(0.4),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("SAVE MEASUREMENT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎨 Helper: Build Text Field (🔥 UPDATED: Removed 'validator' so it's not strictly required)
  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey.shade600),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.deepOrange.shade300, width: 2)),
      ),
      // No strict validator here anymore!
    );
  }

  // 🟢 আপডেট করা হেল্পার মেথড (বক্স এবং লেখার সাইজ বড় করা হয়েছে এবং শুধুমাত্র নাম্বার কিবোর্ড সেট করা হয়েছে)
  Widget _buildDynamicTextField(TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true), // 🔥 Restricts keyboard to numbers and decimals only
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2), // লেখা বড় ও স্পষ্ট করা হয়েছে
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 15, color: Colors.grey.shade700),
        prefixIcon: Icon(icon, color: Colors.grey.shade600, size: 24), // আইকন বড় করা হয়েছে
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16), // বক্সের ভেতরের জায়গা (উচ্চতা) বাড়ানো হয়েছে
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.deepOrange.shade400, width: 2)),
      ),
    );
  }




  // 🖼️ Helper: Build Image Picker UI
  Widget _buildImageSection() {
    if (_imageFile == null) {
      // 📷 State: No Image selected -> Show Camera Button
      return InkWell(
        onTap: _takePicture,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.deepOrange.withOpacity(0.5), width: 1.5, style: BorderStyle.solid),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt_outlined, size: 40, color: Colors.deepOrange.shade300),
              const SizedBox(height: 8),
              const Text("Tap to take a photo", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    } else {
      // 🖼️ State: Image Selected -> Show Image with Cross Button
      return Stack(
        children: [
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                _imageFile!,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          // ❌ Cross Button
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withOpacity(0.6),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: _removePicture,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      );
    }
  }
}
