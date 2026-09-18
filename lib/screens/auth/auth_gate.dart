import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import '../admin/admin_home.dart';
import '../user/profile_setup_screen.dart';
import '../user/user_home.dart';
import 'login_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return auth.when(
      loading: () => const _Splash(),
      error: (e, _) => _ErrorView(message: '$e'),
      data: (user) {
        if (user == null) return const LoginScreen();
        final me = ref.watch(meProvider);
        return me.when(
          loading: () => const _Splash(),
          error: (e, _) => _ErrorView(message: '$e'),
          data: (u) {
            // Hujjat yo'q: yo hozir ro'yxatdan o'tilyapti (hujjat yaratilmoqda),
            // yo bosh admin akkauntni o'chirgan. Farqini kutib aniqlaymiz.
            if (u == null) return const _NoProfile();
            if (u.isAdmin) return const AdminHome();
            // Zalda trener bo'lsa — shogird trenerini tanlashi shart
            final trainers = ref.watch(trainerDirectoryProvider).value ?? const [];
            final needTrainer = u.trainerId == null && trainers.isNotEmpty;
            // Maqsad, metabolizm yoki trener tanlanmagan shogird anketaga qaytadi
            if (!u.profileDone || u.goal.isEmpty || u.metabolism.isEmpty || needTrainer) {
              return ProfileSetupScreen(user: u);
            }
            return const UserHome();
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.fitness_center, size: 30, color: AppColors.onAccent),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                'Diamond zal',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: AppSpace.xxl),
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Xatolik yuz berdi',
          subtitle: message,
          action: const OutlinedButton(onPressed: AuthService.signOut, child: Text('Qayta kirish')),
        ),
      );
}

/// Kirish akkaunti bor, lekin Firestore'da hujjati yo'q.
///
/// Ikki holat bo'lishi mumkin:
///  * ro'yxatdan o'tish endi tugadi — hujjat bir soniyada yaratiladi;
///  * bosh admin akkauntni o'chirgan — hujjat qaytmaydi.
///
/// Shuning uchun avval kutamiz, keyingina xabar ko'rsatamiz.
class _NoProfile extends StatefulWidget {
  const _NoProfile();

  @override
  State<_NoProfile> createState() => _NoProfileState();
}

class _NoProfileState extends State<_NoProfile> {
  static const _grace = Duration(seconds: 5);
  Timer? _timer;
  bool _waited = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_grace, () {
      if (mounted) setState(() => _waited = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_waited) return const _Splash();
    return Scaffold(
      body: EmptyState(
        icon: Icons.no_accounts_outlined,
        title: 'Akkaunt topilmadi',
        subtitle: "Akkauntingiz o'chirilgan bo'lishi mumkin. Shu raqam bilan qaytadan "
            "ro'yxatdan o'tishingiz mumkin.",
        action: Column(mainAxisSize: MainAxisSize.min, children: [
          FilledButton(
            onPressed: _busy ? null : _restart,
            child: const Text("Qaytadan ro'yxatdan o'tish"),
          ),
          const SizedBox(height: AppSpace.sm),
          const OutlinedButton(onPressed: AuthService.signOut, child: Text('Chiqish')),
        ]),
      ),
    );
  }

  bool _busy = false;

  /// O'chirilgan akkauntning qolgan kirish yozuvini (Auth) o'chiradi — shunda shu telefon
  /// raqam bilan yangidan ro'yxatdan o'tish mumkin bo'ladi ("raqam band" xatosi chiqmaydi)
  Future<void> _restart() async {
    final pass = TextEditingController();
    final ok = await showSheet<bool>(
      context,
      Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Qaytadan ro'yxatdan o'tish", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Text(
              "Eski kirish ma'lumotlari o'chiriladi, keyin shu raqam bilan yangidan ro'yxatdan "
              "o'tasiz. Tasdiqlash uchun hozirgi parolingizni kiriting.",
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: pass,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Parol',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
                onPressed: () => Navigator.pop(context, true), child: const Text('Davom etish')),
            const SizedBox(height: AppSpace.sm),
            OutlinedButton(
                onPressed: () => Navigator.pop(context, false), child: const Text('Bekor qilish')),
          ]),
    );
    if (ok != true || pass.text.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await AuthService.deleteOwnLogin(pass.text);
      // kirish akkaunti o'chdi — AuthGate o'zi login ekraniga qaytaradi
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        showSnack(
          context,
          e.code == 'wrong-password' || e.code == 'invalid-credential'
              ? "Parol noto'g'ri"
              : "Bo'lmadi: ${e.code}",
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, "Bo'lmadi: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
