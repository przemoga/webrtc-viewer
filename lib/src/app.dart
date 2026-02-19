import 'package:flutter/material.dart';
import '../style.dart';
import 'screens/viewer_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCTV Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppStyles.blackColor,
        colorScheme: ColorScheme.dark(
          primary: AppStyles.themeColor,
          surface: AppStyles.surfaceColor,
          onSurface: AppStyles.whiteColor,
        ),
      ),
      home: const ViewerPage(),
    );
  }
}
