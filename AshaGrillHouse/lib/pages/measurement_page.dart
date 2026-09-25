/*
import 'dart:io';
import 'package:flutter/material.dart';
import '../db_helper.dart';
import '../models/measurement.dart';
import '../models/customer.dart'; // Added to support looking up existing customer records
import 'measurement_detail_page.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';

class MeasurementPage extends StatefulWidget {
  @override
  _MeasurementPageState createState() => _MeasurementPageState();
}

class _MeasurementPageState extends State<MeasurementPage> {
  List<Measurement> allMeasurements = [];
  List<Measurement> filteredMeasurements = [];
  bool isLoading = true;

  final TextEditingController _searchController = TextEditingController();

  late stt.SpeechToText speech;

  // Tracks exactly which text field is currently using the microphone
  TextEditingController? _listeningController;

  @override
  void initState() {
    super.initState();
    speech = stt.SpeechToText();
    _loadMeasurements();
  }

  // 📥 Fetch from Database
  Future<void> _loadMeasurements() async {
    setState(() => isLoading = true);
    List<Measurement> data = await DBHelper.getMeasurements();
    setState(() {
      allMeasurements = data;
      filteredMeasurements = data;
      isLoading = false;
    });
  }

  // 🔍 Filter List
  void _filterMeasurements(String query) {
    if (query.isEmpty) {
      setState(() => filteredMeasurements = allMeasurements);
    } else {
      setState(() {
        filteredMeasurements = allMeasurements.where((m) {
          return m.name.toLowerCase().contains(query.toLowerCase()) ||
          m.phone.contains(query);
        }).toList();
      });
    }
  }

  // 🎤 UNIFIED VOICE LOGIC
  void _toggleMic(TextEditingController targetController, {StateSetter? modalState}) async {
    // If the user taps the mic that is already listening, stop it.
    if (_listeningController == targetController) {
      await speech.stop();
      _updateMicState(null, modalState);
      return;
    }

    // Initialize speech recognition
    bool available = await speech.initialize(
      onStatus: (status) {
        // When speech stops naturally, reset the mic icon
        if (status == 'done' || status == 'notListening') {
          _updateMicState(null, modalState);
        }
      },
      onError: (error) => _updateMicState(null, modalState),
    );

    if (available) {
      _updateMicState(targetController, modalState); // Turn mic RED

      speech.listen(
        localeId: "bn_IN", // Change to en_IN for English if preferred
        onResult: (result) {
          targetController.text = result.recognizedWords;
          // Keep cursor at the end of the text
          targetController.selection = TextSelection.collapsed(offset: targetController.text.length);

          // If searching, filter the list immediately
          if (targetController == _searchController) {
            _filterMeasurements(result.recognizedWords);
          }

          // Force UI to refresh to show text as it is spoken
          _updateMicState(targetController, modalState);
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Microphone permission denied."))
      );
    }
  }

  // 📞 FETCH RECENT CALLS (For Bottom Sheet)
  Future<void> _showRecentCalls(BuildContext sheetContext, TextEditingController phoneController) async {
    PermissionStatus status = await Permission.phone.request();

    if (status.isGranted) {
      Iterable<CallLogEntry> entries = await CallLog.get();

      if (!sheetContext.mounted) return;

      showModalBottomSheet(
        context: sheetContext,
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
                    itemCount: entries.length > 20 ? 20 : entries.length, // Top 20 calls
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
                            // Strip all spaces, dashes, and country codes
                            String cleanNumber = entry.number!.replaceAll(RegExp(r'\D'), '');
                            if (cleanNumber.length > 10) {
                              cleanNumber = cleanNumber.substring(cleanNumber.length - 10);
                            }

                            // Instantly update the text field with prefix and no spaces
                            phoneController.text = "+91$cleanNumber";
                          }
                          Navigator.pop(context); // Close the call log list
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Call log permission denied", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        )
      );
    }
  }

  // Safely updates UI in both Main Page and Bottom Sheet
  void _updateMicState(TextEditingController? controller, StateSetter? modalState) {
    _listeningController = controller;
    if (modalState != null) modalState(() {});
    setState(() {});
  }

  // 🗑️ Delete from Database
  Future<void> _deleteMeasurement(Measurement m) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Record?"),
        content: Text("Are you sure you want to delete ${m.name}'s measurement?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("DELETE", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await DBHelper.deletePriceAgreement(m.id!);
      await DBHelper.deleteMeasurement(m.id!);
      _loadMeasurements();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Measurement record deleted.")));
      }
    }
  }

  // ➕ Add New Bottom Sheet
  void _showAddNewBottomSheet() {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController _nameController = TextEditingController();
    //final TextEditingController _phoneController = TextEditingController();
    final TextEditingController _addressController = TextEditingController();
    final TextEditingController _phoneController = TextEditingController(text: "+91");

    // To hold customer tables records for autocomplete lookup feature
    List<Customer>? _allDbCustomers;
    List<Customer> _matchedCustomers = [];
    bool _isExistingCustomer = false; // Tracks if selected profile is imported from DB

    // Ensure mic is off before opening sheet
    speech.stop();
    _updateMicState(null, null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext statefulContext, StateSetter setModalState) {

            // Asynchronously fetch all master customers if not already loaded
            if (_allDbCustomers == null) {
              DBHelper.getCustomers().then((list) {
                setModalState(() {
                  _allDbCustomers = list;
                });
              });
            }

            // Local helper function to look up existing items matching typed state inputs
            void _updateSuggestions() {
              // Hide suggestion box if we have already locked an existing customer profile
              if (_isExistingCustomer) {
                _matchedCustomers = [];
                return;
              }

              final nameQuery = _nameController.text.trim().toLowerCase();
              final phoneQuery = _phoneController.text.trim();

              if (nameQuery.isEmpty && phoneQuery.isEmpty) {
                _matchedCustomers = [];
              } else {
                _matchedCustomers = (_allDbCustomers ?? []).where((c) {
                  final matchesName = nameQuery.isNotEmpty && c.name.toLowerCase().contains(nameQuery);
                  final matchesPhone = phoneQuery.isNotEmpty && c.phone.contains(phoneQuery);
                  return matchesName || matchesPhone;
                }).toList();
              }
            }

            // Fire lookup analysis every build cycle to perfectly coordinate text changes
            _updateSuggestions();

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stylish drag handle indicator
                        Center(
                          child: Container(
                            width: 50,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text("নতুন খদ্দেরের মাপ", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 24),

                        // CUSTOMER NAME FIELD
                        TextFormField(
                          controller: _nameController,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText: "Customer Name *",
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                            prefixIcon: const Icon(Icons.person_outline, color: Colors.deepOrange),

                            // 🔥 SHOW CLEAR/UNLOCK OPTION IF EXISTING PROFILE WAS LOADED
                            suffixIcon: _isExistingCustomer
                            ? IconButton(
                              icon: const Icon(Icons.lock_open_rounded, color: Colors.blue, size: 24),
                              tooltip: "Unlock profile fields",
                              onPressed: () {
                                setModalState(() {
                                  _nameController.clear();
                                  _phoneController.clear();
                                  _addressController.clear();
                                  _isExistingCustomer = false; // Revert everything back
                                });
                              },
                            )
                            : IconButton(
                              icon: Icon(
                                _listeningController == _nameController ? Icons.mic : Icons.mic_none,
                                color: _listeningController == _nameController ? Colors.red : Colors.deepOrange,
                                size: 26,
                              ),
                              onPressed: () => _toggleMic(_nameController, modalState: setModalState),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              // 🔥 IF USER MODIFIES/DELETES SEARCH TEXT, AUTOMATICALLY UNLOCK AND REVERT BACK!
                              if (_isExistingCustomer) {
                                _isExistingCustomer = false;
                              }
                            });
                          },
                          validator: (value) => (value == null || value.trim().isEmpty) ? "Required" : null,
                        ),

                        const SizedBox(height: 16),

                        // 📞 PHONE NUMBER FIELD (LOCKED IF EXISTING)
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          readOnly: _isExistingCustomer,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _isExistingCustomer ? Colors.grey.shade600 : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText: _isExistingCustomer ? "Phone Number (Linked Profile)" : "Phone Number",
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                            prefixIcon: Icon(
                              _isExistingCustomer ? Icons.lock_outline : Icons.phone_outlined,
                              color: _isExistingCustomer ? Colors.grey : Colors.blue,
                            ),
                            suffixIcon: _isExistingCustomer
                            ? null
                            : IconButton(
                              icon: const Icon(Icons.history_rounded, color: Colors.deepOrange),
                              tooltip: "Fetch from call log",
                              onPressed: () => _showRecentCalls(statefulContext, _phoneController),
                            ),
                            filled: true,
                            fillColor: _isExistingCustomer ? Colors.grey.shade200 : Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onChanged: (val) {
                            if (!val.startsWith("+91")) {
                              // If user deleted the prefix or pasted text without +91
                              String cleanDigits = val.replaceAll(RegExp(r'\D'), '');
                              if (cleanDigits.startsWith('91') && cleanDigits.length > 10) {
                                cleanDigits = cleanDigits.substring(2);
                              }
                              if (cleanDigits.length > 10) {
                                cleanDigits = cleanDigits.substring(cleanDigits.length - 10);
                              }
                              _phoneController.text = "+91$cleanDigits";
                            } else {
                              // If it has +91, clean up spaces/dashes pasted into the remainder text
                              String remainder = val.substring(3);
                              String cleanDigits = remainder.replaceAll(RegExp(r'\D'), '');
                              if (cleanDigits.length > 10) {
                                cleanDigits = cleanDigits.substring(0, 10);
                              }
                              String formattedText = "+91$cleanDigits";
                              if (val != formattedText) {
                                _phoneController.text = formattedText;
                              }
                            }

                            // Keep cursor position at the very end of the string
                            _phoneController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _phoneController.text.length)
                            );

                            // Revert lock flag if text changes
                            setModalState(() {
                              if (_isExistingCustomer) {
                                _isExistingCustomer = false;
                              }
                            });
                          },
                        ),






                        // 🌟 DETECTED EXISTING CUSTOMERS SCROLLABLE COMPONENT
                        if (_matchedCustomers.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Row(
                            children: [
                              Icon(Icons.people_outline_rounded, size: 16, color: Colors.blueGrey),
                              SizedBox(width: 6),
                              Text(
                                "Existing Profiles Found (Tap to Autofill):",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200, width: 1.5),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _matchedCustomers.length,
                              separatorBuilder: (context, index) => Divider(color: Colors.grey.shade200, height: 1),
                              itemBuilder: (context, idx) {
                                final customer = _matchedCustomers[idx];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue.shade50,
                                    radius: 15,
                                    child: const Icon(Icons.person, size: 15, color: Colors.blue),
                                  ),
                                  title: Text(
                                    customer.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)
                                  ),
                                  subtitle: Text(
                                    "${customer.phone}${customer.address.isNotEmpty ? ' • ${customer.address}' : ''}",
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    setModalState(() {
                                      _nameController.text = customer.name;
                                      _phoneController.text = customer.phone;
                                      _addressController.text = customer.address;
                                      _isExistingCustomer = true; // 🔥 Set lock flag to active
                                      _matchedCustomers = [];
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // 📍 ADDRESS FIELD (LOCKED IF EXISTING)
                        TextFormField(
                          controller: _addressController,
                          readOnly: _isExistingCustomer, // 🔥 Blocks entry if existing customer profile selected
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _isExistingCustomer ? Colors.grey.shade600 : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText: _isExistingCustomer ? "Address (Linked Profile)" : "Address",
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                            prefixIcon: Icon(
                              _isExistingCustomer ? Icons.lock_outline : Icons.location_on_outlined,
                              color: _isExistingCustomer ? Colors.grey : Colors.green,
                            ),
                            suffixIcon: _isExistingCustomer
                            ? null
                            : IconButton(
                              icon: Icon(
                                _listeningController == _addressController ? Icons.mic : Icons.mic_none,
                                color: _listeningController == _addressController ? Colors.red : Colors.green,
                                size: 26,
                              ),
                              onPressed: () => _toggleMic(_addressController, modalState: setModalState),
                            ),
                            filled: true,
                            fillColor: _isExistingCustomer ? Colors.grey.shade200 : Colors.grey.shade50, // Darker bg when locked
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ➡️ NEXT/SAVE BUTTON
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (_formKey.currentState!.validate()) {
                                Measurement newRecord = Measurement(
                                  name: _nameController.text.trim(),
                                  phone: _phoneController.text.trim(),
                                  address: _addressController.text.trim(),
                                  createdAt: DateTime.now().toIso8601String(),
                                );

                                await DBHelper.insertMeasurement(newRecord);

                                List<Measurement> updatedList = await DBHelper.getMeasurements();
                                Measurement createdRecord = updatedList.lastWhere(
                                  (m) => m.name == newRecord.name && m.phone == newRecord.phone,
                                  orElse: () => newRecord,
                                );

                                speech.stop();
                                _updateMicState(null, null);
                                _loadMeasurements();

                                if (!mounted) return;

                                Navigator.pop(statefulContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Measurement record added!"),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(milliseconds: 1000),
                                  ),
                                );

                                await Future.delayed(const Duration(milliseconds: 400));

                                if (!mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MeasurementDetailPage(measurement: createdRecord),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 2,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("SAVE", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                SizedBox(width: 8),
                                Icon(Icons.check_circle_outline, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      speech.stop();
      _updateMicState(null, null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: AppBar(
        title: const Text("খদ্দেরের মাপ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: _showAddNewBottomSheet,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Colors.deepOrange),
              label: const Text(
                "Add",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 15)
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 2,
                shadowColor: Colors.black.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: Column(
        children: [
          // 🔍 MAIN LOOKUP SEARCH BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _filterMeasurements,
              style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: "Search customer name or phone...",
                hintStyle: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, color: Colors.deepOrange, size: 24),

                // 🔥 CLEAR ICON BACK REVERT OR MIC ICON CONDITION
                suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.deepOrange, size: 24),
                  tooltip: "Clear search",
                  onPressed: () {
                    _searchController.clear();
                    _filterMeasurements('');
                    if (_listeningController == _searchController) {
                      speech.stop();
                      _updateMicState(null, null);
                    }
                    setState(() {});
                  },
                )
                : IconButton(
                  icon: Icon(
                    _listeningController == _searchController ? Icons.mic : Icons.mic_none,
                    color: _listeningController == _searchController ? Colors.red : Colors.grey,
                    size: 24,
                  ),
                  onPressed: () => _toggleMic(_searchController),
                ),
                filled: true,
                fillColor: const Color(0xfff1f3f8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              ),
            ),
          ),

          // 📄 LIST SECTION
          Expanded(
            child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
            : filteredMeasurements.isEmpty
            ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.straighten, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("No records found.", style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ],
              )
            )
            : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredMeasurements.length,
              itemBuilder: (context, index) {
                final Measurement m = filteredMeasurements[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                    image: const DecorationImage(
                      image: AssetImage('assets/images/card_bg1.png'),
                      fit: BoxFit.cover,
                      opacity: 0.25,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MeasurementDetailPage(measurement: m),
                          ),
                        ).then((_) => _loadMeasurements());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.straighten_rounded, color: Colors.deepOrange, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  const SizedBox(height: 6),
                                  if (m.phone.isNotEmpty)
                                    Row(
                                      children: [
                                        const Icon(Icons.phone_rounded, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(m.phone, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    if (m.address.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_rounded, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              m.address,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ],
                                      ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                              tooltip: "Delete",
                              onPressed: () => _deleteMeasurement(m),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}*/






