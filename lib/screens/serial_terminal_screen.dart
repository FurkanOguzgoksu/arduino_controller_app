import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_service.dart';
import '../models/serial_log_model.dart';
import '../widgets/serial_log_item.dart';

class SerialTerminalScreen extends StatefulWidget {
  const SerialTerminalScreen({super.key});

  @override
  State<SerialTerminalScreen> createState() => _SerialTerminalScreenState();
}

class _SerialTerminalScreenState extends State<SerialTerminalScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _autoScroll = true;
  bool _appendNewline = true;
  
  // 0: Hepsi, 1: Sadece TX, 2: Sadece RX
  int _filterIndex = 0;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    // Filtreleme
    final filteredLogs = provider.logs.where((log) {
      if (_filterIndex == 1) return log.type == LogType.tx || log.type == LogType.system;
      if (_filterIndex == 2) return log.type == LogType.rx || log.type == LogType.system;
      return true;
    }).toList();

    // Yeni mesaj geldiğinde kaydırma (Consumer builder tetiklendiğinde)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seri Terminal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Kayıtları Temizle',
            onPressed: () => provider.clearLogs(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Araç çubuğu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            color: colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Tümü')),
                      ButtonSegment(value: 1, label: Text('TX')),
                      ButtonSegment(value: 2, label: Text('RX')),
                    ],
                    selected: {_filterIndex},
                    onSelectionChanged: (Set<int> selection) {
                      setState(() {
                        _filterIndex = selection.first;
                        _scrollToBottom();
                      });
                    },
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Oto Kaydır', style: TextStyle(fontSize: 10)),
                    Switch(
                      value: _autoScroll,
                      onChanged: (val) {
                        setState(() => _autoScroll = val);
                        if (val) _scrollToBottom();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Log Listesi
          Expanded(
            child: Container(
              color: Colors.black87,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: filteredLogs.length,
                itemBuilder: (context, index) {
                  final log = filteredLogs[index];
                  return GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: log.message));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Metin kopyalandı')),
                      );
                    },
                    child: SerialLogItem(log: log),
                  );
                },
              ),
            ),
          ),

          // Manuel Gönderim Alanı
          Container(
            padding: const EdgeInsets.all(8.0),
            color: colorScheme.surface,
            child: Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('\\n', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    Checkbox(
                      value: _appendNewline,
                      onChanged: (val) {
                        setState(() => _appendNewline = val ?? true);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Manuel komut gönder...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    enabled: provider.isConnected,
                    onSubmitted: (value) => _sendManualCommand(provider),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: provider.isConnected ? () => _sendManualCommand(provider) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendManualCommand(BluetoothProvider provider) {
    final text = _textController.text;
    if (text.isEmpty) return;

    provider.sendCommand(text, description: 'Manuel', addNewline: _appendNewline);
    _textController.clear();
  }
}
