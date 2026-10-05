import 'dart:async';

import 'package:flutter/material.dart';

import 'data/ble/ble_client.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final link = BleLink();

  runApp(ManejIAApp(link: link, bleReady: link.initialize()));
}

class ManejIAApp extends StatefulWidget {
  const ManejIAApp({super.key, required this.link, required this.bleReady});

  final BleLink link;

  /// El arranque del Bluetooth. El splash espera esto, asi que no hace falta
  /// `await` aqui: la app se dibuja igual y el splash tapa el hueco.
  final Future<void> bleReady;

  @override
  State<ManejIAApp> createState() => _ManejIAAppState();
}

class _ManejIAAppState extends State<ManejIAApp> {
  /// Empieza en claro aunque el movil este en modo oscuro.
  ///
  /// Con `ThemeMode.system` la app aparecia de golpe con el acento azul de
  /// noche a media tarde, y la persona no llega a elegir. Ahora el color es
  /// una decision suya y se recuerda durante la sesion.
  ThemeMode _themeMode = ThemeMode.light;

  /// `true` mientras se muestra el splash.
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ManejIA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: _showSplash
          ? SplashScreen(
              ready: widget.bleReady,
              onFinished: () {
                if (mounted) setState(() => _showSplash = false);
              },
            )
          : HomeScreen(
              link: widget.link,
              isDarkMode: _themeMode == ThemeMode.dark,
              onToggleTheme: _toggleTheme,
            ),
    );
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }
}