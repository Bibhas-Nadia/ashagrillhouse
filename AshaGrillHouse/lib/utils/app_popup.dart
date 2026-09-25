import 'package:flutter/material.dart';

class AppPopup {
  static void show(
    BuildContext context, {
    required String message,
    IconData icon = Icons.check_circle,
    Color color = Colors.green,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 30),
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 10),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 50),
                  SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // ⏳ Auto close after 2 sec
    Future.delayed(Duration(seconds: 2), () {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }
}
