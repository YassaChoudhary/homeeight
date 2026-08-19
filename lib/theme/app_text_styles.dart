import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography scale — Section 7.3 of the Product Blueprint.
/// Font: Circular Std.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle _base({
    required double size,
    required double height,
    required FontWeight weight,
    Color color = AppColors.ink,
  }) {
    return TextStyle(
      fontFamily: 'CircularStd',
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      color: color,
    );
  }

  static TextStyle display({Color color = AppColors.ink}) =>
      _base(size: 28, height: 34, weight: FontWeight.w700, color: color);

  static TextStyle h1({Color color = AppColors.ink}) =>
      _base(size: 22, height: 28, weight: FontWeight.w700, color: color);

  static TextStyle h2({Color color = AppColors.ink}) =>
      _base(size: 18, height: 24, weight: FontWeight.w600, color: color);

  static TextStyle body({Color color = AppColors.ink}) =>
      _base(size: 15, height: 22, weight: FontWeight.w400, color: color);

  static TextStyle bodyStrong({Color color = AppColors.ink}) =>
      _base(size: 15, height: 22, weight: FontWeight.w600, color: color);

  static TextStyle caption({Color color = AppColors.inkMuted}) =>
      _base(size: 13, height: 18, weight: FontWeight.w400, color: color);

  static TextStyle micro({Color color = AppColors.inkMuted}) =>
      _base(size: 11, height: 14, weight: FontWeight.w600, color: color);
}
