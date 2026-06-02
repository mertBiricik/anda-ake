import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'main.dart'; // For TacticalColors and navigatorKey

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = "E-posta ve şifre gereklidir.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.serverUrl}/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', data['token']);
        await prefs.setString('user_role', data['user']['role']);
        await prefs.setString('user_province', data['user']['province'] ?? '');
        await prefs.setString('user_name', data['user']['name']);

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/');
        }
      } else {
        setState(() {
          _errorMessage = data['error'] ?? "Giriş başarısız.";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Sunucuya bağlanılamadı. Ağ bağlantınızı kontrol edin.";
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TacticalColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo & Header
                Image.asset(
                  'assets/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24),
                const Text(
                  'ANDA AKE',
                  style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w900,
                    letterSpacing: 4.0, color: TacticalColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'YETKİLİ PERSONEL GİRİŞİ',
                  style: TextStyle(
                    fontSize: 12, letterSpacing: 2.0,
                    color: TacticalColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 48),

                // Error Message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: TacticalColors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: TacticalColors.red.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: TacticalColors.red, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: TacticalColors.red, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Email Field
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: TacticalColors.textPrimary),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'E-POSTA ADRESİ',
                    labelStyle: TextStyle(color: TacticalColors.textSecondary.withOpacity(0.8), fontSize: 12, letterSpacing: 1.0),
                    prefixIcon: const Icon(Icons.person, color: TacticalColors.textSecondary),
                    filled: true,
                    fillColor: TacticalColors.surface,
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: TacticalColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: TacticalColors.cyan),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Password Field
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: TacticalColors.textPrimary),
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'GÜVENLİK ŞİFRESİ',
                    labelStyle: TextStyle(color: TacticalColors.textSecondary.withOpacity(0.8), fontSize: 12, letterSpacing: 1.0),
                    prefixIcon: const Icon(Icons.lock, color: TacticalColors.textSecondary),
                    filled: true,
                    fillColor: TacticalColors.surface,
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: TacticalColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: TacticalColors.cyan),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TacticalColors.cyan.withOpacity(0.15),
                      foregroundColor: TacticalColors.cyan,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: BorderSide(color: TacticalColors.cyan.withOpacity(0.5), width: 1.5),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24, width: 24,
                            child: CircularProgressIndicator(color: TacticalColors.cyan, strokeWidth: 2),
                          )
                        : const Text(
                            'SİSTEME BAĞLAN',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2.0),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
