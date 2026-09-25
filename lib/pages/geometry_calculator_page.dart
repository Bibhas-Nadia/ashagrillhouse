import 'dart:math';
import 'package:flutter/material.dart';

class GeometryCalculatorPage extends StatelessWidget {
  const GeometryCalculatorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Geometry & Measurements', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigoAccent,
        foregroundColor: Colors.white,
          elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        physics: const BouncingScrollPhysics(),
        children: const [
          RightTriangleCard(),
          SizedBox(height: 16),
          RectangleCard(),
          SizedBox(height: 16),
          SquareCard(),
          SizedBox(height: 16),
          CircleCard(),
          SizedBox(height: 16),
          OvalCard(),
          SizedBox(height: 16),
          CylinderCard(),
          SizedBox(height: 16),
          ConeCard(),
        ],
      ),
    );
  }
}

// ==========================================
// 📐 1. RIGHT-ANGLED TRIANGLE
// ==========================================
class RightTriangleCard extends StatefulWidget {
  const RightTriangleCard({super.key});
  @override
  State<RightTriangleCard> createState() => _RightTriangleCardState();
}

class _RightTriangleCardState extends State<RightTriangleCard> {
  final TextEditingController _baseCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  String _hypotenuse = "0.00";

  void _calculate() {
    double base = double.tryParse(_baseCtrl.text) ?? 0;
    double height = double.tryParse(_heightCtrl.text) ?? 0;
    setState(() {
      _hypotenuse = (base > 0 && height > 0) ? sqrt((base * base) + (height * height)).toStringAsFixed(2) : "0.00";
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildCalcCard(
      title: "Right-Angled Triangle",
      painter: TrianglePainter(),
      inputs: [
        _buildTextField("Base (a)", _baseCtrl, _calculate),
        _buildTextField("Height (b)", _heightCtrl, _calculate),
      ],
      results: [
        _buildResultRow("Hypotenuse (c):", _hypotenuse),
      ],
    );
  }
}

// ==========================================
// ▭ 2. RECTANGLE
// ==========================================
class RectangleCard extends StatefulWidget {
  const RectangleCard({super.key});
  @override
  State<RectangleCard> createState() => _RectangleCardState();
}

class _RectangleCardState extends State<RectangleCard> {
  final TextEditingController _lengthCtrl = TextEditingController();
  final TextEditingController _widthCtrl = TextEditingController();
  String _diagonal = "0.00";

  void _calculate() {
    double length = double.tryParse(_lengthCtrl.text) ?? 0;
    double width = double.tryParse(_widthCtrl.text) ?? 0;
    setState(() {
      _diagonal = (length > 0 && width > 0) ? sqrt((length * length) + (width * width)).toStringAsFixed(2) : "0.00";
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildCalcCard(
      title: "Rectangle",
      painter: RectanglePainter(),
      inputs: [
        _buildTextField("Length", _lengthCtrl, _calculate),
        _buildTextField("Width", _widthCtrl, _calculate),
      ],
      results: [
        _buildResultRow("Diagonal Length:", _diagonal),
      ],
    );
  }
}

// ==========================================
// □ 3. SQUARE
// ==========================================
class SquareCard extends StatefulWidget {
  const SquareCard({super.key});
  @override
  State<SquareCard> createState() => _SquareCardState();
}

class _SquareCardState extends State<SquareCard> {
  final TextEditingController _sideCtrl = TextEditingController();
  String _diagonal = "0.00";

  void _calculate() {
    double side = double.tryParse(_sideCtrl.text) ?? 0;
    setState(() {
      _diagonal = (side > 0) ? (side * sqrt(2)).toStringAsFixed(2) : "0.00";
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildCalcCard(
      title: "Square",
      painter: SquarePainter(),
      inputs: [
        _buildTextField("Side Length", _sideCtrl, _calculate),
      ],
      results: [
        _buildResultRow("Diagonal Length:", _diagonal),
      ],
    );
  }
}

// ==========================================
// ◯ 4. CIRCLE
// ==========================================
class CircleCard extends StatefulWidget {
  const CircleCard({super.key});
  @override
  State<CircleCard> createState() => _CircleCardState();
}

class _CircleCardState extends State<CircleCard> {
  final TextEditingController _diaCtrl = TextEditingController();
  final TextEditingController _circCtrl = TextEditingController();

  void _calcFromDiameter(String val) {
    double d = double.tryParse(val) ?? 0;
    if (d > 0) {
      _circCtrl.text = (pi * d).toStringAsFixed(2);
    } else {
      _circCtrl.clear();
    }
  }

  void _calcFromCircumference(String val) {
    double c = double.tryParse(val) ?? 0;
    if (c > 0) {
      _diaCtrl.text = (c / pi).toStringAsFixed(2);
    } else {
      _diaCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildCalcCard(
      title: "Circle",
      painter: CirclePainter(),
      inputs: [
        _buildTextField("Diameter (d)", _diaCtrl, () {}, onChanged: _calcFromDiameter),
        _buildTextField("Circumference (C)", _circCtrl, () {}, onChanged: _calcFromCircumference),
      ],
      results: [
        const Text("Type in either field to calculate the other.", style: TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

// ==========================================
// ⬭ 5. OVAL / ELLIPSE
// ==========================================
class OvalCard extends StatefulWidget {
  const OvalCard({super.key});
  @override
  State<OvalCard> createState() => _OvalCardState();
}

class _OvalCardState extends State<OvalCard> {
  final TextEditingController _majorCtrl = TextEditingController();
  final TextEditingController _minorCtrl = TextEditingController();
  String _circumference = "0.00";

  void _calculate() {
    double a = (double.tryParse(_majorCtrl.text) ?? 0) / 2; // Semi-major
    double b = (double.tryParse(_minorCtrl.text) ?? 0) / 2; // Semi-minor
    setState(() {
      if (a > 0 && b > 0) {
        // Ramanujan's Approximation for Ellipse Circumference
        _circumference = (pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))).toStringAsFixed(2);
      } else {
        _circumference = "0.00";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildCalcCard(
      title: "Oval (Ellipse)",
      painter: OvalPainter(),
      inputs: [
        _buildTextField("Full Width", _majorCtrl, _calculate),
        _buildTextField("Full Height", _minorCtrl, _calculate),
      ],
      results: [
        _buildResultRow("Approx. Circumference:", _circumference),
      ],
    );
  }
}

// ==========================================
// 🛢️ 6. CYLINDER
// ==========================================
class CylinderCard extends StatefulWidget {
  const CylinderCard({super.key});
  @override
  State<CylinderCard> createState() => _CylinderCardState();
}

class _CylinderCardState extends State<CylinderCard> {
  final TextEditingController _radiusCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  String _surfaceArea = "0.00";
  String _volume = "0.00";

  void _calculate() {
    double r = double.tryParse(_radiusCtrl.text) ?? 0;
    double h = double.tryParse(_heightCtrl.text) ?? 0;
    setState(() {
      if (r > 0 && h > 0) {
        _surfaceArea = (2 * pi * r * (r + h)).toStringAsFixed(2);
        _volume = (pi * r * r * h).toStringAsFixed(2);
      } else {
        _surfaceArea = "0.00";
        _volume = "0.00";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildCalcCard(
      title: "Right Cylinder",
      painter: CylinderPainter(),
      inputs: [
        _buildTextField("Radius (r)", _radiusCtrl, _calculate),
        _buildTextField("Height (h)", _heightCtrl, _calculate),
      ],
      results: [
        _buildResultRow("Total Surface Area:", _surfaceArea),
        _buildResultRow("Volume:", _volume),
      ],
    );
  }
}

// ==========================================
// 🍦 7. CONE
// ==========================================
class ConeCard extends StatefulWidget {
  const ConeCard({super.key});
  @override
  State<ConeCard> createState() => _ConeCardState();
}

class _ConeCardState extends State<ConeCard> {
  final TextEditingController _radiusCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  String _slantHeight = "0.00";
  String _surfaceArea = "0.00";
  String _volume = "0.00";

  void _calculate() {
    double r = double.tryParse(_radiusCtrl.text) ?? 0;
    double h = double.tryParse(_heightCtrl.text) ?? 0;
    setState(() {
      if (r > 0 && h > 0) {
        double l = sqrt((r * r) + (h * h));
        _slantHeight = l.toStringAsFixed(2);
        _surfaceArea = (pi * r * (r + l)).toStringAsFixed(2);
        _volume = ((1 / 3) * pi * r * r * h).toStringAsFixed(2);
      } else {
        _slantHeight = "0.00";
        _surfaceArea = "0.00";
        _volume = "0.00";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildCalcCard(
      title: "Cone",
      painter: ConePainter(),
      inputs: [
        _buildTextField("Radius (r)", _radiusCtrl, _calculate),
        _buildTextField("Height (h)", _heightCtrl, _calculate),
      ],
      results: [
        _buildResultRow("Slant Height (l):", _slantHeight),
        _buildResultRow("Total Surface Area:", _surfaceArea),
        _buildResultRow("Volume:", _volume),
      ],
    );
  }
}

// ==========================================
// 🛠️ REUSABLE UI BUILDERS
// ==========================================
Widget _buildCalcCard({
  required String title,
  required CustomPainter painter,
  required List<Widget> inputs,
  required List<Widget> results,
}) {
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🎨 VISUAL DIAGRAM
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12)),
              child: CustomPaint(painter: painter),
            ),
            const SizedBox(width: 20),
            // 🔢 INPUT FIELDS
            Expanded(
              child: Column(
                children: inputs,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        // 📊 RESULTS
        ...results,
      ],
    ),
  );
}

Widget _buildTextField(String label, TextEditingController controller, VoidCallback onEditComplete, {Function(String)? onChanged}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10.0),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged ?? (val) => onEditComplete(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

Widget _buildResultRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

// ==========================================
// 🎨 CUSTOM PAINTERS FOR VISUALS
// ==========================================

class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.indigoAccent..strokeWidth = 3..style = PaintingStyle.stroke;
    final path = Path()
    ..moveTo(20, 80)
    ..lineTo(80, 80) // Base
    ..lineTo(20, 20) // Height
    ..close();       // Hypotenuse
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RectanglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.indigoAccent..strokeWidth = 3..style = PaintingStyle.stroke;
    final dashed = Paint()..color = Colors.redAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawRect(const Rect.fromLTWH(10, 30, 80, 40), paint);
    _drawDashedLine(canvas, const Offset(10, 30), const Offset(90, 70), dashed); // Diagonal
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SquarePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.indigoAccent..strokeWidth = 3..style = PaintingStyle.stroke;
    final dashed = Paint()..color = Colors.redAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawRect(const Rect.fromLTWH(20, 20, 60, 60), paint);
    _drawDashedLine(canvas, const Offset(20, 20), const Offset(80, 80), dashed); // Diagonal
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.indigoAccent..strokeWidth = 3..style = PaintingStyle.stroke;
    final dashed = Paint()..color = Colors.redAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawCircle(const Offset(50, 50), 35, paint);
    _drawDashedLine(canvas, const Offset(15, 50), const Offset(85, 50), dashed); // Diameter
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.indigoAccent..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawOval(const Rect.fromLTWH(10, 30, 80, 40), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CylinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.indigoAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    // Top oval
    canvas.drawOval(const Rect.fromLTWH(25, 10, 50, 15), paint);
    // Bottom oval
    canvas.drawOval(const Rect.fromLTWH(25, 75, 50, 15), paint);
    // Sides
    canvas.drawLine(const Offset(25, 17.5), const Offset(25, 82.5), paint);
    canvas.drawLine(const Offset(75, 17.5), const Offset(75, 82.5), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.indigoAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    // Base oval
    canvas.drawOval(const Rect.fromLTWH(20, 75, 60, 15), paint);
    // Triangle sides
    canvas.drawLine(const Offset(50, 15), const Offset(20, 82.5), paint);
    canvas.drawLine(const Offset(50, 15), const Offset(80, 82.5), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Helper for drawing diagonal dashed lines
void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
  const int dashWidth = 5;
  const int dashSpace = 5;
  double distance = (p2 - p1).distance;
  double dx = (p2.dx - p1.dx) / distance;
  double dy = (p2.dy - p1.dy) / distance;

  double startX = p1.dx;
  double startY = p1.dy;

  while (distance >= 0) {
    canvas.drawLine(Offset(startX, startY), Offset(startX + dx * dashWidth, startY + dy * dashWidth), paint);
    startX += dx * (dashWidth + dashSpace);
    startY += dy * (dashWidth + dashSpace);
    distance -= (dashWidth + dashSpace);
  }
}