import 'dart:io';
import 'package:flutter/material.dart';
import '../db_helper.dart';
import '../models/measurement.dart';
import '../models/customer.dart'; // Added to support looking up existing customer records
import 'measurement_detail_page.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';

class MeasurementPage extends StatefulWidget {
  @override
  _MeasurementPageState createState() => _MeasurementPageState();
}

class _MeasurementPageState extends State<MeasurementPage> {
  List<Measurement> allMeasurements = [];
  List<Measurement> filteredMeasurements = [];
  bool isLoading = true;

  final TextEditingController _searchController = TextEditingController();

  late stt.SpeechToText speech;

  // Tracks exactly which text field is currently using the microphone
  TextEditingController? _listeningController;

  @override
  void initState() {
    super.initState();
    speech = stt.SpeechToText();
    _loadMeasurements();
  }

  // 📥 Fetch from Database
  Future<void> _loadMeasurements() async {
    setState(() => isLoading = true);
    List<Measurement> data = await DBHelper.getMeasurements();
    setState(() {
      allMeasurements = data;
      filteredMeasurements = data;
      isLoading = false;
    });
  }

  // 🔍 Filter List
  void _filterMeasurements(String query) {
    if (query.isEmpty) {
      setState(() => filteredMeasurements = allMeasurements);
    } else {
      setState(() {
        filteredMeasurements = allMeasurements.where((m) {
          return m.name.toLowerCase().contains(query.toLowerCase()) ||
          m.phone.contains(query);
        }).toList();
      });
    }
  }

