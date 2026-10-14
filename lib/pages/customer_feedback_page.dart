import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../backup_service.dart';
import '../db_helper.dart';

// =====================================================================
// customer_feedback_page.dart  -  ONE file: data fetch + the screen.
// Open it with:
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerFeedbackPage()));
// =====================================================================

// ---------------------------------------------------------------- data + web script
/// One customer's feedback (one row of the "feedback" sheet in Google Sheets).
class FeedbackEntry {
  final String customerId;
  final String name;
  final String phone;
  final int rating; // 1..5
  final String date; // e.g. "11-10-2026 09:47:12 PM" (Indian time, already formatted by the script)

  const FeedbackEntry({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.rating,
    required this.date,
  });

  factory FeedbackEntry.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final int r = toInt(json['rating']);
    return FeedbackEntry(
      customerId: (json['customerId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      rating: r < 0 ? 0 : (r > 5 ? 5 : r),
      date: (json['date'] ?? '').toString(),
    );
  }
}

/// Everything the feedback page needs.
class FeedbackData {
  final int count;
  final double average; // e.g. 4.3
  final Map<int, int> distribution; // star (1..5) -> how many customers gave it
  final List<FeedbackEntry> items; // NEWEST first

  const FeedbackData({
    required this.count,
    required this.average,
    required this.distribution,
    required this.items,
  });
}

class FeedbackService {
  static const Duration _timeout = Duration(seconds: 60);

  // Same method as BackupService: auto-redirects are turned off and the 302/303 that
  // Google Apps Script answers with is followed by hand (otherwise the payload is lost).
  static Future<http.Response> _postToGoogle(String scriptUrl, Map<String, dynamic> body) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(scriptUrl))
        ..headers["Content-Type"] = "application/json"
        ..body = jsonEncode(body)
        ..followRedirects = false;

