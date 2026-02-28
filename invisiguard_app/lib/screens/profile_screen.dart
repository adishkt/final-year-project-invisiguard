import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _editing = false;
  bool _saving = false;
  bool _loading = true;

  final _formKey = GlobalKey<FormState>();
  final _parentCtrl = TextEditingController();
  final _childCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _savedParent = '';
  String _savedChild = '';
  String _savedPhone = '';

  // Email comes from Firebase Auth — never editable
  String get _authEmail => FirebaseAuth.instance.currentUser?.email ?? '—';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _parentCtrl.dispose();
    _childCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Load from Firestore ────────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (doc.exists) {
      final d = doc.data()!;
      _savedParent = d['parentName'] ?? '';
      _savedChild = d['childName'] ?? '';
      _savedPhone = d['phoneNumber'] ?? '';
      _parentCtrl.text = _savedParent;
      _childCtrl.text = _savedChild;
      _phoneCtrl.text = _savedPhone;
    }

    if (mounted) setState(() => _loading = false);
  }

  // ── Save to Firestore ──────────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'parentName': _parentCtrl.text.trim(),
      'childName': _childCtrl.text.trim(),
      'phoneNumber': _phoneCtrl.text.trim(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() {
      _savedParent = _parentCtrl.text.trim();
      _savedChild = _childCtrl.text.trim();
      _savedPhone = _phoneCtrl.text.trim();
      _saving = false;
      _editing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile saved'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _cancelEdit() {
    _parentCtrl.text = _savedParent;
    _childCtrl.text = _savedChild;
    _phoneCtrl.text = _savedPhone;
    setState(() => _editing = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit profile',
              onPressed: _loading
                  ? null
                  : () => setState(() => _editing = true),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Avatar ───────────────────────────────────────────
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Text(
                        _savedParent.isNotEmpty
                            ? _savedParent[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (!_editing) ...[
                      // ── VIEW MODE ──────────────────────────────────────
                      _profileCard(
                        icon: Icons.person,
                        label: 'Parent Name',
                        value: _savedParent.isNotEmpty ? _savedParent : '—',
                      ),
                      const SizedBox(height: 12),
                      _profileCard(
                        icon: Icons.school,
                        label: 'Child Name',
                        value: _savedChild.isNotEmpty ? _savedChild : '—',
                      ),
                      const SizedBox(height: 12),
                      _profileCard(
                        icon: Icons.phone,
                        label: 'Phone Number',
                        value: _savedPhone.isNotEmpty ? _savedPhone : '—',
                      ),
                      const SizedBox(height: 12),
                      _lockedEmailCard(),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit Profile'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => setState(() => _editing = true),
                        ),
                      ),
                    ] else ...[
                      // ── EDIT MODE ──────────────────────────────────────
                      _inputField(
                        controller: _parentCtrl,
                        label: 'Parent Name',
                        icon: Icons.person,
                        hint: 'Enter parent / guardian name',
                      ),
                      const SizedBox(height: 14),
                      _inputField(
                        controller: _childCtrl,
                        label: 'Child Name',
                        icon: Icons.school,
                        hint: 'Enter child name',
                      ),
                      const SizedBox(height: 14),
                      _inputField(
                        controller: _phoneCtrl,
                        label: 'Phone Number',
                        icon: Icons.phone,
                        hint: 'Enter 10-digit phone number',
                        keyboard: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        required: false,
                        validatePhone: true,
                      ),
                      const SizedBox(height: 14),
                      // Email is locked — it's the Firebase Auth login email
                      _lockedEmailCard(),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _cancelEdit,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(_saving ? 'Saving…' : 'Save'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _saving ? null : _saveProfile,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _profileCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Read-only email card — shows Firebase Auth email with a lock badge.
  Widget _lockedEmailCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.email_outlined,
            size: 22,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email ID',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _authEmail,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Email cannot be changed\n(used for account login)',
            child: Icon(
              Icons.lock_outline,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization textCapitalize = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
    bool required = true,
    bool validatePhone = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: textCapitalize,
      inputFormatters: inputFormatters,
      validator: (v) {
        final val = v?.trim() ?? '';
        if (required && val.isEmpty) return 'This field is required';
        if (validatePhone && val.isNotEmpty) {
          // Strip any non-digits before length check (safety net)
          final digits = val.replaceAll(RegExp(r'\D'), '');
          if (digits.length != 10) {
            return 'Enter a valid 10-digit phone number';
          }
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
