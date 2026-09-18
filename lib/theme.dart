import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Diamond dizayn tizimi — to'q grafit fon + olmos ko'ki urg'u
///
/// Qoidalar (60 / 30 / 10):
///  * 60% — fon: mutlaqo qora EMAS, to'q grafit (#16191E). Ko'zni charchatmaydi.
///  * 30% — matn va kartochkalar: sutsimon oq (#E3E8EE), shaffof to'q kulrang (#22262F).
///  * 10% — urg'u: olmos ko'ki (#4AF2FF) faqat eng muhim tugma va ko'rsatkichda.
///  * Burchaklar 8–16 px (keskin ham, ortiqcha yumaloq ham emas).
///  * Ikonkalar ingichka chiziqli (outlined) — to'la ikonka ekranni to'ldirib yuboradi.
///  * Kartochkalar — shisha effekti (shaffof + orqa fon xiralashgan).
///  * Elementlar orasi keng: mashqda qo'l titrasa ham noto'g'ri bosilmaydi.
///  * Asosiy rejim — qorong'i (brend). Foydalanuvchi Profil'da yorug' rejimni ham tanlay oladi:
///    yorug'da olmos ko'ki oq fonda o'qilmaydi, shuning uchun to'qroq ko'k (#0891B2) ishlatiladi.
/// ---------------------------------------------------------------------------

/// Ranglar joriy rejimga qarab qaytariladi ([AppColors.light]). Rejim almashganda
/// butun ilova qayta quriladi (main.dart — MaterialApp kaliti), shuning uchun
/// ranglar `const` emas.
class AppColors {
  /// true — yorug' rejim. main.dart ThemeController o'rnatadi.
  static bool light = false;

  static Color _c(int dark, int lightValue) => Color(light ? lightValue : dark);

  // fon (60%)
  static Color get bg => _c(0xFF16191E, 0xFFF3F5F8); // asosiy fon
  static Color get bgDeep => _c(0xFF11141A, 0xFFE8ECF1); // undan to'qroq qatlam
  static Color get card => _c(0xFF22262F, 0xFFFFFFFF); // kartochka asosi
  static Color get cardHigh => _c(0xFF2C313B, 0xFFEDF0F4); // ustidagi qatlam (maydon, chip)

  // matn (30%)
  static Color get text => _c(0xFFE3E8EE, 0xFF151A21);
  static Color get textMuted => _c(0xFF96A0AE, 0xFF545E6B);
  static Color get textFaint => _c(0xFF6B7480, 0xFF858E9A);

  // urg'u (10%) — faqat eng muhim joyda
  static Color get accent => _c(0xFF4AF2FF, 0xFF0891B2); // Diamond Blue / to'q ko'k
  static Color get accentSoft => _c(0xFF7DF9FF, 0xFF0E7490);
  static Color get onAccent => _c(0xFF08131A, 0xFFFFFFFF); // urg'u ustidagi matn

  // holat ranglari — har rejim fonida o'qiladigan variantlar
  static Color get success => _c(0xFF4ADE80, 0xFF15803D);
  static Color get warning => _c(0xFFFBBF24, 0xFFB45309);
  static Color get danger => _c(0xFFFB7185, 0xFFE11D48);
  static Color get water => _c(0xFF38BDF8, 0xFF0369A1);
  static Color get protein => _c(0xFFA78BFA, 0xFF7C3AED);

  /// Chegara — juda past shaffoflikdagi qirra (shisha qirrasi)
  static Color get hairline => _c(0x14FFFFFF, 0x1A0F172A);
  static Color get hairlineSoft => _c(0x0AFFFFFF, 0x0F0F172A);

  /// Fon ustidagi yumshoq olmos jilosi — shisha effekti shuni xiralashtiradi
  static RadialGradient get glow => RadialGradient(
        center: const Alignment(0, -1.05),
        radius: 1.25,
        colors: light
            ? const [Color(0x220891B2), Color(0x00F3F5F8), Color(0x00F3F5F8)]
            : const [Color(0x2B4AF2FF), Color(0x0011141A), Color(0x0011141A)],
        stops: const [0.0, 0.55, 1.0],
      );

  /// Sahifa boshidagi blok
  static LinearGradient get headerGradient => LinearGradient(
        colors: [light ? const Color(0xFFE4F2F6) : const Color(0xFF1D222B), bg],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

/// Bo'shliq shkalasi. Bloklar orasi keng — mashq paytida qo'l titrasa ham
/// tugmalar bir-biriga yaqin bo'lib qolmaydi.
class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const xxl = 40.0;
}

/// Burchak radiuslari — 8 dan 16 gacha
class AppRadius {
  static const sm = 8.0;
  static const md = 10.0;
  static const lg = 12.0;
  static const xl = 16.0;
  static const pill = 999.0;
}

/// Raqamlar bir xil kenglikda tursin (jadval va hisoblagichlar uchun)
const tabular = [FontFeature.tabularFigures()];

/// Bosiladigan elementning eng kichik balandligi — barmoq uchun
const kTouchTarget = 52.0;

class AppTheme {
  static const radius = AppRadius.md;