      final streamedResponse = await client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 302 || response.statusCode == 303) {
        final String? redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          return await http.get(Uri.parse(redirectUrl)).timeout(_timeout);
        }
      }
      return response;
    } finally {
      client.close();
    }
  }

  /// Downloads the complete feedback list. Throws an Exception with a readable message on any problem.
  static Future<FeedbackData> fetchAll() async {
    final config = await DBHelper.getConfig();
    final String scriptUrl = config?['googleScriptUrl']?.toString().trim() ?? "";

    if (scriptUrl.isEmpty || !scriptUrl.startsWith("https://script.google.com/macros/s/")) {
      throw Exception("Google Script URL is not set. Please set it in Configuration.");
    }

    http.Response response;
    try {
      response = await _postToGoogle(scriptUrl, {
        "apiKey": BackupService.SECRET_API_KEY,
        "action": "fetch_feedbacks",
      });
    } on SocketException {
      throw Exception("No internet connection.");
    } on TimeoutException {
      throw Exception("The server took too long to answer. Please try again.");
    } on http.ClientException {
      throw Exception("Network problem. Please check your internet and try again.");
    }

    if (response.statusCode != 200) {
      throw Exception("Server error (${response.statusCode}).");
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map) {
      throw Exception("Unexpected answer from the server. Make sure the latest Google Script version is deployed.");
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(decoded);

    if (json['status'] != 'success') {
      final String msg = (json['message'] ?? 'Request failed').toString();
      if (msg.toLowerCase().contains('unknown action')) {
        throw Exception("The Google Script is not updated yet. Deploy the new version (Deploy > Manage deployments > New version).");
      }
      throw Exception(msg);
    }

    // star -> count
    final Map<int, int> distribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    final dynamic rawDist = json['distribution'];
    if (rawDist is Map) {
      for (int s = 1; s <= 5; s++) {
        final dynamic v = rawDist['$s'];
        distribution[s] = v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);
      }
    }

    final List<FeedbackEntry> items = [];
    final dynamic rawList = json['feedbacks'];
    if (rawList is List) {
      for (final dynamic e in rawList) {
        if (e is Map) {
          items.add(FeedbackEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    final dynamic avgRaw = json['average'];
    final double average = avgRaw is num ? avgRaw.toDouble() : (double.tryParse(avgRaw?.toString() ?? '') ?? 0.0);
    final dynamic countRaw = json['count'];
    final int count = countRaw is num ? countRaw.toInt() : items.length;

    return FeedbackData(
      count: count,
      average: average,
      distribution: distribution,
      items: items,
    );
  }
}

// ---------------------------------------------------------------- screen

class CustomerFeedbackPage extends StatefulWidget {
  const CustomerFeedbackPage({Key? key}) : super(key: key);

  @override
  State<CustomerFeedbackPage> createState() => _CustomerFeedbackPageState();
}

class _CustomerFeedbackPageState extends State<CustomerFeedbackPage> {
  FeedbackData? _data;
  bool _loading = true;
  String? _error;

  int _ratingFilter = 0; // 0 = all ratings
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await FeedbackService.fetchAll();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<FeedbackEntry> get _filtered {
    final FeedbackData? data = _data;
    if (data == null) return <FeedbackEntry>[];
    final String q = _query.trim().toLowerCase();
    return data.items.where((f) {
      if (_ratingFilter != 0 && f.rating != _ratingFilter) return false;
      if (q.isEmpty) return true;
      return f.name.toLowerCase().contains(q) ||
          f.phone.toLowerCase().contains(q) ||
          f.customerId.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          "Customer Feedback",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final FeedbackData? data = _data;

    // First load: nothing to show yet
    if (data == null && _loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.deepOrange));
    }
    // First load failed
    if (data == null) {
      return _buildErrorState();
    }

    final List<FeedbackEntry> items = _filtered;
    final String? err = _error;

    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 3, color: Colors.deepOrange),
        if (err != null)
          Container(
            width: double.infinity,
            color: Colors.red.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              err,
              style: TextStyle(color: Colors.red.shade800, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: Colors.deepOrange,
            onRefresh: _load,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: 1 + (items.isEmpty ? 1 : items.length),
              itemBuilder: (context, index) {
                if (index == 0) return _buildHeader(data, items.length);
                if (items.isEmpty) return _buildEmptyMessage(data);
                return _buildItem(items[index - 1]);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- header (summary + search + filters)
  Widget _buildHeader(FeedbackData d, int shown) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCard(d),
        const SizedBox(height: 14),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search name / phone',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.deepOrange, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildChip('All', 0),
              for (int s = 5; s >= 1; s--) _buildChip('$s ★', s),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          d.items.isEmpty ? '' : 'Showing $shown of ${d.items.length}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSummaryCard(FeedbackData d) {
    final int totalRated = d.distribution.values.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                d.average.toStringAsFixed(1),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
              _starRow(d.average.round(), size: 16),
              const SizedBox(height: 6),
              Text(
                '${d.count} feedback',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (int s = 5; s >= 1; s--) _buildBarRow(s, d.distribution[s] ?? 0, totalRated),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // One tappable bar: tap = show only that rating, tap again = show all
  Widget _buildBarRow(int star, int count, int total) {
    final bool selected = _ratingFilter == star;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _ratingFilter = selected ? 0 : star),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Text(
                '$star',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  color: selected ? Colors.deepOrange : const Color(0xFF475569),
                ),
              ),
            ),
            Icon(Icons.star_rounded, size: 13, color: Colors.amber.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0.0 : count / total,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(selected ? Colors.deepOrange : Colors.amber.shade600),
                ),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '$count',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, int value) {
    final bool selected = _ratingFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: Colors.deepOrange.shade100,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? Colors.deepOrange.shade900 : const Color(0xFF334155),
        ),
        onSelected: (_) => setState(() => _ratingFilter = value),
      ),
    );
  }

  // ---------------------------------------------------------------- one feedback card
  Widget _buildItem(FeedbackEntry f) {
    final MaterialColor tone = f.rating >= 4 ? Colors.green : (f.rating == 3 ? Colors.amber : Colors.red);
    final String name = f.name.trim();
    final String initial = name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: tone.shade100,
            child: Text(
              initial,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: tone.shade800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unknown customer' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                _starRow(f.rating, size: 18),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.phone_rounded, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        f.phone,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _tidyDate(f.date),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (f.phone.trim().isNotEmpty)
            IconButton(
              tooltip: 'Call customer',
              icon: Icon(Icons.call_rounded, color: Colors.green.shade600),
              onPressed: () => _callCustomer(f.phone),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyMessage(FeedbackData d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.rate_review_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            d.items.isEmpty ? 'No feedback received yet.' : 'No feedback matches your search.',
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Could not load feedback.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- small helpers
  Widget _starRow(int filled, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(5, (i) {
        final bool on = i < filled;
        return Icon(
          on ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: on ? Colors.amber.shade600 : Colors.grey.shade400,
        );
      }),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    );
  }

  // "11-10-2026 09:47:12 PM" -> "11-10-2026 09:47 PM"
  String _tidyDate(String d) {
    return d.replaceFirstMapped(
      RegExp(r'(\d{1,2}:\d{2}):\d{2}(\s*[AaPp][Mm])'),
      (m) => '${m[1]}${m[2]}',
    );
  }

  Future<void> _callCustomer(String phone) async {
    final String number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the phone dialer.')),
      );
    }
  }
}
