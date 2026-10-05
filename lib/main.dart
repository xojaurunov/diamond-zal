import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/auth/auth_gate.dart';
import 'firebase_options.dart';
import 'services/settings.dart';
import 'theme.dart';
import 'widgets/ui.dart';

/// true — lokal Firebase Emulator (akkaunt kerak emas, `firebase emulators:start`).
/// false — haqiqiy Firebase (telefon/istalgan joyda ishlaydi, SMS uchun ham shu).
const useEmulator = false;

/// Emulyator qaysi kompyuterda: web uchun localhost, telefon uchun kompyuterning IP manzili
/// flutter build apk --dart-define=EMULATOR_HOST=172.16.18.51
/// USB orqali (tarmoq yopiq bo'lsa): EMULATOR_HOST=127.0.0.1 + `adb reverse tcp:9099 tcp:9099` va `tcp:8085`
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

/// Internet tunnel (bore.pub) portlarni o'zgartiradi:
/// --dart-define=EMULATOR_HOST=bore.pub --dart-define=AUTH_PORT=... --dart-define=FIRESTORE_PORT=...
const _authPort = int.fromEnvironment('AUTH_PORT', defaultValue: 9099);
const _firestorePort = int.fromEnvironment('FIRESTORE_PORT', defaultValue: 8085);

/// Faqat 'localhost' Android emulyatorda 10.0.2.2 ga almashtiriladi; 127.0.0.1 — adb reverse uchun o'zicha qoladi
const _hostMapping = _emulatorHost == 'localhost';

// "demo-" bilan boshlangan loyiha faqat emulyatorda ishlaydi, kalitlar soxta bo'lishi mumkin
const _emulatorOptions = FirebaseOptions(
  apiKey: 'demo-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-kotta-qani',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: useEmulator ? _emulatorOptions : DefaultFirebaseOptions.currentPlatform,
    );
    if (useEmulator) {
      await FirebaseAuth.instance
          .useAuthEmulator(_emulatorHost, _authPort, automaticHostMapping: _hostMapping);
      FirebaseFirestore.instance
          .useFirestoreEmulator(_emulatorHost, _firestorePort, automaticHostMapping: _hostMapping);
    }
  } catch (e) {
    runApp(_FirebaseMissing(error: '$e'));
    return;
  }
  await AppSettings.init();
  runApp(const ProviderScope(child: App()));
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // "Telefon sozlamasiga qarab" rejimida telefon temasi almashsa — ilova ham almashadi
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, mode, _) {
        final platformLight =
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.light;
        final light = mode == ThemeMode.light || (mode == ThemeMode.system && platformLight);
        AppColors.light = light;
        return MaterialApp(
          // Ranglar const emas — rejim almashganda butun daraxt qayta quriladi
          key: ValueKey(light),
          title: 'Diamond',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.current(),
          darkTheme: AppTheme.current(),
          themeMode: light ? ThemeMode.light : ThemeMode.dark,
          builder: (context, child) => _WideScreenFrame(
            child: AppBackdrop(child: child ?? const SizedBox()),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Keng ekranda (web/desktop) ilova telefon kengligida markazda ko'rinadi
class _WideScreenFrame extends StatelessWidget {
  final Widget child;
  const _WideScreenFrame({required this.child});

  static const _maxWidth = 520.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width < 700) return child;
    return ColoredBox(
      color: AppColors.bgDeep,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: MediaQuery(
            data: mq.copyWith(size: Size(_maxWidth, mq.size.height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}

/// Firebase sozlanmagan bo'lsa qizil xato o'rniga tushunarli ko'rsatma chiqadi
class _FirebaseMissing extends StatelessWidget {
  final String error;
  const _FirebaseMissing({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off, size: 64, color: AppColors.accent),
              const SizedBox(height: 12),
              const Text('Firebase sozlanmagan',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                "Terminalda `flutterfire configure` ni bajaring va main.dart dagi "
                "ikki qatorni kommentdan chiqaring (README.md ga qarang).",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}
