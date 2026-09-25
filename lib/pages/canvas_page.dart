


import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CanvasPage extends StatefulWidget {
  final String customerName;

  const CanvasPage({Key? key, required this.customerName}) : super(key: key);

  @override
  _CanvasPageState createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  // Lists to store strokes for drawing, undo, and redo
  List<List<Offset>> _strokes = [];
  List<List<Offset>> _undoneStrokes = [];
  List<Offset> _currentStroke = [];

  // Toggle between Drawing and Panning/Scrolling the canvas
  bool _isDrawingMode = true;

  // Set a large fixed size for the "infinite" canvas
  final double canvasWidth = 3000.0;
  final double canvasHeight = 2000.0;

  @override
  void initState() {
    super.initState();
    // 🔄 Force Landscape Mode & 📱 Full Screen Immersive Mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // 1. Reset orientation to Portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // 2. Bring back top (status) and bottom (nav) bars
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values
    );
    super.dispose();
  }

  // ✍️ Handle Drawing
  void _startStroke(DragStartDetails details) {
    if (!_isDrawingMode) return;
    setState(() {
      _currentStroke = [details.localPosition];
      _undoneStrokes.clear(); // Clear redo history
    });
  }

  void _updateStroke(DragUpdateDetails details) {
    if (!_isDrawingMode) return;
    setState(() {
      _currentStroke.add(details.localPosition);
    });
  }

  void _endStroke(DragEndDetails details) {
    if (!_isDrawingMode) return;
    setState(() {
      if (_currentStroke.isNotEmpty) {
        _strokes.add(List.from(_currentStroke));
        _currentStroke.clear();
      }
    });
  }

  // ↩️ Undo
  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _undoneStrokes.add(_strokes.removeLast());
      });
    }
  }

  // ↪️ Redo
  void _redo() {
    if (_undoneStrokes.isNotEmpty) {
      setState(() {
        _strokes.add(_undoneStrokes.removeLast());
      });
    }
  }


