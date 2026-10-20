import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/bluetooth_service.dart';
import '../widgets/direction_button.dart';
import '../widgets/action_button.dart';
import '../widgets/vehicle_settings_dialog.dart';

class ControlScreen extends StatefulWidget {
  /// Üst çubuğa eklenecek düğmeler. Bu ekranda alt menü gizli olduğu için ekranlar arası
  /// geçiş bu düğmelerle yapılır.
  final List<Widget> appBarActions;

  const ControlScreen({super.key, this.appBarActions = const []});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final Set<String> _activeDirections = {};
  // Ekran kapanırken (dispose) context ile provider aranamadığı için baştan saklanıyor.
  late final BluetoothProvider _bluetoothProvider;

  @override
  void initState() {
    super.initState();
    _bluetoothProvider = Provider.of<BluetoothProvider>(context, listen: false);
    // Ekrana girildiğinde yatay moda zorla
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }

  @override
  void dispose() {
    // Güvenlik: yön tuşu basılıyken ekrandan çıkılırsa (ör. sekme değişti) aracı durdur.
    if (_activeDirections.isNotEmpty) {
      _activeDirections.clear();
      _bluetoothProvider.sendCommand('S', description: 'Kontrol ekranından çıkıldı - Dur');
    }
    // Ekrandan çıkıldığında dikey moda geri dön (veya serbest bırak)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sadece bu ekranda görünen alanlar değişince yeniden çiz; terminale düşen her satırda
    // kontrol ekranının tamamı yeniden çizilmesin.
    final (isConnected, deviceName, isLightOn, isMusicPlaying) = context.select(
      (BluetoothProvider p) => (p.isConnected, p.connectedDevice?.name, p.isLightOn, p.isMusicPlaying),
    );

    // Butonlar arası boşluk
    const double gap = 16.0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Araç Kontrolü', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 16),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isConnected ? '$deviceName Bağlı' : 'Bağlantı Yok',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          ...widget.appBarActions,
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Araç Ayarları',
            onPressed: isConnected ? () => _showVehicleSettings(context) : _showNotConnectedWarning(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Yön tuşlarını eldeki alana sığacak şekilde boyutlandır (en fazla 120 px):
              // solda iki tuş üst üste, sağda iki tuş yan yana; ortaya en az 200 px kalsın.
              final double buttonSize = math
                  .min((constraints.maxHeight - gap) / 2, (constraints.maxWidth - 200 - 3 * gap) / 3)
                  .clamp(48.0, 120.0);

              return Row(
                children: [
                  // SOL TARAF: İleri ve Geri Tuşları
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: buttonSize,
                        height: buttonSize,
                        child: DirectionButton(
                          icon: Icons.arrow_upward,
                          label: 'İleri',
                          command: 'F',
                          isEnabled: isConnected,
                          onCommandStart: _sendCommand(context),
                          onCommandEnd: _sendStopCommand('F'),
                        ),
                      ),
                      const SizedBox(height: gap),
                      SizedBox(
                        width: buttonSize,
                        height: buttonSize,
                        child: DirectionButton(
                          icon: Icons.arrow_downward,
                          label: 'Geri',
                          command: 'B',
                          isEnabled: isConnected,
                          onCommandStart: _sendCommand(context),
                          onCommandEnd: _sendStopCommand('B'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: gap),

                  // ORTA BÖLÜM: Acil Stop ve Ekstra Araç Komutları (yer yetmezse orantılı küçülür)
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ACİL STOP BUTONU
                            SizedBox(
                              width: 140,
                              height: 100,
                              child: DirectionButton(
                                icon: Icons.dangerous,
                                label: 'ACİL STOP',
                                command: 'S',
                                isStopButton: true,
                                isEnabled: isConnected,
                                onCommandStart: _sendCommand(context),
                                onCommandEnd: () {}, // Stop butonu için özel bitiş yok
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Diğer Aksiyon Butonları
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: ActionButton(
                                    icon: isLightOn ? Icons.highlight : Icons.lightbulb_outline,
                                    label: 'Far',
                                    isActive: isLightOn,
                                    activeColor: Colors.amber,
                                    onPressed: isConnected ? () => _bluetoothProvider.toggleLight() : _showNotConnectedWarning(context),
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: ActionButton(
                                    icon: Icons.skip_previous,
                                    label: 'Önceki',
                                    onPressed: isConnected ? () => _bluetoothProvider.sendCommand('V', description: 'Önceki Müzik') : _showNotConnectedWarning(context),
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: ActionButton(
                                    icon: isMusicPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                    label: isMusicPlaying ? 'Duraklat' : 'Oynat',
                                    isActive: isMusicPlaying,
                                    activeColor: Colors.blue,
                                    onPressed: isConnected ? () => _bluetoothProvider.toggleMusic() : _showNotConnectedWarning(context),
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: ActionButton(
                                    icon: Icons.skip_next,
                                    label: 'Sonraki',
                                    onPressed: isConnected ? () => _bluetoothProvider.sendCommand('N', description: 'Sonraki Müzik') : _showNotConnectedWarning(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: gap),

                  // SAĞ TARAF: Sol ve Sağ Tuşları
                  Row(
                    children: [
                      SizedBox(
                        width: buttonSize,
                        height: buttonSize,
                        child: DirectionButton(
                          icon: Icons.arrow_back,
                          label: 'Sol',
                          command: 'L',
                          isEnabled: isConnected,
                          onCommandStart: _sendCommand(context),
                          onCommandEnd: _sendStopCommand('L'),
                        ),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: buttonSize,
                        height: buttonSize,
                        child: DirectionButton(
                          icon: Icons.arrow_forward,
                          label: 'Sağ',
                          command: 'R',
                          isEnabled: isConnected,
                          onCommandStart: _sendCommand(context),
                          onCommandEnd: _sendStopCommand('R'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Function(String, String) _sendCommand(BuildContext context) {
    return (String command, String label) {
      if (!_bluetoothProvider.isConnected) {
        _showNotConnectedWarning(context)();
        return;
      }

      if (command == 'S') {
        _activeDirections.clear();
        _bluetoothProvider.sendCommand('S', description: 'ACİL STOP');
        return;
      }

      _activeDirections.add(command);
      _evaluateAndSendMovement(_bluetoothProvider);
    };
  }

  Function() _sendStopCommand(String command) {
    return () {
      // Bağlantı kopmuş olsa bile yönü listeden çıkar; yoksa yeniden bağlanınca eski yön takılı kalır.
      _activeDirections.remove(command);
      if (!_bluetoothProvider.isConnected) return;

      _evaluateAndSendMovement(_bluetoothProvider);
    };
  }

  void _evaluateAndSendMovement(BluetoothProvider provider) {
    String finalCommand = 'S';
    String label = 'Durdu';

    // Çapraz komutlar Arduino kodundaki (4wsArabaSon) standart eşlemeyle aynı:
    // G ileri sol, I ileri sağ, H geri sol, J geri sağ.
    if (_activeDirections.contains('F') && _activeDirections.contains('L')) {
      finalCommand = 'G';
      label = 'İleri Sol';
    } else if (_activeDirections.contains('F') && _activeDirections.contains('R')) {
      finalCommand = 'I';
      label = 'İleri Sağ';
    } else if (_activeDirections.contains('B') && _activeDirections.contains('L')) {
      finalCommand = 'H';
      label = 'Geri Sol';
    } else if (_activeDirections.contains('B') && _activeDirections.contains('R')) {
      finalCommand = 'J';
      label = 'Geri Sağ';
    } else if (_activeDirections.contains('F')) {
      finalCommand = 'F';
      label = 'İleri';
    } else if (_activeDirections.contains('B')) {
      finalCommand = 'B';
      label = 'Geri';
    } else if (_activeDirections.contains('L')) {
      finalCommand = 'L';
      label = 'Sol';
    } else if (_activeDirections.contains('R')) {
      finalCommand = 'R';
      label = 'Sağ';
    }

    provider.sendCommand(finalCommand, description: label);
  }

  Future<void> _showVehicleSettings(BuildContext context) async {
    final headlightPin = await showDialog<String>(
      context: context,
      builder: (context) => VehicleSettingsDialog(headlightPin: _bluetoothProvider.headlightPin),
    );
    if (headlightPin != null) {
      await _bluetoothProvider.setHeadlightPin(headlightPin);
    }
  }

  VoidCallback _showNotConnectedWarning(BuildContext context) {
    return () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bağlantı yok. Lütfen önce Bluetooth ile bağlanın.'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.red,
        ),
      );
    };
  }
}
