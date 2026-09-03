import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/quran_qiraat_app.dart';
import 'data/quran_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final quran = await QuranRepository.load();
  runApp(QuranQiraatApp(preferences: preferences, quran: quran));
}
