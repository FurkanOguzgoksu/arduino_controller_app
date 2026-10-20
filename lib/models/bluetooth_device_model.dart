import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

/// Bluetooth cihazı model sınıfı.
/// flutter_bluetooth_serial paketindeki BluetoothDevice nesnesini sarar.
class BluetoothDeviceModel {
  final BluetoothDevice device;
  final bool isConnected;

  BluetoothDeviceModel({
    required this.device,
    this.isConnected = false,
  });

  String get name => device.name ?? 'Bilinmeyen Cihaz';
  String get address => device.address;

  BluetoothDeviceModel copyWith({
    BluetoothDevice? device,
    bool? isConnected,
  }) {
    return BluetoothDeviceModel(
      device: device ?? this.device,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}