  // 🎤 UNIFIED VOICE LOGIC
  void _toggleMic(TextEditingController targetController, {StateSetter? modalState}) async {
    // If the user taps the mic that is already listening, stop it.
    if (_listeningController == targetController) {
      await speech.stop();
      _updateMicState(null, modalState);
      return;
    }

    // Initialize speech recognition
    bool available = await speech.initialize(
      onStatus: (status) {
        // When speech stops naturally, reset the mic icon
        if (status == 'done' || status == 'notListening') {
          _updateMicState(null, modalState);
        }
      },
      onError: (error) => _updateMicState(null, modalState),
    );

    if (available) {
      _updateMicState(targetController, modalState); // Turn mic RED

      speech.listen(
        localeId: "bn_IN", // Change to en_IN for English if preferred
        onResult: (result) {
          targetController.text = result.recognizedWords;
          // Keep cursor at the end of the text
          targetController.selection = TextSelection.collapsed(offset: targetController.text.length);

          // If searching, filter the list immediately
          if (targetController == _searchController) {
            _filterMeasurements(result.recognizedWords);
          }

          // Force UI to refresh to show text as it is spoken
          _updateMicState(targetController, modalState);
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Microphone permission denied."))
      );
    }
  }

  // 📞 FETCH RECENT CALLS (For Bottom Sheet)
  Future<void> _showRecentCalls(BuildContext sheetContext, TextEditingController phoneController) async {
    PermissionStatus status = await Permission.phone.request();

    if (status.isGranted) {
      Iterable<CallLogEntry> entries = await CallLog.get();

      if (!sheetContext.mounted) return;

      showModalBottomSheet(
        context: sheetContext,
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
                    itemCount: entries.length > 20 ? 20 : entries.length, // Top 20 calls
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
                            // Strip all spaces, dashes, and country codes
                            String cleanNumber = entry.number!.replaceAll(RegExp(r'\D'), '');
                            if (cleanNumber.length > 10) {
                              cleanNumber = cleanNumber.substring(cleanNumber.length - 10);
                            }

                            // Instantly update the text field with prefix and no spaces
                            phoneController.text = "+91$cleanNumber";
                          }
                          Navigator.pop(context); // Close the call log list
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Call log permission denied", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        )
      );
    }
  }

