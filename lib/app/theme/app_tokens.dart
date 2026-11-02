import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const section = 40.0;
}

abstract final class AppRadii {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 14.0;
  static const xl = 18.0;
  static const xxl = 22.0;
  static const full = 999.0;
}

abstract final class AppElevation {
  static const flat = 0.0;
  static const low = 1.0;
  static const overlay = 3.0;
  static const high = 6.0;
}

abstract final class AppTypography {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const extraBold = FontWeight.w800;

  static const displayTracking = -1.1;
  static const headingTracking = -0.5;
}

abstract final class AppSizes {
  static const minimumTouchTarget = 48.0;
  static const controlHeight = 52.0;
  static const contentMaxWidth = 1200.0;
}