  /// Joriy rejim ([AppColors.light]) bo'yicha tema
  static ThemeData current() => dark();

  static ThemeData dark() {
    final isLight = AppColors.light;
    final s = (isLight ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      primaryContainer: isLight ? const Color(0xFFD5F1F7) : const Color(0xFF123A44),
      onPrimaryContainer: AppColors.accentSoft,
      secondary: AppColors.water,
      onSecondary: AppColors.onAccent,
      surface: AppColors.card,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.textMuted,
      surfaceContainerHighest: AppColors.cardHigh,
      surfaceContainerHigh: AppColors.cardHigh,
      surfaceContainer: AppColors.card,
      outline: isLight ? const Color(0xFFC5CCD5) : const Color(0xFF3A4049),
      outlineVariant: isLight ? const Color(0xFFDCE1E7) : const Color(0xFF2A2F38),
      error: AppColors.danger,
      onError: AppColors.onAccent,
      inverseSurface: AppColors.text,
      onInverseSurface: AppColors.bg,
    );

    final theme = ThemeData(
      colorScheme: s,
      useMaterial3: true,
      brightness: isLight ? Brightness.light : Brightness.dark,
    );
    final r = BorderRadius.circular(AppRadius.md);

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: r,
          borderSide: BorderSide(color: c, width: w),
        );

    return theme.copyWith(
      // Fon MaterialApp.builder ichida jilosi bilan chiziladi — bu yerda shaffof
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: AppColors.bg,
      textTheme: _textTheme(theme.textTheme),
      iconTheme: IconThemeData(color: AppColors.textMuted, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.text, size: 22),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: AppColors.text,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.card.withValues(alpha: AppColors.light ? 0.9 : 0.55),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: AppColors.hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md + 2,
          vertical: AppSpace.md + 4,
        ),
        border: border(AppColors.hairline),
        enabledBorder: border(AppColors.hairline),
        focusedBorder: border(AppColors.accent, 1.5),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 1.5),
        prefixIconColor: AppColors.textFaint,
        suffixIconColor: AppColors.textFaint,
        hintStyle: TextStyle(color: AppColors.textFaint),
        labelStyle: TextStyle(color: AppColors.textMuted),
        floatingLabelStyle: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
        helperStyle: TextStyle(color: AppColors.textFaint, fontSize: 12),
      ),
      // Asosiy amal — olmos ko'ki faqat shu yerda
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.cardHigh,
          disabledForegroundColor: AppColors.textFaint,
          minimumSize: const Size(64, kTouchTarget + 4),
          shape: RoundedRectangleBorder(borderRadius: r),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(64, kTouchTarget),
          side: BorderSide(color: AppColors.hairline),
          shape: RoundedRectangleBorder(borderRadius: r),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: const Size(56, kTouchTarget - 4),
          shape: RoundedRectangleBorder(borderRadius: r),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      // Pastki menyu — bosh barmoq zonasi, ikonkalar ingichka chiziqli
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.accent.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (st) => IconThemeData(
            size: 23,
            color: st.contains(WidgetState.selected) ? AppColors.accent : AppColors.textFaint,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (st) => TextStyle(
            fontSize: 11.5,
            letterSpacing: 0.1,
            fontWeight: st.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: st.contains(WidgetState.selected) ? AppColors.accent : AppColors.textFaint,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        extendedTextStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      chipTheme: theme.chipTheme.copyWith(
        backgroundColor: AppColors.cardHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        side: BorderSide.none,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      // Pop-up o'rniga pastdan chiquvchi varaq ishlatiladi (ui.dart: confirm/showSheet)
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: AppColors.text,
        ),
        contentTextStyle: TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.cardHigh,
        contentTextStyle: TextStyle(color: AppColors.text, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: r),
        iconColor: AppColors.textMuted,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.hairlineSoft,
        space: 1,
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: AppColors.textFaint,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accent,
        circularTrackColor: AppColors.cardHigh,
        linearTrackColor: AppColors.cardHigh,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.cardHigh,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: TextStyle(color: AppColors.text, fontSize: 12),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  /// Sarlavhalar zich, matn keng qatorli — to'q fonda o'qish qulay bo'lsin
  static TextTheme _textTheme(TextTheme t) => t
      .copyWith(
        displaySmall: t.displaySmall?.copyWith(
          fontSize: 38,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.4,
          height: 1.0,
        ),
        headlineLarge: t.headlineLarge?.copyWith(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          height: 1.1,
        ),
        headlineMedium: t.headlineMedium?.copyWith(
          fontSize: 25,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.15,
        ),
        headlineSmall: t.headlineSmall?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
        ),
        titleLarge: t.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: t.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
        bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 1.55),
        bodySmall: t.bodySmall?.copyWith(fontSize: 12.5, height: 1.4),
        labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        // "eyebrow" — bo'lim ustidagi kichik katta-harfli yozuv
        labelSmall: t.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      )
      .apply(bodyColor: AppColors.text, displayColor: AppColors.text);
}
