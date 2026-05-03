import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Nunito-based text styles. All sizes respect MediaQuery.textScaler
/// (clamped to 1.5× max in app.dart).
class AppTextStyles {
  AppTextStyles._();

  static TextStyle display(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 40,
        fontWeight: FontWeight.w900,
        color: color ?? Theme.of(c).colorScheme.onSurface,
      );

  static TextStyle h1(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: color ?? Theme.of(c).colorScheme.onSurface,
      );

  static TextStyle h2(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: color ?? Theme.of(c).colorScheme.onSurface,
      );

  static TextStyle h3(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: color ?? Theme.of(c).colorScheme.onSurface,
      );

  static TextStyle bodyLarge(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color ?? Theme.of(c).colorScheme.onSurface,
      );

  static TextStyle body(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color ?? Theme.of(c).colorScheme.onSurface,
      );

  static TextStyle caption(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color ?? Theme.of(c).colorScheme.onSurfaceVariant,
      );

  /// Session timer — dominant element. Bigger font for accessibility users.
  static TextStyle timer(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 72,
        fontWeight: FontWeight.w900,
        color: color ?? Theme.of(c).colorScheme.onSurface,
        letterSpacing: -2,
        height: 1,
      );

  static TextStyle button(BuildContext c, {Color? color}) => GoogleFonts.nunito(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: color ?? Colors.white,
      );
}
