import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme.dart';

// ---------- formatlash ----------

const _weekdays = [
  'Dushanba',
  'Seshanba',
  'Chorshanba',
  'Payshanba',
  'Juma',
  'Shanba',
  'Yakshanba'
];
const _months = [
  'yanvar',
  'fevral',
  'mart',
  'aprel',
  'may',
  'iyun',
  'iyul',
  'avgust',
  'sentyabr',
  'oktyabr',
  'noyabr',
  'dekabr',
];

/// "Payshanba, 11-sentyabr"
String uzDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day}-${_months[d.month - 1]}';

/// 85.0 -> "85", 85.5 -> "85.5"
String fmtNum(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// "998901234567" -> "+998 90 123 45 67"
String fmtPhone(String digits) {
  final d = digits.replaceAll(RegExp(r'\D'), '');
  if (d.length != 12 || !d.startsWith('998')) return d.isEmpty ? '' : '+$d';
  return '+998 ${d.substring(3, 5)} ${d.substring(5, 8)} ${d.substring(8, 10)} ${d.substring(10)}';
}

/// Telefon bo'lsa — raqam, bo'lmasa (eski akkauntlar) — email
String userContact(String phone, String email) => phone.isNotEmpty ? fmtPhone(phone) : email;

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

Color avatarColor(String seed) {
  // To'q fonda o'qiladigan sovuq ranglar — olmos palitrasiga yaqin
  final palette = [
    AppColors.accent,
    AppColors.water,
    AppColors.protein,
    AppColors.success,
    // yorug' rejimda oq fonda o'qiladigan to'qroq variantlar
    Color(AppColors.light ? 0xFF0E7490 : 0xFF67E8F9),
    Color(AppColors.light ? 0xFF4F46E5 : 0xFF818CF8),
    Color(AppColors.light ? 0xFF0F766E : 0xFF2DD4BF),
    Color(AppColors.light ? 0xFFA21CAF : 0xFFF0ABFC),
  ];
  return palette[seed.hashCode.abs() % palette.length];
}

// ---------- fon ----------

/// Ilova foni: to'q grafit + yuqorida yumshoq olmos jilosi.
/// Shisha kartochkalar aynan shu jiloni xiralashtirib "shaffof" ko'rinadi.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: AppColors.bg),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.glow),
          child: child,
        ),
      );
}

// ---------- pastdan chiquvchi varaqlar (pop-up o'rniga) ----------

void showSnack(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Ekran o'rtasidan chiquvchi pop-up o'rniga pastdan chiquvchi varaq:
/// bosh barmoq zonasida, kutilmagan holda ekranni to'smaydi.
Future<T?> showSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
            child: child,
          ),
        ),
      ),
    );

/// Qaytarib bo'lmaydigan amallardan oldin tasdiqlash — pastdan chiquvchi varaqda
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String ok = 'Ha',
  bool destructive = false,
}) async {
  final r = await showSheet<bool>(
    context,
    Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.sm),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpace.xl),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: AppColors.onAccent,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(ok),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
        ]),
  );
  return r ?? false;
}

// ---------- harakat (yumshoq, tez) ----------

/// Ekran ochilganda blok pastdan yumshoq suzib chiqadi.
/// `index` — ketma-ket bloklar biroz kechikib chiqishi uchun.
class FadeInUp extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeInUp({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 340 + index * 60),
        curve: Curves.easeOutCubic,
        builder: (context, v, c) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: c),
        ),
        child: child,
      );
}

/// Raqam eski qiymatdan yangisiga sanab o'tadi
class CountUp extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final String suffix;
  final int decimals;
  const CountUp(this.value, {super.key, this.style, this.suffix = '', this.decimals = 0});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text(
          '${v.toStringAsFixed(decimals)}$suffix',
          style: (style ?? const TextStyle()).copyWith(fontFeatures: tabular),
        ),
      );
}

// ---------- tuzilma ----------

/// Bo'lim ustidagi kichik katta-harfli yozuv
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const Eyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: color ?? AppColors.textFaint),
      );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.eyebrow, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, AppSpace.sm, 2, AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: AppSpace.xs)],
            Text(title, style: t.titleLarge),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Kichik sarlavha — [SectionHeader] ichidagi kichik bo'lim uchun
