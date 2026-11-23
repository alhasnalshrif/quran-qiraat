import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const quranLocales = [Locale('ar')];
const quranLocalizations = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

abstract final class QuranDesign {
  static const gap = 8.0;
  static const gutter = 16.0;
  static const section = 24.0;
  static const control = 48.0;
  static const icon = 20.0;
  static const controlRadius = 14.0;
  static const dockRadius = 24.0;
  static const sheetRadius = 28.0;
  static const motion = Duration(milliseconds: 220);
}

ThemeData quranTheme({required bool night}) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff286455),
        brightness: night ? Brightness.dark : Brightness.light,
        surface: night ? Colors.black : const Color(0xfffcfaf3),
      ).copyWith(
        primary: night ? const Color(0xffb3d4c4) : const Color(0xff285d4f),
        onPrimary: night ? const Color(0xff102c23) : Colors.white,
        primaryContainer: night
            ? const Color(0xff263d33)
            : const Color(0xffdce8df),
        onPrimaryContainer: night
            ? const Color(0xffdbebe3)
            : const Color(0xff224a3d),
        tertiaryContainer: night
            ? const Color(0xff30291c)
            : const Color(0xfff2e9d7),
        onTertiaryContainer: night
            ? const Color(0xffe3d6ad)
            : const Color(0xff594720),
        onSurface: night ? const Color(0xffcdcac2) : const Color(0xff191814),
        surfaceContainerLow: night
            ? const Color(0xff171a19)
            : const Color(0xfff5f5ed),
        surfaceContainerHigh: night
            ? const Color(0xff222726)
            : const Color(0xffeaf0e9),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'NotoSansArabic',
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.45,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.45,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.55),
      bodySmall: TextStyle(fontSize: 12, height: 1.55),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
    ),
    iconTheme: const IconThemeData(size: QuranDesign.icon),
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerLow),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuranDesign.controlRadius),
      ),
    ),
  );
}

/// Bounded glass used by navigation and sheets. The Quran page has its own ink
/// and paper colors so its legibility is independent of the material.
class QuranGlass extends StatelessWidget {
  const QuranGlass({
    super.key,
    required this.child,
    this.radius = QuranDesign.dockRadius,
    this.native = false,
    this.floating = false,
  });

  final Widget child;
  final double radius;
  final bool native;
  final bool floating;

  static const _channel = MethodChannel('quran/native_glass');
  static final _nativeAvailable = _checkNativeGlass();

  static Future<bool> _checkNativeGlass() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final night = colors.brightness == Brightness.dark;
    final opaque = MediaQuery.highContrastOf(context);
    final shape = BorderRadius.circular(radius);
    final tint = floating
        ? (night ? const Color(0xff222526) : const Color(0xfffffdf8))
        : (night ? const Color(0xff262626) : const Color(0xfffcfaf6));
    final blur = floating ? 14.0 : 18.0;
    final fill = DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(
          alpha: opaque ? 1 : (floating ? (night ? .64 : .61) : .86),
        ),
        borderRadius: shape,
        border: floating && !opaque
            ? null
            : Border.all(
                color: opaque
                    ? colors.outline
                    : night
                    ? const Color(0xff484848)
                    : const Color(0xffdbd7cf),
              ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    Widget fallback = ClipRRect(
      borderRadius: shape,
      child: opaque
          ? fill
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: fill,
            ),
    );
    if (floating && !opaque) {
      fallback = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: night ? .28 : .13),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: _GlassRim(radius: radius, night: night),
          child: fallback,
        ),
      );
    }
    if (!native ||
        opaque ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      return fallback;
    }
    return FutureBuilder<bool>(
      future: _nativeAvailable,
      builder: (context, snapshot) {
        if (snapshot.data != true) return fallback;
        return ClipRRect(
          borderRadius: shape,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: UiKitView(
                    key: ValueKey((night, radius)),
                    viewType: 'quran/native_glass',
                    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                    creationParams: {'dark': night, 'radius': radius},
                    creationParamsCodec: const StandardMessageCodec(),
                  ),
                ),
              ),
              Material(type: MaterialType.transparency, child: child),
            ],
          ),
        );
      },
    );
  }
}

class _GlassRim extends CustomPainter {
  const _GlassRim({required this.radius, required this.night});

  final double radius;
  final bool night;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(.5);
    final light = Colors.white;
    final shade = const Color(0xff665949);
    final rim = LinearGradient(
      begin: const Alignment(-.8, -1),
      end: const Alignment(.9, 1),
      colors: night
          ? [
              light.withValues(alpha: .48),
              light.withValues(alpha: .09),
              const Color(0xffd3e8eb).withValues(alpha: .27),
            ]
          : [
              light.withValues(alpha: .98),
              shade.withValues(alpha: .25),
              light.withValues(alpha: .84),
            ],
      stops: const [0, .59, 1],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(radius - .5)),
      Paint()
        ..shader = rim.createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_GlassRim oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.night != night;
}

class QuranGlassSheet extends StatelessWidget {
  const QuranGlassSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => QuranGlass(
    radius: QuranDesign.sheetRadius,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const SizedBox(width: 32, height: 4),
          ),
        ),
        Flexible(child: child),
      ],
    ),
  );
}

class QuranChoiceGroup<T> extends StatelessWidget {
  const QuranChoiceGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Wrap(
      spacing: QuranDesign.gap,
      runSpacing: QuranDesign.gap,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: selected == value,
            showCheckmark: false,
            onSelected: (_) => onSelected(value),
            padding: const EdgeInsets.symmetric(
              horizontal: QuranDesign.gap,
              vertical: QuranDesign.gap,
            ),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: selected == value
                  ? colors.onPrimaryContainer
                  : colors.onSurface,
            ),
            selectedColor: colors.primaryContainer,
            backgroundColor: colors.surfaceContainerLow,
            side: BorderSide(
              color: selected == value ? colors.primary : colors.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(QuranDesign.controlRadius),
            ),
          ),
      ],
    );
  }
}