  // Safely updates UI in both Main Page and Bottom Sheet
  void _updateMicState(TextEditingController? controller, StateSetter? modalState) {
    _listeningController = controller;
    if (modalState != null) modalState(() {});
    setState(() {});
  }

  // 🗑️ Delete from Database
  Future<void> _deleteMeasurement(Measurement m) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Record?"),
        content: Text("Are you sure you want to delete ${m.name}'s measurement?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("DELETE", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await DBHelper.deletePriceAgreement(m.id!);
      await DBHelper.deleteMeasurement(m.id!);
      _loadMeasurements();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Measurement record deleted.")));
      }
    }
  }

  // ➕ Add New Bottom Sheet
  void _showAddNewBottomSheet() {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController _nameController = TextEditingController();
    final TextEditingController _addressController = TextEditingController();

    // 🔥 Default the phone controller to +91 so the user doesn't have to type it
    final TextEditingController _phoneController = TextEditingController(text: "+91");

    // To hold customer tables records for autocomplete lookup feature
    List<Customer>? _allDbCustomers;
    List<Customer> _matchedCustomers = [];
    bool _isExistingCustomer = false; // Tracks if selected profile is imported from DB

    // Ensure mic is off before opening sheet
    speech.stop();
    _updateMicState(null, null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext statefulContext, StateSetter setModalState) {

            // Asynchronously fetch all master customers if not already loaded
            if (_allDbCustomers == null) {
              DBHelper.getCustomers().then((list) {
                setModalState(() {
                  _allDbCustomers = list;
                });
              });
            }

            // Local helper function to look up existing items matching typed state inputs
            void _updateSuggestions() {
              // Hide suggestion box if we have already locked an existing customer profile
              if (_isExistingCustomer) {
                _matchedCustomers = [];
                return;
              }

              final nameQuery = _nameController.text.trim().toLowerCase();

              // 🟢 Strip out the default "+91" prefix and non-digits to find the actual typed digits
              String typedPhone = _phoneController.text.trim();
              String cleanPhoneQuery = typedPhone.replaceAll("+91", "").replaceAll(RegExp(r'\D'), "");

              // 🟢 INITIALLY HIDDEN: If name is empty AND no phone digits are typed yet, keep list empty
              if (nameQuery.isEmpty && cleanPhoneQuery.isEmpty) {
                _matchedCustomers = [];
              } else {
                _matchedCustomers = (_allDbCustomers ?? []).where((c) {
                  // 1️⃣ Match by Name
                  bool matchesName = nameQuery.isNotEmpty && c.name.toLowerCase().contains(nameQuery);

                  // 2️⃣ Match by Phone (Smart lookup comparing actual digits and last 10 digits fallback)
                  bool matchesPhone = false;
                  if (cleanPhoneQuery.isNotEmpty) {
                    String cleanDbPhone = c.phone.replaceAll(RegExp(r'\D'), '');

                    // Extract last 10 digits for precise cross-matching (+91 vs non-+91 entries)
                    String dbLast10 = cleanDbPhone.length >= 10
                    ? cleanDbPhone.substring(cleanDbPhone.length - 10)
                    : cleanDbPhone;
                    String queryLast10 = cleanPhoneQuery.length >= 10
                    ? cleanPhoneQuery.substring(cleanPhoneQuery.length - 10)
                    : cleanPhoneQuery;

                    matchesPhone = dbLast10.contains(queryLast10) ||
                    cleanDbPhone.contains(cleanPhoneQuery) ||
                    c.phone.contains(cleanPhoneQuery);
                  }

                  // 🟢 Return true if either name or phone number matches the typed search input
                  return matchesName || matchesPhone;
                }).toList();
              }
            }

            // Fire lookup analysis every build cycle to perfectly coordinate text changes
            _updateSuggestions();

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stylish drag handle indicator
                        Center(
                          child: Container(
                            width: 50,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text("নতুন খদ্দেরের মাপ", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 24),

                        // CUSTOMER NAME FIELD
                        TextFormField(
                          controller: _nameController,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText: "Customer Name *",
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                            prefixIcon: const Icon(Icons.person_outline, color: Colors.deepOrange),

                            // 🔥 SHOW CLEAR/UNLOCK OPTION IF EXISTING PROFILE WAS LOADED
                            suffixIcon: _isExistingCustomer
                            ? IconButton(
                              icon: const Icon(Icons.lock_open_rounded, color: Colors.blue, size: 24),
                              tooltip: "Unlock profile fields",
                              onPressed: () {
                                setModalState(() {
                                  _nameController.clear();
                                  _phoneController.text = "+91"; // Reset phone to +91
                                  _addressController.clear();
                                  _isExistingCustomer = false; // Revert everything back
                                });
                              },
                            )
                            : IconButton(
                              icon: Icon(
                                _listeningController == _nameController ? Icons.mic : Icons.mic_none,
                                color: _listeningController == _nameController ? Colors.red : Colors.deepOrange,
                                size: 26,
                              ),
                              onPressed: () => _toggleMic(_nameController, modalState: setModalState),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              // 🔥 IF USER MODIFIES/DELETES SEARCH TEXT, AUTOMATICALLY UNLOCK AND REVERT BACK!
                              if (_isExistingCustomer) {
                                _isExistingCustomer = false;
                              }
                            });
                          },
                          validator: (value) => (value == null || value.trim().isEmpty) ? "Required" : null,
                        ),

                        const SizedBox(height: 16),

                        // 📞 PHONE NUMBER FIELD (LOCKED IF EXISTING)
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          readOnly: _isExistingCustomer,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _isExistingCustomer ? Colors.grey.shade600 : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText: _isExistingCustomer ? "Phone Number (Linked Profile)" : "Phone Number",
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                            prefixIcon: Icon(
                              _isExistingCustomer ? Icons.lock_outline : Icons.phone_outlined,
                              color: _isExistingCustomer ? Colors.grey : Colors.blue,
                            ),
                            suffixIcon: _isExistingCustomer
                            ? null
                            : IconButton(
                              icon: const Icon(Icons.history_rounded, color: Colors.deepOrange),
                              tooltip: "Fetch from call log",
                              onPressed: () => _showRecentCalls(statefulContext, _phoneController),
                            ),
                            filled: true,
                            fillColor: _isExistingCustomer ? Colors.grey.shade200 : Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onChanged: (val) {
                            String rawVal = val;

                            // 1. Remove exactly one explicit '+91' or '+' from the start
                            // to separate the fixed prefix from the user's input.
                            if (rawVal.startsWith('+91')) {
                              rawVal = rawVal.substring(3);
                            } else if (rawVal.startsWith('+')) {
                              rawVal = rawVal.substring(1);
                            }

                            // 2. Strip all spaces, dashes, and letters. Only keep digits.
                            String pureNumber = rawVal.replaceAll(RegExp(r'\D'), '');

                            // 3. Handle double-pasting (e.g. user pasted "+91 98..." into a field that already had "+91")
                            // If the remaining digits start with '91' AND we have more than 10 digits total,
                            // it means an extra country code got mixed in. Strip it securely.
                            while (pureNumber.startsWith('91') && pureNumber.length > 10) {
                              pureNumber = pureNumber.substring(2);
                            }

                            // 4. Enforce max 10 digits for the actual phone number
                            if (pureNumber.length > 10) {
                              pureNumber = pureNumber.substring(0, 10);
                            }

                            // 5. Force the final correct format
                            String formattedText = "+91$pureNumber";

                            // 6. Update text field ONLY if needed to prevent infinite loops
                            if (val != formattedText) {
                              _phoneController.value = TextEditingValue(
                                text: formattedText,
                                selection: TextSelection.collapsed(offset: formattedText.length),
                              );
                            }

                            // Revert lock flag if text changes
                            setModalState(() {
                              if (_isExistingCustomer) {
                                _isExistingCustomer = false;
                              }
                            });
                          },
                        ),

                        // 🌟 DETECTED EXISTING CUSTOMERS SCROLLABLE COMPONENT
                        if (_matchedCustomers.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Row(
                            children: [
                              Icon(Icons.people_outline_rounded, size: 16, color: Colors.blueGrey),
                              SizedBox(width: 6),
                              Text(
                                "Existing Profiles Found (Tap to Autofill):",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200, width: 1.5),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _matchedCustomers.length,
                              separatorBuilder: (context, index) => Divider(color: Colors.grey.shade200, height: 1),
                              itemBuilder: (context, idx) {
                                final customer = _matchedCustomers[idx];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue.shade50,
                                    radius: 15,
                                    child: const Icon(Icons.person, size: 15, color: Colors.blue),
                                  ),
                                  title: Text(
                                    customer.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)
                                  ),
                                  subtitle: Text(
                                    "${customer.phone}${customer.address.isNotEmpty ? ' • ${customer.address}' : ''}",
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    setModalState(() {
                                      _nameController.text = customer.name;

                                      // Safely prefix +91 to the selected DB entry if it's missing
                                      String safePhone = customer.phone;
                                      if (!safePhone.startsWith('+91')) {
                                        safePhone = "+91${safePhone.replaceAll(RegExp(r'\D'), '')}";
                                      }
                                      _phoneController.text = safePhone;

                                      _addressController.text = customer.address;
                                      _isExistingCustomer = true; // 🔥 Set lock flag to active
                                      _matchedCustomers = [];
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // 📍 ADDRESS FIELD (LOCKED IF EXISTING)
                        TextFormField(
                          controller: _addressController,
                          readOnly: _isExistingCustomer, // 🔥 Blocks entry if existing customer profile selected
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _isExistingCustomer ? Colors.grey.shade600 : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText: _isExistingCustomer ? "Address (Linked Profile)" : "Address",
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                            prefixIcon: Icon(
                              _isExistingCustomer ? Icons.lock_outline : Icons.location_on_outlined,
                              color: _isExistingCustomer ? Colors.grey : Colors.green,
                            ),
                            suffixIcon: _isExistingCustomer
                            ? null
                            : IconButton(
                              icon: Icon(
                                _listeningController == _addressController ? Icons.mic : Icons.mic_none,
                                color: _listeningController == _addressController ? Colors.red : Colors.green,
                                size: 26,
                              ),
                              onPressed: () => _toggleMic(_addressController, modalState: setModalState),
                            ),
                            filled: true,
                            fillColor: _isExistingCustomer ? Colors.grey.shade200 : Colors.grey.shade50, // Darker bg when locked
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ➡️ NEXT/SAVE BUTTON
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (_formKey.currentState!.validate()) {
                                Measurement newRecord = Measurement(
                                  name: _nameController.text.trim(),
                                  phone: _phoneController.text.trim(),
                                  address: _addressController.text.trim(),
                                  createdAt: DateTime.now().toIso8601String(),
                                );

                                await DBHelper.insertMeasurement(newRecord);

                                List<Measurement> updatedList = await DBHelper.getMeasurements();
                                Measurement createdRecord = updatedList.lastWhere(
                                  (m) => m.name == newRecord.name && m.phone == newRecord.phone,
                                  orElse: () => newRecord,
                                );

                                speech.stop();
                                _updateMicState(null, null);
                                _loadMeasurements();

                                if (!mounted) return;

                                Navigator.pop(statefulContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Measurement record added!"),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(milliseconds: 1000),
                                  ),
                                );

                                await Future.delayed(const Duration(milliseconds: 400));

                                if (!mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MeasurementDetailPage(measurement: createdRecord),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 2,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("SAVE", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                SizedBox(width: 8),
                                Icon(Icons.check_circle_outline, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      speech.stop();
      _updateMicState(null, null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: AppBar(
        title: const Text("খদ্দেরের মাপ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: _showAddNewBottomSheet,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Colors.deepOrange),
              label: const Text(
                "Add",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 15)
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 2,
                shadowColor: Colors.black.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: Column(
        children: [
          // 🔍 MAIN LOOKUP SEARCH BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _filterMeasurements,
              style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: "Search customer name or phone...",
                hintStyle: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, color: Colors.deepOrange, size: 24),

                // 🔥 CLEAR ICON BACK REVERT OR MIC ICON CONDITION
                suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.deepOrange, size: 24),
                  tooltip: "Clear search",
                  onPressed: () {
                    _searchController.clear();
                    _filterMeasurements('');
                    if (_listeningController == _searchController) {
                      speech.stop();
                      _updateMicState(null, null);
                    }
                    setState(() {});
                  },
                )
                : IconButton(
                  icon: Icon(
                    _listeningController == _searchController ? Icons.mic : Icons.mic_none,
                    color: _listeningController == _searchController ? Colors.red : Colors.grey,
                    size: 24,
                  ),
                  onPressed: () => _toggleMic(_searchController),
                ),
                filled: true,
                fillColor: const Color(0xfff1f3f8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              ),
            ),
          ),

          // 📄 LIST SECTION
          Expanded(
            child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
            : filteredMeasurements.isEmpty
            ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.straighten, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("No records found.", style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ],
              )
            )
            : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredMeasurements.length,
              itemBuilder: (context, index) {
                final Measurement m = filteredMeasurements[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                    image: const DecorationImage(
                      image: AssetImage('assets/images/card_bg1.png'),
                      fit: BoxFit.cover,
                      opacity: 0.25,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MeasurementDetailPage(measurement: m),
                          ),
                        ).then((_) => _loadMeasurements());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.straighten_rounded, color: Colors.deepOrange, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  const SizedBox(height: 6),
                                  if (m.phone.isNotEmpty)
                                    Row(
                                      children: [
                                        const Icon(Icons.phone_rounded, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(m.phone, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    if (m.address.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_rounded, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              m.address,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ],
                                      ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                              tooltip: "Delete",
                              onPressed: () => _deleteMeasurement(m),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
