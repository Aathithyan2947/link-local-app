import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../data/profile_repository.dart';
import 'change_password_screen.dart';
import 'manage_email_screen.dart';
import 'manage_phone_screen.dart';

/// "Log In & Change Password" — hub linking to the My Email / My Phone Number / Change
/// Password pages.
class LoginSecurityScreen extends ConsumerWidget {
  const LoginSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Log In & Change Password'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(message: e.toString()))),
        data: (p) => Container(
          color: AppColors.surface,
          child: Column(
            children: [
              _row(context, Icons.mail_outline, 'My Email',
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageEmailScreen()))),
              const Divider(height: 1, color: AppColors.border, indent: 20),
              _row(context, Icons.phone_outlined, 'My Phone Number',
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManagePhoneScreen()))),
              const Divider(height: 1, color: AppColors.border, indent: 20),
              _row(context, Icons.lock_outline, 'Change Password',
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
