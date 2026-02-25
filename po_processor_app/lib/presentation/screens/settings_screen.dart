import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/language_provider.dart';
import '../providers/auth_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../data/services/gemini_ai_service.dart';
import '../../data/services/email_service.dart';
import '../../data/services/test_data_generator.dart';
import '../providers/po_provider.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isTestingApi = false;
  bool _isClearingTestPOs = false;
  final _emailService = EmailService();
  final _testDataGenerator = TestDataGenerator();
  final _emailPasswordController = TextEditingController();
  bool _isEmailConfigured = false;
  bool _isLoadingEmailConfig = true;

  @override
  void initState() {
    super.initState();
    _checkEmailConfiguration();
  }

  @override
  void dispose() {
    _emailPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkEmailConfiguration() async {
    setState(() => _isLoadingEmailConfig = true);
    try {
      final password = await _emailService.getEmailPassword();
      setState(() {
        _isEmailConfigured = password != null && password.isNotEmpty;
        if (_isEmailConfigured) {
          _emailPasswordController.text = '••••••••'; // Show masked password
        }
        _isLoadingEmailConfig = false;
      });
    } catch (e) {
      setState(() => _isLoadingEmailConfig = false);
    }
  }

  Future<void> _saveEmailPassword() async {
    if (_emailPasswordController.text.isEmpty || 
        _emailPasswordController.text == '••••••••') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email app password'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await _emailService.setEmailPassword(_emailPasswordController.text);
      setState(() {
        _isEmailConfigured = true;
        _emailPasswordController.text = '••••••••';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email password saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving password: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testApiConnection() async {
    setState(() => _isTestingApi = true);
    try {
      final aiService = GeminiAIService();
      final result = await aiService.testApiConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(result 
                  ? 'API connection test successful!' 
                  : 'API connection test completed with warnings'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('API test failed: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingApi = false);
      }
    }
  }

  Future<void> _clearTestPOs() async {
    setState(() => _isClearingTestPOs = true);
    try {
      await _testDataGenerator.clearTestPurchaseOrders();
      if (mounted) {
        ref.read(poProvider.notifier).loadPurchaseOrders();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test purchase orders cleared from the system'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing test POs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearingTestPOs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('settings'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'language'.tr(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text('select_language'.tr()),
                    trailing: DropdownButton<String>(
                      value: language,
                      items: [
                        DropdownMenuItem(
                          value: 'en',
                          child: Text('english'.tr()),
                        ),
                        DropdownMenuItem(
                          value: 'ta',
                          child: Text('tamil'.tr()),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          ref.read(languageProvider.notifier).setLanguage(value);
                          context.setLocale(Locale(value));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Email Configuration',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingEmailConfig)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    TextField(
                      controller: _emailPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Gmail App Password',
                        hintText: 'Enter your Gmail app password',
                        border: const OutlineInputBorder(),
                        suffixIcon: _isEmailConfigured
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                      ),
                      obscureText: true,
                      onChanged: (value) {
                        if (value != '••••••••') {
                          setState(() => _isEmailConfigured = false);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'For Gmail, generate an app password at: myaccount.google.com/apppasswords',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saveEmailPassword,
                        icon: const Icon(Icons.save),
                        label: Text(_isEmailConfigured ? 'Update Password' : 'Save Password'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info),
                  title: Text('about'.tr()),
                  subtitle: Text('${'version'.tr()} ${AppConstants.appVersion}'),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: AppConstants.appName,
                      applicationVersion: AppConstants.appVersion,
                      applicationLegalese: 'ElevateIonix',
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: Text('security'.tr()),
                  subtitle: Text('secure_data_storage'.tr()),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.eco),
                  title: Text('sustainability'.tr()),
                  subtitle: Text('green_tech_enabled'.tr()),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.api, color: Colors.blue),
                  title: const Text('Test API Connection'),
                  subtitle: const Text('Verify Gemini API key is working'),
                  trailing: _isTestingApi 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _isTestingApi ? null : _testApiConnection,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cleaning_services, color: Colors.orange),
                  title: const Text('Clear test POs'),
                  subtitle: const Text('Permanently remove TEST-PO- entries from the system'),
                  trailing: _isClearingTestPOs
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _isClearingTestPOs ? null : _clearTestPOs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text(
                    'logout'.tr(),
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    ref.read(authProvider.notifier).logout();
                    context.go('/login');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

