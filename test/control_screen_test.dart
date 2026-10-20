import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:arduino_controller_app/main.dart';
import 'package:arduino_controller_app/models/bluetooth_device_model.dart';
import 'package:arduino_controller_app/services/bluetooth_service.dart';
import 'package:arduino_controller_app/widgets/action_button.dart';
import 'package:arduino_controller_app/widgets/direction_button.dart';
import 'package:arduino_controller_app/widgets/vehicle_settings_dialog.dart';

import 'fake_bluetooth.dart';

Finder directionButton(String label) => find.ancestor(of: find.text(label), matching: find.byType(DirectionButton));
Finder actionButton(String label) => find.ancestor(of: find.text(label), matching: find.byType(ActionButton));

/// Uygulamayı verilen ekran boyutunda kontrol ekranıyla açar ve HC-05'e bağlanır.
Future<FakeBluetooth> pumpConnectedApp(
  WidgetTester tester,
  Size size, {
  FakeViewPadding padding = FakeViewPadding.zero,
}) async {
  final bt = FakeBluetooth();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const ArduinoControllerApp(isFirstTime: false));
  await tester.pump();
  final provider = Provider.of<BluetoothProvider>(tester.element(find.byType(MainScreen)), listen: false);
  provider.connect(BluetoothDeviceModel(
    device: const BluetoothDevice(name: 'HC-05', address: FakeBluetooth.hc05Address),
  ));
  await tester.pump();
  await tester.pump();
  expect(provider.isConnected, isTrue);
  bt.writes.clear();
  return bt;
}

/// Bağlantıyı kapatır; eklentinin bağlantı döngüsü test sonunda bekleyen zamanlayıcı bırakmasın.
Future<void> closeConnection(WidgetTester tester, FakeBluetooth bt) async {
  bt.readSink!.endOfStream();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('yön tuşu basılıyken parmak kayınca tuş bırakılmış sayılmaz', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 120,
          height: 120,
          child: DirectionButton(
            icon: Icons.arrow_upward,
            label: 'İleri',
            command: 'F',
            onCommandStart: (command, label) => events.add('başla'),
            onCommandEnd: () => events.add('bitir'),
          ),
        ),
      ),
    ));

    final gesture = await tester.startGesture(tester.getCenter(find.byType(DirectionButton)));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(events, ['başla']);

    await gesture.up();
    await tester.pump();
    expect(events, ['başla', 'bitir']);
  });

  const screens = {
    '915x412 (hareketli gezinme)': (Size(915, 412), FakeViewPadding(top: 24, bottom: 24)),
    '800x360 (sağda 3 tuşlu gezinme)': (Size(800, 360), FakeViewPadding(top: 24, right: 48)),
    '640x360 (küçük telefon)': (Size(640, 360), FakeViewPadding(top: 24, right: 48)),
  };
  for (final MapEntry(key: name, value: (size, padding)) in screens.entries) {
    testWidgets('kontrol ekranı yatayda $name taşmaz ve butonlar çakışmaz', (tester) async {
      final bt = await pumpConnectedApp(tester, size, padding: padding);

      // Bir RenderFlex taşsaydı test çerçevesi hatayı burada yakalamış olurdu.
      expect(tester.takeException(), isNull);

      // Kontrol ekranında alt menü yok; butonlar ekranın görünen alanında kalmalı.
      expect(find.byType(NavigationBar), findsNothing);
      final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
      final screenBottom = size.height - padding.bottom;
      final buttons = {
        for (final label in ['İleri', 'Geri', 'Sol', 'Sağ', 'ACİL STOP']) label: tester.getRect(directionButton(label)),
        for (final label in ['Far', 'Önceki', 'Oynat', 'Sonraki']) label: tester.getRect(actionButton(label)),
      };
      for (final MapEntry(key: label, value: rect) in buttons.entries) {
        expect(rect.top, greaterThanOrEqualTo(appBarBottom), reason: '$label üst menünün altında kalıyor');
        expect(rect.bottom, lessThanOrEqualTo(screenBottom), reason: '$label ekranın altına taşıyor');
        for (final MapEntry(key: other, value: otherRect) in buttons.entries) {
          if (other != label) {
            expect(rect.overlaps(otherRect), isFalse, reason: '$label ile $other çakışıyor');
          }
        }
      }

      // Yön tuşları rahat basılacak kadar büyük kalmalı.
      expect(tester.getSize(directionButton('İleri')).width, greaterThanOrEqualTo(96));

      await tester.tap(actionButton('Sonraki'));
      await tester.pump();
      expect(bt.writes, ['N']);

      await closeConnection(tester, bt);
    });
  }

  testWidgets('çapraz hareketler Arduino koduyla aynı komutları gönderir', (tester) async {
    final bt = await pumpConnectedApp(tester, const Size(915, 412));

    final ileri = await tester.startGesture(tester.getCenter(directionButton('İleri')));
    final sag = await tester.startGesture(tester.getCenter(directionButton('Sağ')));
    await tester.pump();
    await sag.up();
    await ileri.up();
    await tester.pump();

    final geri = await tester.startGesture(tester.getCenter(directionButton('Geri')));
    final sol = await tester.startGesture(tester.getCenter(directionButton('Sol')));
    await tester.pump();
    await sol.up();
    await geri.up();
    await tester.pump();

    // '.' bağlantı sinyalleri hariç: ileri, ileri sağ (I), ileri, dur, geri, geri sol (H), geri, dur
    expect(bt.writes.where((command) => command != '.'), ['F', 'I', 'F', 'S', 'B', 'H', 'B', 'S']);

    await closeConnection(tester, bt);
  });

  testWidgets('far pini araç ayarlarından değiştirilip araca gönderilir', (tester) async {
    final bt = await pumpConnectedApp(tester, const Size(915, 412));

    await tester.tap(find.byTooltip('Araç Ayarları'));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    expect(find.text('Geçersiz pin. Örnek: 12 veya A0'), findsOneWidget);
    expect(bt.writes, isEmpty);

    await tester.enterText(find.byType(TextField), '13');
    await tester.tap(find.text('Kaydet'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(VehicleSettingsDialog), findsNothing);
    expect(bt.writes, ['#13\n']);

    await closeConnection(tester, bt);
  });

  testWidgets('ACİL STOP her dokunuşta tek bir S gönderir', (tester) async {
    final bt = await pumpConnectedApp(tester, const Size(915, 412));

    await tester.tap(directionButton('ACİL STOP'));
    await tester.pump();
    expect(bt.writes, ['S']);

    await closeConnection(tester, bt);
  });

  testWidgets('yön tuşu basılıyken sekme değişirse araç durdurulur', (tester) async {
    final bt = await pumpConnectedApp(tester, const Size(915, 412));

    final gesture = await tester.startGesture(tester.getCenter(directionButton('İleri')));
    await tester.pump();
    await tester.tap(find.byTooltip('Bağlantı'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(bt.writes, ['F', 'S']);

    await gesture.up();
    await tester.pump();
    await closeConnection(tester, bt);
  });
}
