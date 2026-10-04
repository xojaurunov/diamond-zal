import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/change_password.dart';
import '../../widgets/join_qr_sheet.dart';
import '../../widgets/notification_sync.dart';
import '../../widgets/settings_sheet.dart';
import '../../widgets/ui.dart';
import '../notifications_screen.dart';
import 'clients_screen.dart';
import 'gym_admin_screen.dart';
import 'plans_screen.dart';
import 'foods_screen.dart';
import 'shop_admin_screen.dart';
import 'staff_screen.dart';
import 'subscriptions_screen.dart';

class AdminHome extends ConsumerStatefulWidget {
  const AdminHome({super.key});
  @override
  ConsumerState<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends ConsumerState<AdminHome> {
  int _tab = 0;
  bool _dirSynced = false;

  // Bosh adminda qo'shimcha "Xodimlar" bo'limi bo'ladi
  static const _trainerTitles = [
    'Mijozlar',
    'Abonement',
    'Zal',
    'Ovqatlanish rejalari',
    'Mahsulotlar bazasi',
    "Do'kon",
    'Eslatmalar',
  ];
  static const _ownerTitles = [..._trainerTitles, 'Xodimlar va shogirdlar'];

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      title: 'Chiqish',
      message: 'Trener panelidan chiqmoqchimisiz?',
      ok: 'Chiqish',
      destructive: true,
    );
    if (ok) await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).value;
    if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final s = Theme.of(context).colorScheme;
    // Bosh admin ochganda trenerlar katalogi haqiqiy trenerlar bilan tenglashtiriladi
    if (me.isOwner && !_dirSynced) {
      _dirSynced = true;
      Db.syncTrainerDirectory().ignore();
    }
    final titles = me.isOwner ? _ownerTitles : _trainerTitles;
    // Rol o'zgarsa (masalan trenerlikdan olinsa) tanlangan bo'lim chegaradan chiqmasin
    final tab = _tab < titles.length ? _tab : 0;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[tab]),
            Text(
              me.isOwner ? 'Bosh admin • Diamond' : 'Trener paneli • Diamond',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: me.isOwner ? AppColors.accent : s.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'QR kod',
            onPressed: () => showJoinQr(context),
            icon: const Icon(Icons.qr_code_2_outlined),
          ),
          IconButton(
            tooltip: 'Sozlamalar',
            onPressed: () => showSettings(context, student: false),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: "Parolni o'zgartirish",
            onPressed: () => showChangePassword(context),
            icon: const Icon(Icons.key_outlined),
          ),
          IconButton(tooltip: 'Chiqish', onPressed: _signOut, icon: const Icon(Icons.logout)),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: IndexedStack(
            index: tab,
            children: [
              ClientsScreen(admin: me),
              SubscriptionsScreen(admin: me),
              GymAdminScreen(admin: me),
              const PlansScreen(),
              const FoodsScreen(),
              ShopAdminScreen(admin: me),
              NotificationsScreen(user: me),
              if (me.isOwner) StaffScreen(owner: me),
            ],
          ),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        // bo'lim ko'p — yozuv faqat tanlanganida
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        // Faqat ingichka chiziqli ikonkalar (dizayn qoidasi)
        destinations: [
          const NavigationDestination(icon: Icon(Icons.people_outline), label: 'Mijozlar'),
          const NavigationDestination(
              icon: Icon(Icons.card_membership_outlined), label: 'Abonement'),
          const NavigationDestination(icon: Icon(Icons.fitness_center_outlined), label: 'Zal'),
          const NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Rejalar'),
          const NavigationDestination(icon: Icon(Icons.egg_alt_outlined), label: 'Ovqat'),
          const NavigationDestination(icon: Icon(Icons.storefront_outlined), label: "Do'kon"),
          NavigationDestination(
            icon: FeedBadge(user: me, icon: const Icon(Icons.notifications_none)),
            label: 'Eslatma',
          ),
          if (me.isOwner)
            const NavigationDestination(icon: Icon(Icons.badge_outlined), label: 'Xodimlar'),
        ],
      ),
    );
    // Trener shogirdlaridan kelgan xabarlar haqida bildirishnoma oladi
    return me.isTrainer ? TrainerNotificationSync(trainer: me, child: scaffold) : scaffold;
  }
}
