import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'main.dart'; // for TacticalColors

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  String _jwtToken = '';
  String _userRole = '';
  String _userProvince = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    _jwtToken = prefs.getString('jwt_token') ?? '';
    _userRole = prefs.getString('user_role') ?? '';
    _userProvince = prefs.getString('user_province') ?? '';

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.serverUrl}/api/users'),
        headers: {'Authorization': 'Bearer $_jwtToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _users = data['users'];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUser(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TacticalColors.panel,
        title: const Text('Kullanıcıyı Sil', style: TextStyle(color: TacticalColors.red)),
        content: const Text('Bu kullanıcıyı silmek istediğinize emin misiniz?', style: TextStyle(color: TacticalColors.textPrimary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İPTAL', style: TextStyle(color: TacticalColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('SİL', style: TextStyle(color: TacticalColors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.serverUrl}/api/users/$id'),
        headers: {'Authorization': 'Bearer $_jwtToken'},
      );
      if (response.statusCode == 200) {
        _loadUsers();
      }
    } catch (e) {
      debugPrint('Error deleting user: $e');
    }
  }

  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = _userRole == 'MERKEZ' ? 'RESCUER' : 'RESCUER';
    String selectedProvince = _userProvince;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: TacticalColors.panel,
          title: const Text('Yeni Personel Ekle', style: TextStyle(color: TacticalColors.cyan)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: TacticalColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'İsim Soyisim', labelStyle: TextStyle(color: TacticalColors.textSecondary)),
                ),
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: TacticalColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'E-Posta', labelStyle: TextStyle(color: TacticalColors.textSecondary)),
                ),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: TacticalColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Şifre', labelStyle: TextStyle(color: TacticalColors.textSecondary)),
                ),
                if (_userRole == 'MERKEZ') ...[
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    dropdownColor: TacticalColors.bg,
                    style: const TextStyle(color: TacticalColors.textPrimary),
                    items: ['RESCUER', 'IL_BASKANI', 'MERKEZ'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (v) => setDialogState(() => selectedRole = v!),
                    decoration: const InputDecoration(labelText: 'Rol', labelStyle: TextStyle(color: TacticalColors.textSecondary)),
                  ),
                  TextField(
                    onChanged: (v) => selectedProvince = v,
                    style: const TextStyle(color: TacticalColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'İl (Örn: ISTANBUL)', labelStyle: TextStyle(color: TacticalColors.textSecondary)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İPTAL', style: TextStyle(color: TacticalColors.textSecondary))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: TacticalColors.cyan),
              onPressed: () async {
                try {
                  final response = await http.post(
                    Uri.parse('${AppConfig.serverUrl}/api/users'),
                    headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_jwtToken'},
                    body: jsonEncode({
                      'name': nameController.text,
                      'email': emailController.text,
                      'password': passwordController.text,
                      'role': selectedRole,
                      'province': selectedProvince,
                    }),
                  );
                  if (response.statusCode == 200) {
                    Navigator.pop(context);
                    _loadUsers();
                  } else {
                    debugPrint('Error adding user: ${response.body}');
                  }
                } catch (e) {
                  debugPrint('Network error');
                }
              },
              child: const Text('EKLE', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TacticalColors.bg,
      appBar: AppBar(
        backgroundColor: TacticalColors.surface,
        title: const Text('PERSONEL YÖNETİMİ', style: TextStyle(color: TacticalColors.cyan, fontSize: 14, letterSpacing: 2)),
        iconTheme: const IconThemeData(color: TacticalColors.textPrimary),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: TacticalColors.cyan))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final u = _users[index];
                return Card(
                  color: TacticalColors.panel,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      u['role'] == 'MERKEZ' ? Icons.star : (u['role'] == 'IL_BASKANI' ? Icons.shield : Icons.person),
                      color: u['role'] == 'MERKEZ' ? TacticalColors.orange : TacticalColors.cyan,
                    ),
                    title: Text(u['name'], style: const TextStyle(color: TacticalColors.textPrimary, fontWeight: FontWeight.bold)),
                    subtitle: Text('${u['email']} | ${u['role']} ${u['province'] != null ? '(${u['province']})' : ''}', style: const TextStyle(color: TacticalColors.textSecondary, fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: TacticalColors.red),
                      onPressed: () => _deleteUser(u['id']),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: TacticalColors.cyan,
        onPressed: _showAddUserDialog,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}
