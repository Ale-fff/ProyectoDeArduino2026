import 'dart:async';

import 'package:flutter/material.dart';

import 'data/ble/ble_client.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final link = BleLink();
  // Se lanza sin await a proposito: la app tiene que pintar ya, aunque el
  // Bluetooth tarde. La pantalla unica ya muestra el estado de la conexion.
  unawaited(link.initialize());

  runApp(PuertaVozApp(link: link));
}

class PuertaVozApp extends StatelessWidget {
  const PuertaVozApp({super.key, required this.link});

  final BleLink link;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puerta por voz',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: HomeScreen(link: link),
    );
  }
}
