import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';

/// Bağlı aracın ayarları. Şimdilik yalnızca farın Arduino'da bağlı olduğu pin soruluyor;
/// kaydedilirse standart hale getirilmiş pini ("12", "A0"), vazgeçilirse null döndürür.
class VehicleSettingsDialog extends StatefulWidget {
  final String? headlightPin;

  const VehicleSettingsDialog({super.key, this.headlightPin});

  @override
  State<VehicleSettingsDialog> createState() => _VehicleSettingsDialogState();
}

class _VehicleSettingsDialogState extends State<VehicleSettingsDialog> {
  late final TextEditingController _pinController = TextEditingController(text: widget.headlightPin);
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _save() {
    final pin = BluetoothProvider.normalizeHeadlightPin(_pinController.text);
    if (pin == null) {
      setState(() => _errorText = 'Geçersiz pin. Örnek: 12 veya A0');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Yatay ekranda klavye açılınca içerik sığmazsa kaydırılabilsin
      scrollable: true,
      title: const Text('Araç Ayarları'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Farın Arduino\'da bağlı olduğu pin. Bu araç için kaydedilir ve her bağlantıda araca gönderilir.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Far pini',
              hintText: 'Örn. 12 veya A0',
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
