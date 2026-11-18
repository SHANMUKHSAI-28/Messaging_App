import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:flutter_contacts/flutter_contacts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SOSApp());
}

class EmergencyContact {
  String name;
  String phone;

  EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}

class SOSApp extends StatelessWidget {
  const SOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeSOS - Emergency Alert',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}


class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;
  List<EmergencyContact> _contacts = [];
  List<Contact> _systemContacts = [];
  bool _isLoadingSystemContacts = false;
  String _customMessage = "EMERGENCY! I need immediate help. My current location is:";
  List<String> _history = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      perm.Permission.location,
      perm.Permission.sms,
      perm.Permission.contacts,
    ].request();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final contactsData = prefs.getStringList('sos_contacts');
    if (contactsData != null) {
      setState(() {
        _contacts = contactsData
            .map((item) => EmergencyContact.fromJson(jsonDecode(item)))
            .toList();
      });
    } else {
      setState(() {
        _contacts = [
          EmergencyContact(name: 'Family / ICE', phone: '+1234567890'),
        ];
      });
      _saveContacts();
    }

    final savedMsg = prefs.getString('sos_message');
    if (savedMsg != null) {
      setState(() {
        _customMessage = savedMsg;
      });
    }

    final historyData = prefs.getStringList('sos_history');
    if (historyData != null) {
      setState(() {
        _history = historyData;
      });
    }
  }

  Future<void> _loadSystemContacts() async {
    setState(() {
      _isLoadingSystemContacts = true;
    });

    try {
      PermissionStatus status = await FlutterContacts.permissions.request(PermissionType.readWrite);
      if (status != PermissionStatus.granted) {
        throw 'Contacts permission denied';
      }

      List<Contact> contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      setState(() {
        _systemContacts = contacts;
        _isLoadingSystemContacts = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingSystemContacts = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load contacts: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  }

  void _showImportContactsDialog() {
    if (_systemContacts.isEmpty) {
      _loadSystemContacts();
      return;
    }

    // Create a map to track selection state
    Set<int> selectedIndices = {};

    // Pre-select contacts that are already in emergency contacts
    for (int i = 0; i < _systemContacts.length; i++) {
      Contact sysContact = _systemContacts[i];
      String normalizedSysPhone = _normalizePhone(sysContact.phones.isNotEmpty ? sysContact.phones.first.number : '');
      for (var emContact in _contacts) {
        if (_normalizePhone(emContact.phone) == normalizedSysPhone) {
          selectedIndices.add(i);
          break;
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Import from System Contacts'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: _isLoadingSystemContacts
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      const Text('Select contacts to add as emergency contacts:'),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _systemContacts.length,
                          itemBuilder: (context, index) {
                            Contact contact = _systemContacts[index];
                            String phone = contact.phones.isNotEmpty ? contact.phones.first.number : 'No phone';
                            String displayName = (contact.displayName ?? '').isNotEmpty ? contact.displayName! : 'Unknown';
                            bool isSelected = selectedIndices.contains(index);

                            return CheckboxListTile(
                              title: Text(displayName),
                              subtitle: Text(phone),
                              value: isSelected,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedIndices.add(index);
                                  } else {
                                    selectedIndices.remove(index);
                                  }
                                });
                              },
                              secondary: CircleAvatar(
                                backgroundColor: Colors.red[800],
                                child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white),
              onPressed: () {
                for (int index in selectedIndices) {
                  Contact sysContact = _systemContacts[index];
                  if (sysContact.phones.isNotEmpty) {
                    String phone = sysContact.phones.first.number;
                    String name = (sysContact.displayName ?? '').isNotEmpty ? sysContact.displayName! : 'Unknown';
                    
                    // Check if already exists
                    bool exists = _contacts.any((c) => _normalizePhone(c.phone) == _normalizePhone(phone));
                    if (!exists) {
                      _contacts.add(EmergencyContact(name: name, phone: phone));
                    }
                  }
                }
                _saveContacts();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added ${selectedIndices.length} contact(s) to emergency list')),
                );
              },
              child: const Text('Import Selected'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsData = _contacts
        .map((contact) => jsonEncode(contact.toJson()))
        .toList();
    await prefs.setStringList('sos_contacts', contactsData);
  }

  Future<void> _saveMessage(String msg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sos_message', msg);
    setState(() {
      _customMessage = msg;
    });
  }

  Future<void> _saveHistory(String log) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _history.insert(0, log);
      if (_history.length > 20) _history.removeLast();
    });
    await prefs.setStringList('sos_history', _history);
  }

  Future<void> _triggerSOS() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one emergency contact in the Contacts tab!'),
          backgroundColor: Colors.orange,
        ),
      );
      setState(() {
        _currentIndex = 1;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled. Please enable GPS.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied.';
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String googleMapsUrl = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      String message = '$_customMessage\n$googleMapsUrl';
      List<String> recipients = _contacts.map((c) => c.phone).toList();

      await sendSMS(message: message, recipients: recipients);
      
      String timestamp = DateTime.now().toString().substring(0, 19);
      await _saveHistory('[$timestamp] SOS Sent to ${recipients.length} contact(s). Loc: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SOS SMS interface launched for ${recipients.length} contacts!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      String timestamp = DateTime.now().toString().substring(0, 19);
      await _saveHistory('[$timestamp] SOS Failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeTab(),
      _buildContactsTab(),
      _buildSettingsTab(),
      _buildHistoryTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeSOS Emergency', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red[900],
        elevation: 4,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.redAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'SOS Home'),
          BottomNavigationBarItem(icon: Icon(Icons.contacts), label: 'Contacts'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'EMERGENCY ASSIST',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Press the SOS button below to instantly broadcast your GPS location to ${_contacts.length} emergency contact(s).',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 50),
            _isLoading
                ? const CircularProgressIndicator(color: Colors.red, strokeWidth: 5)
                : GestureDetector(
                    onTap: _triggerSOS,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Colors.redAccent, Colors.red[900]!],
                          center: Alignment.center,
                          radius: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.6),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 56,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _contacts.isEmpty
                          ? 'No emergency contacts selected!'
                          : '${_contacts.length} Contact(s) configured ready for SOS.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentIndex = 1),
                    child: const Text('Manage', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Emergency Contacts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _showImportContactsDialog,
                    icon: const Icon(Icons.import_contacts),
                    label: const Text('Import from Phone'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800], 
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showAddContactDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Manually'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'These contacts will receive your live GPS location link when SOS is triggered.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _contacts.isEmpty
                ? const Center(
                    child: Text('No emergency contacts added yet. Tap "Import from Phone" or "Add Manually" above.'),
                  )
                : ListView.builder(
                    itemCount: _contacts.length,
                    itemBuilder: (context, index) {
                      final contact = _contacts[index];
                      return Card(
                        color: Colors.grey[900],
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red[800],
                            child: Text(contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?'),
                          ),
                          title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(contact.phone),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () {
                              setState(() {
                                _contacts.removeAt(index);
                              });
                              _saveContacts();
                            },
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

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Contact Name (e.g., Mom)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number (e.g., +1234567890)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white),
            onPressed: () {
              if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
                setState(() {
                  _contacts.add(EmergencyContact(
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                  ));
                });
                _saveContacts();
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    final msgController = TextEditingController(text: _customMessage);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text(
            'SOS Message Customization',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Edit the text message that gets sent along with your GPS location link.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: msgController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Custom SOS Message',
            ),
          ),
          const SizedBox(height: 15),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white),
            onPressed: () {
              _saveMessage(msgController.text.trim());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SOS message updated successfully!')),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Message'),
          ),
          const Divider(height: 40),
          const Text(
            'Permissions & Info',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.location_on, color: Colors.redAccent),
            title: const Text('Location Access'),
            subtitle: const Text('Required to fetch exact GPS coordinates'),
            trailing: TextButton(
              onPressed: () => Geolocator.openAppSettings(),
              child: const Text('Open Settings'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sms, color: Colors.redAccent),
            title: const Text('SMS Permission'),
            subtitle: const Text('Required to send emergency texts'),
            trailing: TextButton(
              onPressed: () => perm.openAppSettings(),
              child: const Text('Open Settings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SOS Event History',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (_history.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('sos_history');
                    setState(() {
                      _history.clear();
                    });
                  },
                  icon: const Icon(Icons.delete_sweep, color: Colors.grey),
                  label: const Text('Clear', style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _history.isEmpty
                ? const Center(
                    child: Text('No SOS alerts triggered yet.'),
                  )
                : ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      return Card(
                        color: Colors.grey[900],
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            _history[index],
                            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
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


