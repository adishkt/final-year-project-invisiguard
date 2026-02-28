import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationController = TextEditingController();
  
  String? _editingContactId;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationController.dispose();
    super.dispose();
  }

  // 📝 EDIT CONTACT
  void _editContact(Map<String, dynamic> contact, String contactId) {
    _editingContactId = contactId;
    _nameController.text = contact['name'] ?? '';
    _phoneController.text = contact['phone'] ?? '';
    _relationController.text = contact['relation'] ?? '';
    
    _showContactDialog(isEditing: true);
  }

  // 🗑️ DELETE CONTACT
  void _deleteContact(String contactId, String contactName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Contact"),
        content: Text("Are you sure you want to delete $contactName?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser!.uid;
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('emergency_contacts')
                  .doc(contactId)
                  .delete();
              
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("$contactName deleted"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  // ➕ ADD/EDIT CONTACT DIALOG
  void _showContactDialog({bool isEditing = false}) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(isEditing ? "Edit Contact" : "Add Emergency Contact"),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Name",
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _relationController,
                        decoration: const InputDecoration(
                          labelText: "Relation (e.g., Father, Mother)",
                          prefixIcon: Icon(Icons.group),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: "Phone Number",
                          prefixIcon: Icon(Icons.phone),
                          hintText: "+911234567890",
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter phone number';
                          }
                          // Basic phone validation
                          if (!RegExp(r'^[+0-9\s\-]{10,}$').hasMatch(value)) {
                            return 'Enter valid phone number';
                          }
                          return null;
                        },
                      ),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: CircularProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _clearForm();
                    Navigator.pop(context);
                  },
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      setState(() => _isLoading = true);
                      await _saveContact(isEditing);
                      if (mounted) {
                        setState(() => _isLoading = false);
                        _clearForm();
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: Text(isEditing ? "Update" : "Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 💾 SAVE CONTACT TO FIREBASE
  Future<void> _saveContact(bool isEditing) async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final contactData = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'relation': _relationController.text.trim(),
        'receiveAlerts': true, // Changed from 'smsEnabled' to 'receiveAlerts'
        'updatedAt': Timestamp.now(),
      };

      if (isEditing && _editingContactId != null) {
        // Update existing contact
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('emergency_contacts')
            .doc(_editingContactId)
            .update(contactData);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Contact updated successfully"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Add new contact
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('emergency_contacts')
            .add({
              ...contactData,
              'createdAt': Timestamp.now(),
            });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Contact added successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 🧹 CLEAR FORM
  void _clearForm() {
    _nameController.clear();
    _phoneController.clear();
    _relationController.clear();
    _editingContactId = null;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Contacts"),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: "About Emergency Contacts",
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("About Emergency Contacts"),
                  content: const Text(
                    "Add people who should receive SOS alerts.\n\n"
                    "• They will receive SMS with location when SOS is triggered\n"
                    "• Toggle alerts on/off for each contact\n"
                    "• Long press to delete contact\n"
                    "• Tap contact to edit details",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text("Add Contact"),
        onPressed: () {
          _clearForm();
          _showContactDialog();
        },
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('emergency_contacts')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.contacts,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "No Emergency Contacts",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Add contacts who should receive\nSOS alerts in emergencies",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Add First Contact"),
                    onPressed: () {
                      _clearForm();
                      _showContactDialog();
                    },
                  ),
                ],
              ),
            );
          }

          final contacts = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final doc = contacts[index];
              final data = doc.data() as Map<String, dynamic>;
              final contactId = doc.id;
              final name = data['name'] ?? 'Unknown';
              final phone = data['phone'] ?? '';
              final relation = data['relation'] ?? 'Contact';
              final receiveAlerts = data['receiveAlerts'] ?? true;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  // Leading: Avatar with initial
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  
                  // Title and Subtitle
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (receiveAlerts)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green),
                          ),
                          child: Text(
                            "ALERTS ON",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$relation • $phone",
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "ID: ${contactId.substring(0, 8)}...",
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),

                  // Trailing: Toggle and Menu
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 📱 SMS ALERTS TOGGLE
                      Switch(
                        value: receiveAlerts,
                        activeColor: Colors.green,
                        onChanged: (value) async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('emergency_contacts')
                              .doc(contactId)
                              .update({
                                'receiveAlerts': value,
                                'updatedAt': Timestamp.now(),
                              });
                        },
                      ),
                      
                      // 🗑️ DELETE BUTTON (only shown on long press)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text("Edit Contact"),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red, size: 18),
                                SizedBox(width: 8),
                                Text("Delete", style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          if (value == 'edit') {
                            _editContact(data, contactId);
                          } else if (value == 'delete') {
                            _deleteContact(contactId, name);
                          }
                        },
                      ),
                    ],
                  ),

                  // TAP TO EDIT
                  onTap: () => _editContact(data, contactId),
                  
                  // LONG PRESS TO DELETE
                  onLongPress: () => _deleteContact(contactId, name),
                ),
              );
            },
          );
        },
      ),
    );
  }
}