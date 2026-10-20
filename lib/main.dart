import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/bluetooth_service.dart';
import 'screens/bluetooth_screen.dart';
import 'screens/control_screen.dart';
import 'screens/serial_terminal_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final isFirstTime = prefs.getBool('isFirstTime') ?? true;

  runApp(ArduinoControllerApp(isFirstTime: isFirstTime));
}

class ArduinoControllerApp extends StatelessWidget {
  final bool isFirstTime;
  const ArduinoControllerApp({super.key, required this.isFirstTime});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
      ],
      child: MaterialApp(
        title: 'Arduino Araba Kumandası',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.blueGrey,
          fontFamily: 'Inter', // Eğer Inter fontu yoksa varsayılan kullanılacak
        ),
        home: isFirstTime ? const OnboardingScreen() : const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 1; // Varsayılan olarak Kontrol ekranı ile başla

  void _selectScreen(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Kontrol ekranı yatay bir kumanda gibi tüm yüksekliği kullanıyor: alt menü orada
    // gizli, ekranlar arası geçiş kontrol ekranının üst çubuğundaki düğmelerle yapılıyor.
    final isControlScreen = _currentIndex == 1;

    return Scaffold(
      body: switch (_currentIndex) {
        0 => const BluetoothScreen(),
        1 => ControlScreen(
            appBarActions: [
              IconButton(
                icon: const Icon(Icons.bluetooth),
                tooltip: 'Bağlantı',
                onPressed: () => _selectScreen(0),
              ),
              IconButton(
                icon: const Icon(Icons.terminal),
                tooltip: 'Terminal',
                onPressed: () => _selectScreen(2),
              ),
            ],
          ),
        _ => const SerialTerminalScreen(),
      },
      bottomNavigationBar: isControlScreen
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: _selectScreen,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.bluetooth),
                  label: 'Bağlantı',
                ),
                NavigationDestination(
                  icon: Icon(Icons.gamepad),
                  label: 'Kontrol',
                ),
                NavigationDestination(
                  icon: Icon(Icons.terminal),
                  label: 'Terminal',
                ),
              ],
            ),
    );
  }
}
