import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DocumentationPage extends StatefulWidget {
  const DocumentationPage({super.key});

  @override
  State<DocumentationPage> createState() => _DocumentationPageState();
}

class _DocumentationPageState extends State<DocumentationPage> {
  late final WebViewController _controller;
  bool _isLoading = true; // Added to show a loading spinner while the page loads

  @override
  void initState() {
    super.initState();

    // Initialize the WebViewController
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // 🔥 Enables JavaScript
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false; // Hide loader when page finishes loading
            });
          },
        ),
      )
      ..loadRequest(Uri.parse('https://ashagrillhouse.github.io/site/app/documentation.html'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Documentation',
          style: TextStyle(fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.orange, // Assuming orange based on your previous UI snippets
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      // 🔥 The Stack allows us to show a loading indicator on top of the WebView
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller), // Takes up the whole screen under the AppBar

            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.deepOrange,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
