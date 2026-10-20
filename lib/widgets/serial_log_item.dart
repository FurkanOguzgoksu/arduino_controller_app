import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/serial_log_model.dart';

class SerialLogItem extends StatelessWidget {
  final SerialLogModel log;

  const SerialLogItem({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm:ss').format(log.timestamp);
    
    IconData icon;
    Color color;
    String prefix;

    switch (log.type) {
      case LogType.tx:
        icon = Icons.upload_rounded;
        color = Colors.blue;
        prefix = 'TX >';
        break;
      case LogType.rx:
        icon = Icons.download_rounded;
        color = Colors.green;
        prefix = 'RX <';
        break;
      case LogType.system:
        icon = Icons.info_outline_rounded;
        color = Colors.orange;
        prefix = 'SYSTEM -';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white70,
                ),
                children: [
                  TextSpan(
                    text: '[$timeStr] ',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  TextSpan(
                    text: '$prefix ',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: log.message,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
