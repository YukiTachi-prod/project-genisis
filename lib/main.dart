import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core/app_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  WakelockPlus.enable();
  runApp(HomeAiApp(config: config));
}