/*
  // ==========================================================
  // 🗂️ DIRECTORY FINDER (SD CARD SUPPORT)
  // ==========================================================
  Future<String> _getDir() async {
    print("==================================================");
    print("🗂️ [CANVAS] STARTING STORAGE SEARCH");
    print("==================================================");

    Directory? targetDir;

    try {
      List<Directory>? extDirectories = await getExternalStorageDirectories(type: StorageDirectory.pictures);

      if (extDirectories != null && extDirectories.isNotEmpty) {
        if (extDirectories.length > 1) {
          print("💾 SUCCESS: Physical SD Card detected! Selecting Volume 1.");
          targetDir = extDirectories[1];
        } else {
          print("📱 NOTICE: No physical SD Card found. Using Internal Shared.");
          targetDir = extDirectories[0];
        }
      }
    } catch (e) {
      print("❌ ERROR: Failed to get external storage: $e");
    }

    if (targetDir == null) {
      targetDir = await getApplicationDocumentsDirectory();
    }

    final String finalPath = "${targetDir.path}/measurements";
    final folder = Directory(finalPath);

    if (!await folder.exists()) {
      await folder.create(recursive: true);
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








  // ==============================================================
  // 💾 SAVE IMAGE WITH SMART AUTO-CROP
  // ==============================================================
  Future<void> _saveImage() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please draw something before saving!"), backgroundColor: Colors.redAccent)
      );
      return;
    }

    try {
      // 1. Find the exact boundaries of the drawing (Bounding Box)
      double minX = double.infinity;
      double minY = double.infinity;
      double maxX = -double.infinity;
      double maxY = -double.infinity;

      for (var stroke in _strokes) {
        for (var point in stroke) {
          if (point.dx < minX) minX = point.dx;
          if (point.dy < minY) minY = point.dy;
          if (point.dx > maxX) maxX = point.dx;
          if (point.dy > maxY) maxY = point.dy;
        }
      }

      // 2. Add padding so the drawing isn't touching the absolute edge
      const double padding = 40.0;
      minX = (minX - padding).clamp(0.0, canvasWidth);
      minY = (minY - padding).clamp(0.0, canvasHeight);
      maxX = (maxX + padding).clamp(0.0, canvasWidth);
      maxY = (maxY + padding).clamp(0.0, canvasHeight);

      double cropWidth = maxX - minX;
      double cropHeight = maxY - minY;

      if (cropWidth <= 0 || cropHeight <= 0) return;

      // 3. Create a pristine Off-Screen Canvas specifically sized for the drawing
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // High-resolution multiplier
      const double pixelRatio = 2.0;
      canvas.scale(pixelRatio);

      // Fill background with white
      canvas.drawRect(Rect.fromLTWH(0, 0, cropWidth, cropHeight), Paint()..color = Colors.white);

      // Shift the canvas coordinate system so the drawing starts exactly at 0,0
      canvas.translate(-minX, -minY);

      // 4. Re-draw all the strokes mathematically onto this new canvas
      Paint paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

      for (var stroke in _strokes) {
        if (stroke.isEmpty) continue;
        Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (int i = 1; i < stroke.length; i++) {
          path.lineTo(stroke[i].dx, stroke[i].dy);
        }
        canvas.drawPath(path, paint);
      }

      // 5. Render directly to a cropped high-quality image
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(
        (cropWidth * pixelRatio).toInt(),
        (cropHeight * pixelRatio).toInt()
      );

      // 6. Save File to Phone
      // ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      // Uint8List pngBytes = byteData!.buffer.asUint8List();
      //
      // final directory = await getApplicationDocumentsDirectory();
      // String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      // File imgFile = File('${directory.path}/${widget.customerName.replaceAll(" ", "_")}_$timestamp.png');
      // await imgFile.writeAsBytes(pngBytes);
      //
      // if (mounted) {
      //   Navigator.pop(context, imgFile.path); // Return the newly cropped image path
      // }

      // 6. Save File to Phone (ON SD CARD)
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // 🔥 Fetch the SD Card directory
      String permanentDirPath = await _getDir();
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      // Clean the customer name to avoid folder error crashes
      String cleanName = widget.customerName.replaceAll(" ", "_").replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

      // Save directly to the SD Card
      File imgFile = File('$permanentDirPath/CANVAS_${cleanName}_$timestamp.png');
      await imgFile.writeAsBytes(pngBytes);

      print("💾 Canvas Image successfully saved to permanent path:");
      print("   ▶ ${imgFile.path}");

      if (mounted) {
        Navigator.pop(context, imgFile.path); // Return the newly cropped image path
      }




    } catch (e) {
      print("Error saving cropped image: $e");
    }
  }

  Future<bool> _onWillPop() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Exit without saving?"),
        content: const Text("Any unsaved drawings will be lost."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("EXIT", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
    return confirm;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade300,
        body: Stack(
          children: [
            // 1. 🎨 THE SCROLLABLE CANVAS
            InteractiveViewer(
              panEnabled: !_isDrawingMode,
              scaleEnabled: !_isDrawingMode,
              constrained: false,
              minScale: 0.1,
              maxScale: 3.0,
              boundaryMargin: const EdgeInsets.all(500),
              child: Center(
                child: GestureDetector(
                  onPanStart: _isDrawingMode ? _startStroke : null,
                  onPanUpdate: _isDrawingMode ? _updateStroke : null,
                  onPanEnd: _isDrawingMode ? _endStroke : null,
                  child: Container(
                    width: canvasWidth,
                    height: canvasHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)
                      ]
                    ),
                    child: CustomPaint(
                      painter: SketchPainter(strokes: _strokes, currentStroke: _currentStroke),
                      size: Size(canvasWidth, canvasHeight),
                    ),
                  ),
                ),
              ),
            ),

            // 2. 🧰 FLOATING TOOLBAR
            Positioned(
              left: 16,
              top: 24,
              bottom: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToolButton(Icons.arrow_back_rounded, Colors.black87, () async {
                          if (await _onWillPop()) Navigator.pop(context);
                        }),
                        const SizedBox(height: 16),
                        Container(height: 1, width: 24, color: Colors.grey.shade300),
                        const SizedBox(height: 16),

                        // Toggle Draw / Move
                        _buildToolButton(
                          _isDrawingMode ? Icons.edit : Icons.pan_tool,
                          _isDrawingMode ? Colors.deepOrange : Colors.blue,
                          () => setState(() => _isDrawingMode = !_isDrawingMode)
                        ),
                        Text(_isDrawingMode ? "Draw" : "Move", style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),

                        const SizedBox(height: 16),
                        _buildToolButton(Icons.undo_rounded, _strokes.isNotEmpty ? Colors.black87 : Colors.grey, _undo),
                        const SizedBox(height: 12),
                        _buildToolButton(Icons.redo_rounded, _undoneStrokes.isNotEmpty ? Colors.black87 : Colors.grey, _redo),
                        const SizedBox(height: 16),
                        Container(height: 1, width: 24, color: Colors.grey.shade300),
                        const SizedBox(height: 16),

                        _buildToolButton(Icons.save_rounded, Colors.green, _saveImage),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}

class SketchPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;

  SketchPainter({required this.strokes, required this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
    ..color = Colors.black
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

    for (var stroke in strokes) {
      if (stroke.isEmpty) continue;
      Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.isNotEmpty) {
      Path path = Path()..moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (int i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) => true;
}
