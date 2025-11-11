import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness b) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    colorSchemeSeed: Colors.pinkAccent,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: b == Brightness.dark ? Colors.white : Colors.black,
      ),
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.all(8),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      elevation: 2,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}

