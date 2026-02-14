import 'package:flutter/material.dart';

class AppStyles {
  // Modern Color Palette
  static const Color blackColor = Color(0xFF0B0E14); // Deep rich background
  static const Color surfaceColor = Color(0xFF1A1F29); // Slightly lighter for cards
  static const Color themeColor = Color(0xFF00E5FF); // Electric Cyan
  static const Color whiteColor = Color(0xFFE0E0E0); // Off-white for less eye strain
  static const Color greyColor = Color(0xFF8A939E); // Cool grey
  static const Color redColor = Color(0xFFFF4858); // Soft bright red

  // Derived Colors with varying opacity
  static Color get outerBoarderColor => whiteColor.withValues(alpha: .05);
  static Color get innerBoarderColor => whiteColor.withValues(alpha: 0.1);
  static Color get highlightColor => themeColor.withValues(alpha: 0.15);

  // Text Styles
  static const TextStyle titleLine = TextStyle(
    fontSize: 40,
    color: AppStyles.whiteColor,
    fontWeight: FontWeight.w200, // Thinner, more elegant
    letterSpacing: 1.5,
  );

  static const TextStyle subTitleLine = TextStyle(
    fontSize: 18,
    color: AppStyles.greyColor,
    fontWeight: FontWeight.w300,
    letterSpacing: 0.5,
  );

  static const TextStyle tableTitle = TextStyle(
    fontSize: 14,
    color: AppStyles.greyColor,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle captionLine = TextStyle(
    fontSize: 12,
    color: AppStyles.greyColor,
    fontStyle: FontStyle.italic,
  );

  static const TextStyle tableTitleW = TextStyle(
    fontSize: 14,
    color: AppStyles.whiteColor,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle labelTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppStyles.greyColor,
  );

  static const TextStyle labelValue = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppStyles.themeColor, // Highlight values
  );

  static const TextStyle enabledItem = TextStyle(
    fontWeight: FontWeight.bold,
    color: AppStyles.whiteColor,
    shadows: const [Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))],
  );

  static const TextStyle disabledItem = TextStyle(
    fontWeight: FontWeight.normal,
    color: AppStyles.greyColor,
  );

  static TextStyle buttonTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppStyles.whiteColor.withValues(alpha: 0.9),
    letterSpacing: 0.8,
  );

  // Decorations

  // Main content frame with glassmorphism feel
  static final mainFrameDecoration = BoxDecoration(
    color: surfaceColor.withValues(alpha: 0.7),
    gradient: LinearGradient(
      colors: [surfaceColor.withValues(alpha: 0.8), surfaceColor.withValues(alpha: 0.5)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    border: Border.all(color: innerBoarderColor, width: 1),
    borderRadius: BorderRadius.circular(16), // Softer corners
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.4),
        blurRadius: 20,
        spreadRadius: 2,
        offset: const Offset(0, 10),
      ),
    ],
  );

  // Pipe visualization container
  static final pipeDecoration = BoxDecoration(
    color: Colors.black.withValues(alpha: 0.3),
    border: Border.all(color: themeColor.withValues(alpha: 0.2), width: 1),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(color: themeColor.withValues(alpha: 0.05), blurRadius: 15, spreadRadius: 0),
    ],
  );

  static final videoFrameDecoration = BoxDecoration(
    color: Colors.black,
    border: Border.all(color: themeColor.withValues(alpha: 0.3), width: 2),
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(color: themeColor.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 1),
    ],
  );

  static InputDecoration textFieldDecoration(String label, Icon icon) => InputDecoration(
    filled: true,
    fillColor: surfaceColor,
    labelText: label,
    labelStyle: const TextStyle(color: AppStyles.greyColor),
    hintStyle: TextStyle(color: AppStyles.whiteColor.withValues(alpha: 0.3)),
    contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: innerBoarderColor),
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: themeColor, width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
    prefixIcon: Icon(icon.icon, color: themeColor.withValues(alpha: 0.7)),
  );

  static ButtonStyle primaryButtonStyle(Color color) => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
      if (states.contains(WidgetState.hovered)) {
        return color.withValues(alpha: 0.2);
      }
      return color.withValues(alpha: 0.1);
    }),
    overlayColor: WidgetStateProperty.resolveWith<Color?>(
      (Set<WidgetState> states) => color.withValues(alpha: 0.1),
    ),
    side: WidgetStateProperty.resolveWith<BorderSide?>((Set<WidgetState> states) {
      if (states.contains(WidgetState.hovered)) {
        return BorderSide(color: color, width: 2);
      }
      return BorderSide(color: color.withValues(alpha: 0.5), width: 1);
    }),
    elevation: WidgetStateProperty.all(0),
    shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 22, horizontal: 24)),
    shadowColor: WidgetStateProperty.all(color.withValues(alpha: 0.4)),
  );

  static ButtonStyle secondaryButtonStyle(Color color) => ButtonStyle(
    backgroundColor: WidgetStateProperty.all(Colors.transparent),
    overlayColor: WidgetStateProperty.resolveWith<Color?>(
      (Set<WidgetState> states) => color.withValues(alpha: 0.05),
    ),
    side: WidgetStateProperty.resolveWith<BorderSide?>((Set<WidgetState> states) {
      if (states.contains(WidgetState.hovered)) {
        return BorderSide(color: color.withValues(alpha: 0.8), width: 1);
      }
      return BorderSide(color: color.withValues(alpha: 0.3), width: 1);
    }),
    shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
  );

  static ButtonStyle prviewButtonStyle(Color color) => ButtonStyle(
    backgroundColor: WidgetStateProperty.all(color.withValues(alpha: 0.1)),
    side: WidgetStateProperty.resolveWith<BorderSide?>((Set<WidgetState> states) {
      if (states.contains(WidgetState.hovered)) {
        return BorderSide(color: color, width: 2);
      }
      return BorderSide(color: color.withValues(alpha: 0.6), width: 2);
    }),
    shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 18, horizontal: 24)),
    shadowColor: WidgetStateProperty.all(color.withValues(alpha: 0.2)),
    elevation: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.hovered) ? 8 : 0,
    ),
  );

  // Padding
  static const EdgeInsets pagePadding = EdgeInsets.all(24);
}
