/// Seri terminal kayıtlarının tipini belirten enum.
enum LogType {
  /// Uygulamadan Arduino'ya gönderilen (Transmit)
  tx,
  /// Arduino'dan uygulamaya gelen (Receive)
  rx,
  /// Sistem mesajları (Bağlantı durumu vb.)
  system,
}

/// Seri haberleşme log modeli.
class SerialLogModel {
  final DateTime timestamp;
  final String message;
  final LogType type;

  SerialLogModel({
    required this.timestamp,
    required this.message,
    required this.type,
  });
}
