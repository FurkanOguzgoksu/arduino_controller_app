import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/bluetooth_service.dart';
import '../models/bluetooth_device_model.dart';

class BluetoothScreen extends StatelessWidget {
  const BluetoothScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bluetoothProvider = Provider.of<BluetoothProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Cihazları'),
        actions: [
          Row(
            children: [
              Text(
                bluetoothProvider.bluetoothState == BluetoothState.STATE_ON ? 'AÇIK' : 'KAPALI',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Switch(
                value: bluetoothProvider.bluetoothState == BluetoothState.STATE_ON,
                onChanged: (bool value) async {
                  if (value) {
                    await bluetoothProvider.requestEnable();
                  } else if (!await bluetoothProvider.requestDisable()) {
                    // Android 13+ uygulamaların Bluetooth'u kapatmasına izin vermiyor;
                    // kullanıcıyı kapatabileceği sistem ayarlarına götür.
                    await bluetoothProvider.openBluetoothSettings();
                  }
                },
              ),
            ],
          ),
          IconButton(
            icon: bluetoothProvider.isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)
                  )
                : const Icon(Icons.refresh),
            onPressed: bluetoothProvider.isScanning
                ? null
                : () {
                    if (bluetoothProvider.bluetoothState == BluetoothState.STATE_ON) {
                      bluetoothProvider.getPairedDevices();
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // Durum Kartı
          Container(
            padding: const EdgeInsets.all(16),
            color: bluetoothProvider.isConnected
                ? Colors.green.withValues(alpha: 0.2)
                : (bluetoothProvider.bluetoothState == BluetoothState.STATE_ON
                    ? colorScheme.surfaceContainerHighest
                    : Colors.red.withValues(alpha: 0.2)),
            child: Row(
              children: [
                Icon(
                  bluetoothProvider.isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: bluetoothProvider.isConnected ? Colors.green : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bağlantı Durumu',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                      Text(
                        _getStatusText(bluetoothProvider),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (bluetoothProvider.isConnected)
                  ElevatedButton(
                    onPressed: () => bluetoothProvider.disconnect(),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
                    child: const Text('Kes', style: TextStyle(color: Colors.white)),
                  ),
              ],
            ),
          ),

          // Uyarı: Bluetooth Kapalıysa
          if (bluetoothProvider.bluetoothState != BluetoothState.STATE_ON)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('Lütfen Bluetooth\'u açın.'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => bluetoothProvider.requestEnable(),
                      child: const Text('Bluetooth Ayarlarını Aç'),
                    ),
                  ],
                ),
              ),
            )
          // Uyarı: İzin verilmediyse cihazlar listelenemez
          else if (!bluetoothProvider.permissionsGranted)
            Expanded(child: _buildPermissionRequest(bluetoothProvider))
          else
            // Cihaz Listesi
            Expanded(
              child: bluetoothProvider.devices.isEmpty && !bluetoothProvider.isScanning
                  ? const Center(child: Text('Cihaz bulunamadı.\nTarama için yenile tuşuna basın.', textAlign: TextAlign.center))
                  : _buildDeviceLists(bluetoothProvider, context),
            ),
        ],
      ),
    );
  }

  Widget _buildPermissionRequest(BluetoothProvider provider) {
    // Kalıcı olarak reddedildiyse Android artık soru sormuyor; izin ayarlardan verilmeli.
    final openSettings = provider.permissionsPermanentlyDenied;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Cihazları bulup bağlanabilmek için "Yakındaki cihazlar" iznini vermelisiniz.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: openSettings ? () => openAppSettings() : () => provider.getPairedDevices(),
              child: Text(openSettings ? 'Uygulama Ayarlarını Aç' : 'İzin Ver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceLists(BluetoothProvider provider, BuildContext context) {
    final bondedDevices = provider.devices.where((d) => d.device.isBonded).toList();
    final newDevices = provider.devices.where((d) => !d.device.isBonded).toList();

    return ListView(
      children: [
        if (bondedDevices.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Kayıtlı Cihazlar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          ...bondedDevices.map((d) => _buildDeviceTile(d, provider, context)),
        ],
        if (newDevices.isNotEmpty || provider.isScanning) ...[
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Yeni Cihazlar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          ...newDevices.map((d) => _buildDeviceTile(d, provider, context)),
          if (provider.isScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )
        ],
      ],
    );
  }

  Widget _buildDeviceTile(BluetoothDeviceModel device, BluetoothProvider provider, BuildContext context) {
    final isThisConnected = provider.connectedDevice?.address == device.address;

    return ListTile(
      leading: const Icon(Icons.memory),
      title: Text(device.name),
      subtitle: Text(device.address),
      trailing: isThisConnected
          ? const Icon(Icons.check_circle, color: Colors.green)
          : (provider.isConnecting
              ? const CircularProgressIndicator()
              : const Icon(Icons.chevron_right)),
      onTap: () async {
        if (!provider.isConnecting && !isThisConnected) {
          bool success = await provider.connect(device);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success
                      ? "${device.name} cihazına başarıyla bağlandı."
                      : "${device.name} cihazına bağlanılamadı!",
                ),
                backgroundColor: success ? Colors.green.shade800 : Colors.red.shade800,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      },
    );
  }

  String _getStatusText(BluetoothProvider provider) {
    if (provider.bluetoothState != BluetoothState.STATE_ON) return 'Bluetooth Kapalı';
    if (provider.isConnecting) return 'Bağlanıyor...';
    if (provider.isConnected) return '${provider.connectedDevice?.name} Bağlandı';
    return 'Bağlı Değil';
  }
}
