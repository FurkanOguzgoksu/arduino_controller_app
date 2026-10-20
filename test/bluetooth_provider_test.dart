import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arduino_controller_app/models/bluetooth_device_model.dart';
import 'package:arduino_controller_app/models/serial_log_model.dart';
import 'package:arduino_controller_app/services/bluetooth_service.dart';

import 'fake_bluetooth.dart';

final hc05 = BluetoothDeviceModel(
  device: const BluetoothDevice(name: 'HC-05', address: FakeBluetooth.hc05Address),
);

// Eklenti bağlantı kapanışını ~111 ms aralıklı bir döngüyle bekliyor; gerçek zamanla bekleniyor.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disconnect() bağlantıyı kapatmadan önce aracı durdurmak için S gönderir', () async {
    final bt = FakeBluetooth();
    final provider = BluetoothProvider();
    addTearDown(provider.dispose);
    await settle();
    await provider.connect(hc05);

    await provider.disconnect();

    expect(bt.writes, ['S']);
    expect(provider.isConnected, isFalse);
    expect(provider.connectedDevice, isNull);
  });

  test('Arduino tarafı koparsa bağlantı temizlenir ve aynı cihaza yeniden bağlanılabilir', () async {
    final bt = FakeBluetooth();
    final provider = BluetoothProvider();
    addTearDown(provider.dispose);
    await settle();
    await provider.connect(hc05);
    var notified = false;
    provider.addListener(() => notified = true);

    bt.readSink!.endOfStream(); // HC-05'in gücü gitti
    await settle();

    expect(notified, isTrue);
    expect(provider.isConnected, isFalse);
    expect(provider.connectedDevice, isNull);
    expect(provider.logs.last.message, contains('aniden kesildi'));

    expect(await provider.connect(hc05), isTrue);
    expect(bt.connectCalls, 2);
    bt.readSink!.endOfStream();
    await settle();
  });

  test('iki Bluetooth paketine bölünen Türkçe karakterli satır kaybolmaz', () async {
    final bt = FakeBluetooth();
    final provider = BluetoothProvider();
    addTearDown(provider.dispose);
    await settle();
    await provider.connect(hc05);

    final bytes = utf8.encode('Işık açık\r\n');
    bt.readSink!.success(Uint8List.fromList(bytes.sublist(0, 2))); // "I" + "ş"nin ilk baytı
    bt.readSink!.success(Uint8List.fromList(bytes.sublist(2)));
    bt.readSink!.success(Uint8List.fromList(utf8.encode('Mesafe: 25\n')));
    await settle();

    final received = provider.logs.where((log) => log.type == LogType.rx).map((log) => log.message);
    expect(received, ['Işık açık', 'Mesafe: 25']);
    bt.readSink!.endOfStream();
    await settle();
  });

  test('duraklatılan müzik baştan değil kaldığı yerden devam eder', () async {
    final bt = FakeBluetooth();
    final provider = BluetoothProvider();
    addTearDown(provider.dispose);
    await settle();
    await provider.connect(hc05);

    provider.toggleMusic(); // Oynat
    provider.toggleMusic(); // Duraklat
    provider.toggleMusic(); // Oynat
    await settle();

    expect(bt.writes, ['P', 'O', 'C']);
    bt.readSink!.endOfStream();
    await settle();
  });

  test('far pini araç için kaydedilir ve her bağlantıda Arduino\'ya gönderilir', () async {
    final bt = FakeBluetooth();
    final provider = BluetoothProvider();
    addTearDown(provider.dispose);
    await settle();
    await provider.connect(hc05);
    expect(bt.writes, isEmpty, reason: 'Far pini henüz ayarlanmadı');

    await provider.setHeadlightPin('A0');
    expect(bt.writes, ['#A0\n']);

    await provider.disconnect();
    bt.writes.clear();
    await provider.connect(hc05);
    expect(provider.headlightPin, 'A0');
    expect(bt.writes, ['#A0\n']);

    // Başka bir aracın (projenin) far pini ayrı tutulur
    await provider.disconnect();
    bt.writes.clear();
    await provider.connect(BluetoothDeviceModel(
      device: const BluetoothDevice(name: 'HC-06', address: '00:21:13:00:AA:BB'),
    ));
    expect(provider.headlightPin, isNull);
    expect(bt.writes, isEmpty);

    bt.readSink!.endOfStream();
    await settle();
  });

  test('far pini yalnızca "12" veya "A0" biçiminde kabul edilir', () {
    expect(BluetoothProvider.normalizeHeadlightPin('12'), '12');
    expect(BluetoothProvider.normalizeHeadlightPin(' a3 '), 'A3');
    expect(BluetoothProvider.normalizeHeadlightPin('07'), '7');
    expect(BluetoothProvider.normalizeHeadlightPin('1'), isNull); // Bluetooth seri pini
    expect(BluetoothProvider.normalizeHeadlightPin('D5'), isNull);
    expect(BluetoothProvider.normalizeHeadlightPin('123'), isNull);
    expect(BluetoothProvider.normalizeHeadlightPin(''), isNull);
  });

  test('izin yoksa eklenti çağrılmaz ve tarama göstergesi takılı kalmaz', () async {
    final bt = FakeBluetooth(grantPermissions: false);
    final provider = BluetoothProvider();
    addTearDown(provider.dispose);
    await settle();

    expect(provider.permissionsGranted, isFalse);
    expect(provider.isScanning, isFalse);
    expect(bt.calls, isNot(contains('getBondedDevices')));
    expect(bt.calls, isNot(contains('startDiscovery')));
  });

  testWidgets('araç hareket ederken bağlantı sinyali gönderilir, durunca kesilir', (tester) async {
    final bt = FakeBluetooth();
    final provider = BluetoothProvider();
    addTearDown(provider.dispose);
    await tester.pump();
    provider.connect(hc05);
    await tester.pump();
    bt.writes.clear();

    provider.sendCommand('F');
    await tester.pump(const Duration(seconds: 1));
    expect(bt.writes.first, 'F');
    expect(bt.writes.skip(1), everyElement('.'));
    expect(bt.writes.length, greaterThanOrEqualTo(4)); // 300 ms'de bir sinyal

    provider.sendCommand('S');
    await tester.pump();
    bt.writes.clear();
    await tester.pump(const Duration(seconds: 1));
    expect(bt.writes, isEmpty);

    bt.readSink!.endOfStream();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tarama hiç bitmezse süre sınırında durdurulur', (tester) async {
    FakeBluetooth();
    final provider = BluetoothProvider();
    addTearDown(provider.dispose);
    await tester.pump();
    expect(provider.isScanning, isTrue);

    await tester.pump(const Duration(seconds: 16));
    expect(provider.isScanning, isFalse);
  });
}