/// (masalan "Dobavkalar" ichida "Protein", "Gainer" ...).
class SubHeader extends StatelessWidget {
  final String title;
  final int? count;
  final Color? color;
  const SubHeader(this.title, {super.key, this.count, this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, AppSpace.xs, 2, AppSpace.sm),
      child: Row(children: [
        Container(
          width: 3,
          height: 16,
          margin: const EdgeInsets.only(right: AppSpace.sm),
          decoration: BoxDecoration(
            color: color ?? AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(child: Text(title, style: t.titleSmall)),
        if (count != null)
          Text('$count', style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
      ]),
    );
  }
}

/// Shisha kartochka — olmosning shaffofligiga ishora.
///
/// `blur: true` orqa fonni haqiqatan xiralashtiradi (BackdropFilter). U qimmat
/// amal, shuning uchun faqat bosh bloklarda yoqiladi; ro'yxat kataklarida
/// shaffof to'ldirish va yuqori qirradagi yorug' chiziq yetarli.
///
/// `feature: true` — urg'u bloki: olmos ko'ki bilan yengil bo'yalgan shisha.
class BentoTile extends StatelessWidget {
  final Widget child;
  final bool feature;
  final bool blur;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const BentoTile({
    super.key,
    required this.child,
    this.feature = false,
    this.blur = false,
    this.color,
    this.padding = const EdgeInsets.all(AppSpace.md + 2),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    final fill = color ??
        (feature
            ? Color.alphaBlend(AppColors.accent.withValues(alpha: 0.06),
                AppColors.card.withValues(alpha: AppColors.light ? 0.95 : 0.72))
            : AppColors.card.withValues(alpha: AppColors.light ? 0.9 : 0.55));
    final edge = feature ? AppColors.accent.withValues(alpha: 0.22) : AppColors.hairline;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: edge),
        // yuqori qirradagi yorug' chiziq — shishaning sinishi
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: 0.04), fill),
            fill,
          ],
          stops: const [0.0, 0.35],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (blur) {
      content = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: content,
      );
    }
    return ClipRRect(borderRadius: radius, child: content);
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState(
      {super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: FadeInUp(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.card.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Icon(icon, size: 30, color: AppColors.textFaint),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(title, textAlign: TextAlign.center, style: t.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: AppSpace.xl), action!],
          ]),
        ),
      ),
    );
  }
}

// ---------- kichik komponentlar ----------

class UserAvatar extends StatelessWidget {
  final String name;
  final double size;
  const UserAvatar({super.key, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = avatarColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.33,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

/// Rangli fonli kichik ikonka (ichi bo'sh, ingichka chiziqli)
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, {super.key, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Icon(icon, color: color, size: size * 0.46),
      );
}

/// Kichik rangli yorliq (status, makro va h.k.)
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  const Pill({super.key, required this.text, required this.color, this.icon, this.solid = false});

  @override
  Widget build(BuildContext context) {
    final fg = solid ? AppColors.onAccent : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: solid ? null : Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
        Text(
          text,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: tabular,
          ),
        ),
      ]),
    );
  }
}

/// Ko'rsatkich katagi: yirik raqam + izoh
class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BentoTile(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpace.sm - 2),
          // Tor katakda sarlavha qirqilmaydi ("REJA B…"), balki biroz kichrayadi
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                style: t.labelSmall?.copyWith(color: AppColors.textFaint),
              ),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: t.headlineSmall?.copyWith(fontFeatures: tabular)),
        ),
      ]),
    );
  }
}

/// Kaloriya halqasi — ingichka, olmos ko'ki bilan
class KcalRing extends StatelessWidget {
  final double value, total, size;
  final Color? color, trackColor, textColor;
  const KcalRing({
    super.key,
    required this.value,
    required this.total,
    this.size = 120,
    this.color,
    this.trackColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;
    final fg = textColor ?? AppColors.text;
    return SizedBox.square(
      dimension: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => CircularProgressIndicator(
              value: v,
              strokeWidth: size * 0.055,
              strokeCap: StrokeCap.round,
              color: color ?? AppColors.accent,
              backgroundColor: trackColor ?? AppColors.cardHigh,
            ),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          CountUp(value, style: t.headlineMedium?.copyWith(color: fg)),
          const SizedBox(height: 2),
          Text(
            'gacha ${total.round()}',
            style: t.labelSmall?.copyWith(color: AppColors.textFaint, fontFeatures: tabular),
          ),
        ]),
      ]),
    );
  }
}

/// Sahifa boshidagi to'q blok (eski nomi saqlangan)
class GradientHeader extends StatelessWidget {
  final Widget child;
  const GradientHeader({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.headerGradient,
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl)),
        ),
        child: SafeArea(bottom: false, child: child),
      );
}
