import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

class MyApp extends StatelessWidget {
  final String? notificationPayload;

  const MyApp({super.key, this.notificationPayload});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cacao Light 4.0',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: HomeScreen(
        title: 'Cacao Light 4.0',
        notificationPayload: notificationPayload,
      ),
    );
  }
}
