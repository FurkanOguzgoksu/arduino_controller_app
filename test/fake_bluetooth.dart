import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bluetooth eklentisinin (flutter_bluetooth_serial_plus) ve permission_handler'ın platform
/// kanallarını taklit eder; Arduino'ya giden komutları [writes] içinde toplar.
///
/// EventChannel'lar bilerek setMockStreamHandler ile taklit edilmiyor: testWidgets içinde
/// kullanılınca test kapanışı sonsuza kadar bekliyor. Olaylar doğrudan handlePlatformMessage
/// ile gönderiliyor.
class FakeBluetooth {
  FakeBluetooth({bool grantPermissions = true}) {
    _messenger.setMockMethodCallHandler(const MethodChannel('$_namespace/methods'), (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getState':
          return 12; // BluetoothState.STATE_ON
        case 'isEnabled':
          return true;
        case 'getBondedDevices':
          return [
            {'address': hc05Address, 'name': 'HC-05', 'type': 1, 'bondState': 12, 'isConnected': false},
          ];
        case 'connect':
          connectCalls++;
          final id = ++_lastConnectionId;
          _mockEventChannel('$_namespace/read/$id', (sink) => readSink = sink);
          return id;
        case 'write':
          writes.add(utf8.decode((call.arguments as Map)['bytes'] as List<int>));
          return null;
        default:
          return null; // startDiscovery, cancelDiscovery, requestEnable...
      }
    });
    _mockEventChannel('$_namespace/state');
    _mockEventChannel('$_namespace/discovery');

    // permission_handler durum kodları: 1 = granted, 4 = permanentlyDenied
    final status = grantPermissions ? 1 : 4;
    _messenger.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async {
      switch (call.method) {
        case 'requestPermissions':
          return {for (final permission in call.arguments as List) permission: status};
        case 'checkPermissionStatus':
          return status;
        default:
          return null;
      }
    });

    // SystemChrome.setPreferredOrientations vb.
    _messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

    // Araç başına kaydedilen ayarlar (far pini) için boş bir kayıt alanı
    SharedPreferences.setMockInitialValues({});
  }

  static const hc05Address = '98:D3:31:F5:12:34';
  static const _namespace = 'flutter_bluetooth_serial_plus';

  /// Arduino'ya gönderilen komutlar (gönderim sırasıyla).
  final List<String> writes = [];

  /// Eklentiye yapılan metot çağrıları.
  final List<String> calls = [];

  int connectCalls = 0;

  /// Açık bağlantının okuma kanalı: Arduino'dan veri ya da kopma sinyali göndermek için.
  FakeEventSink? readSink;

  int _lastConnectionId = 0;

  TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void _mockEventChannel(String name, [void Function(FakeEventSink sink)? onListen]) {
    _messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'listen') onListen?.call(FakeEventSink(name));
      return null;
    });
  }
}

class FakeEventSink {
  FakeEventSink(this.channel);

  final String channel;

  static const _codec = StandardMethodCodec();

  TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void success(Object? event) => _messenger.handlePlatformMessage(channel, _codec.encodeSuccessEnvelope(event), null);

  /// Native tarafın "bağlantı kapandı" sinyali (ör. HC-05'in gücü gitti).
  void endOfStream() => _messenger.handlePlatformMessage(channel, null, null);
}
