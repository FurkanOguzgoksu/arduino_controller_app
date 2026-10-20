import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bluetooth_device_model.dart';
import '../models/serial_log_model.dart';

class BluetoothProvider extends ChangeNotifier with WidgetsBindingObserver {
  // Bluetooth durumu
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothState get bluetoothState => _bluetoothState;

  // İzinler (Android 12+ "Yakındaki cihazlar": tarama + bağlanma)
  bool _permissionsGranted = true;
  bool get permissionsGranted => _permissionsGranted;

  bool _permissionsPermanentlyDenied = false;
  bool get permissionsPermanentlyDenied => _permissionsPermanentlyDenied;

  // Cihaz listesi ve Bağlantı
  List<BluetoothDeviceModel> _devices = [];
  List<BluetoothDeviceModel> get devices => _devices;

  BluetoothConnection? _connection;
  BluetoothDeviceModel? _connectedDevice;
  BluetoothDeviceModel? get connectedDevice => _connectedDevice;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  StreamSubscription<BluetoothDiscoveryResult>? _discoveryStreamSubscription;
  StreamSubscription<BluetoothState>? _stateSubscription;

  // Android taramayı başlatmayı reddederse (ör. konum kapalı) "tarama bitti" olayı hiç
  // gelmiyor; tarama en fazla bu kadar sürsün.
  static const Duration _discoveryTimeout = Duration(seconds: 15);
  Timer? _discoveryTimer;

  // Araç hareket ederken Arduino'ya düzenli aralıklarla '.' gönderilir; Arduino bu sinyal
  // kesilirse (bağlantı koptu, telefon uzaklaştı) aracı kendiliğinden durdurur.
  // '.' Arduino kodunda komut olarak işlenmez.
  static const String _keepAliveSignal = '.';
  static const Duration _keepAliveInterval = Duration(milliseconds: 300);
  static const Set<String> _movementCommands = {'F', 'B', 'L', 'R', 'G', 'H', 'I', 'J'};
  Timer? _keepAliveTimer;

  bool get isConnected => _connection != null && _connection!.isConnected;

  // Kontrol Durumları
  bool _isLightOn = false;
  bool get isLightOn => _isLightOn;

  // Far pini projeden projeye değiştiği için her araç (Bluetooth adresi) için ayrı saklanır
  // ve bağlanınca Arduino'ya "#12" / "#A0" satırı olarak gönderilir.
  String? _headlightPin;
  String? get headlightPin => _headlightPin;

  bool _isMusicPlaying = false;
  bool get isMusicPlaying => _isMusicPlaying;

  // Arduino'da 'P' müziği her seferinde ilk şarkının başından başlatıyor; müzik bir kez
  // başladıysa duraklatıldıktan sonra 'C' ile kaldığı yerden devam ettirilir.
  bool _hasStartedMusic = false;

  // Terminal Kayıtları
  final List<SerialLogModel> _logs = [];
  List<SerialLogModel> get logs => List.unmodifiable(_logs);
  final int _maxLogCount = 500;

  bool _isDisposed = false;

  BluetoothProvider() {
    WidgetsBinding.instance.addObserver(this);
    _initBluetooth();
  }

  void _initBluetooth() {
    FlutterBluetoothSerial.instance.state.then((state) {
      _bluetoothState = state;
      notifyListeners();
      if (_bluetoothState == BluetoothState.STATE_ON) {
        getPairedDevices(requestPermissions: false);
      }
    }).catchError((Object e) {
      debugPrint('Bluetooth durumu alınamadı: $e');
    });

    _stateSubscription = FlutterBluetoothSerial.instance.onStateChanged().listen((BluetoothState state) {
      _bluetoothState = state;
      if (_bluetoothState == BluetoothState.STATE_OFF) {
        _addSystemLog('Bluetooth kapatıldı.');
        _stopDiscovery();
        final connection = _connection;
        if (connection != null) {
          _handleConnectionLost(connection);
        }
      } else if (_bluetoothState == BluetoothState.STATE_ON) {
        getPairedDevices(requestPermissions: false);
      }
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('Bluetooth durumu dinlenemedi: $e');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kullanıcı izni sistem ayarlarından verip geri döndüyse listeyi kendiliğinden yenile.
    if (state == AppLifecycleState.resumed &&
        !_permissionsGranted &&
        _bluetoothState == BluetoothState.STATE_ON) {
      getPairedDevices(requestPermissions: false);
    }
  }

  /// Android 12+ "Yakındaki cihazlar" izinlerini kontrol eder; [request] true ise kullanıcıya
  /// sorar. Eski Android sürümlerinde bu izinler verilmiş sayılır; orada gereken konum
  /// iznini eklenti kendisi istiyor.
  ///
  /// Eklenti bu izinler olmadan çağrılmamalı: Android 12+'da kendi izin isteğinin sonucunu
  /// yanlış istek koduyla bekliyor ve çağrı hiç cevap dönmeden takılı kalıyor.
  Future<bool> _ensurePermissions({bool request = true}) async {
    final permissions = [Permission.bluetoothScan, Permission.bluetoothConnect];
    try {
      final statuses = request
          ? (await permissions.request()).values
          : await Future.wait(permissions.map((permission) => permission.status));
      _permissionsGranted = statuses.every((status) => status.isGranted);
      _permissionsPermanentlyDenied = statuses.any((status) => status.isPermanentlyDenied);
    } catch (e) {
      debugPrint('İzinler kontrol edilemedi: $e');
      _permissionsGranted = false;
    }
    notifyListeners();
    return _permissionsGranted;
  }

  Future<void> getPairedDevices({bool requestPermissions = true}) async {
    if (_isScanning) return;

    _isScanning = true;
    notifyListeners();

    if (!await _ensurePermissions(request: requestPermissions)) {
      _isScanning = false;
      notifyListeners();
      return;
    }

    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance
          .getBondedDevices()
          .timeout(const Duration(seconds: 10));
      _devices = bondedDevices.map((d) => BluetoothDeviceModel(device: d)).toList();
      notifyListeners();

      // Bu arada bir cihaza bağlanılmaya başlandıysa tarama iptal edilmiştir; yeniden başlatma.
      if (!_isScanning) return;

      _discoveryStreamSubscription?.cancel();
      _discoveryStreamSubscription = FlutterBluetoothSerial.instance.startDiscovery().listen(
        _onDeviceDiscovered,
        onError: (Object e) {
          _addSystemLog('Cihaz taraması başarısız: $e');
          _stopDiscovery();
        },
        onDone: _stopDiscovery,
      );
      _discoveryTimer?.cancel();
      _discoveryTimer = Timer(_discoveryTimeout, _stopDiscovery);
    } catch (e) {
      _addSystemLog('Cihazlar alınamadı: $e');
      _isScanning = false;
      notifyListeners();
    }
  }

  void _onDeviceDiscovered(BluetoothDiscoveryResult r) {
    final existingIndex = _devices.indexWhere((element) => element.address == r.device.address);
    if (existingIndex >= 0) {
      final existingName = _devices[existingIndex].device.name;
      if (r.device.name != null || existingName == null) {
        _devices[existingIndex] = BluetoothDeviceModel(device: r.device);
      }
    } else {
      _devices.add(BluetoothDeviceModel(device: r.device));
    }
    notifyListeners();
  }

  /// Taramayı bitirir. Aboneliği iptal etmek eklenti tarafında da taramayı durdurur.
  void _stopDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _discoveryStreamSubscription?.cancel();
    _discoveryStreamSubscription = null;
    if (_isScanning) {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<bool> connect(BluetoothDeviceModel deviceModel) async {
    if (_connection != null) {
      await disconnect();
    }

    // Tarama sürerken bağlanmak hem yavaş hem de sık başarısız oluyor.
    _stopDiscovery();

    _isConnecting = true;
    notifyListeners();

    try {
      final connection = await BluetoothConnection.toAddress(deviceModel.address);
      _connection = connection;
      _connectedDevice = deviceModel;
      _isConnecting = false;

      _addSystemLog('${deviceModel.name} cihazına bağlanıldı.');
      notifyListeners();

      // Baytlar satırlara bölünmeden önce akış halinde çözülüyor: çok baytlı bir karakter
      // (ş, ğ, ı...) iki Bluetooth paketine bölünse bile kaybolmaz.
      connection.input
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            _onLineReceived,
            onError: (Object e) {
              debugPrint('Veri okuma hatası: $e');
            },
            onDone: () => _handleConnectionLost(connection),
          );
      await _loadHeadlightPin(deviceModel);
      return true;
    } catch (e) {
      _isConnecting = false;
      _addSystemLog('Bağlantı hatası: ${deviceModel.name}');
      notifyListeners();
      return false;
    }
  }

  /// Bağlantı kullanıcı istemeden koptuğunda (Arduino kapandı, menzil dışı, Bluetooth
  /// kapandı) durumu temizler. Kullanıcı kestiğinde disconnect() _connection'ı önceden null
  /// yaptığı için burası ikinci kez çalışmaz.
  ///
  /// Eklenti isConnected'ı bu noktadan önce false yaptığı için isConnected'a değil, bağlantı
  /// nesnesine bakılıyor.
  void _handleConnectionLost(BluetoothConnection connection) {
    if (_connection != connection) return;

    final deviceName = _connectedDevice?.name;
    _clearConnection();
    connection.close().catchError((Object e) {
      debugPrint('Bağlantı kapatılırken hata: $e');
    });
    _addSystemLog('Bağlantı aniden kesildi: $deviceName');
  }

  Future<void> disconnect() async {
    final connection = _connection;
    if (connection == null) return;

    // Güvenlik için önce aracı durdur (S komutu) ve komutun gerçekten gitmesini bekle:
    // eklenti yazmayı erteliyor, hemen close() çağrılırsa komut hiç gönderilmiyor.
    if (connection.isConnected) {
      await sendCommand('S', description: 'Bağlantı kesiliyor - Dur');
    }
    if (_connection != connection) return; // Beklerken bağlantı zaten koptu

    final deviceName = _connectedDevice?.name;
    _clearConnection();
    notifyListeners();

    try {
      await connection.close();
    } catch (e) {
      debugPrint('Bağlantı kesilirken hata: $e');
    }
    _addSystemLog('Bağlantı kesildi: $deviceName');
  }

  void _clearConnection() {
    _connection = null;
    _connectedDevice = null;
    _headlightPin = null;
    _stopKeepAlive();
  }

  /// Bağlanılan aracın kayıtlı far pinini yükler ve Arduino'ya gönderir.
  Future<void> _loadHeadlightPin(BluetoothDeviceModel device) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _headlightPin = prefs.getString(_headlightPinKey(device.address));
    } catch (e) {
      debugPrint('Far pini okunamadı: $e');
      _headlightPin = null;
    }
    notifyListeners();

    final pin = _headlightPin;
    if (pin != null) {
      await _sendHeadlightPin(pin);
    }
  }

  /// Bağlı aracın far pinini kaydeder ve Arduino'ya gönderir.
  Future<void> setHeadlightPin(String pin) async {
    final device = _connectedDevice;
    if (device == null) return;

    _headlightPin = pin;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_headlightPinKey(device.address), pin);
    } catch (e) {
      debugPrint('Far pini kaydedilemedi: $e');
    }
    await _sendHeadlightPin(pin);
  }

  // Yalnızca '#', rakam ve 'A' içeriyor: bu ayarı bilmeyen eski Arduino kodları bu
  // karakterleri yok sayıyor ('F', 'R' gibi harfler aracı hareket ettirirdi).
  Future<void> _sendHeadlightPin(String pin) =>
      sendCommand('#$pin', description: 'Far pini', addNewline: true);

  static String _headlightPinKey(String address) => 'headlightPin_$address';

  /// "12" ya da "A0" biçimindeki pin yazısını doğrular ve "A0" gibi standart hale getirir;
  /// geçersizse null döner. 0 ve 1, Bluetooth modülünün bağlı olduğu seri haberleşme pinleri.
  /// Pinin o projede boşta olup olmadığını Arduino kontrol eder.
  static String? normalizeHeadlightPin(String input) {
    final match = RegExp(r'^(A?)(\d{1,2})$').firstMatch(input.trim().toUpperCase());
    if (match == null) return null;

    final prefix = match.group(1)!;
    final number = int.parse(match.group(2)!);
    if (prefix.isEmpty && number < 2) return null;
    return '$prefix$number';
  }

  void _onLineReceived(String line) {
    final message = line.trim();
    if (message.isNotEmpty) {
      _addLog(message, LogType.rx);
    }
  }

  /// Komutu gönderir; komut gerçekten gönderildikten sonra terminale TX kaydı düşer.
  Future<void> sendCommand(String command, {String? description, bool addNewline = false}) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;

    try {
      String finalCommand = addNewline ? '$command\n' : command;
      connection.output.add(utf8.encode(finalCommand));
      _updateKeepAlive(command);
      await connection.output.allSent;
      String logMessage = description != null ? '$command - $description' : command;
      _addLog(logMessage, LogType.tx);
    } catch (e) {
      _addSystemLog('Komut gönderme hatası: $e');
      // Yazma hatası eklentinin çıkış kanalını kapatır; okuma tarafı açık kalsa bile
      // bağlantıyı kopmuş say ki cihaz "bağlı" görünüp yeniden bağlanmayı engellemesin.
      if (!connection.isConnected) _handleConnectionLost(connection);
    }
  }

  /// Hareket komutundan sonra bağlantı sinyalini başlatır, dur komutundan sonra keser.
  void _updateKeepAlive(String command) {
    if (_movementCommands.contains(command)) {
      _keepAliveTimer ??= Timer.periodic(_keepAliveInterval, (_) => _sendKeepAlive());
    } else if (command == 'S') {
      _stopKeepAlive();
    }
  }

  void _sendKeepAlive() {
    final connection = _connection;
    if (connection == null || !connection.isConnected) {
      _stopKeepAlive();
      return;
    }
    // Terminale yazılmıyor; yoksa her 300 ms'de bir kayıt düşerdi.
    connection.output.add(utf8.encode(_keepAliveSignal));
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Bluetooth'u açmayı ister (Android 12+'da bunun için de "Yakındaki cihazlar" izni gerekir).
  Future<void> requestEnable() async {
    if (!await _ensurePermissions()) return;
    try {
      await FlutterBluetoothSerial.instance.requestEnable();
    } catch (e) {
      _addSystemLog('Bluetooth açılamadı: $e');
    }
  }

  /// Bluetooth'u kapatmayı dener; gerçekten kapandıysa true döner. Android 13+ uygulamaların
  /// Bluetooth'u kapatmasına izin vermiyor ama eklenti yine de true döndürüyor; bu yüzden
  /// sonuç adaptörün durumundan okunuyor.
  Future<bool> requestDisable() async {
    try {
      await FlutterBluetoothSerial.instance.requestDisable();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final isStillEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      return isStillEnabled != true;
    } catch (e) {
      return false;
    }
  }

  Future<void> openBluetoothSettings() async {
    try {
      await FlutterBluetoothSerial.instance.openSettings();
    } catch (e) {
      _addSystemLog('Bluetooth ayarları açılamadı: $e');
    }
  }

  // Özel Kontrol Metotları
  void toggleLight() {
    _isLightOn = !_isLightOn;
    sendCommand(_isLightOn ? 'W' : 'w', description: _isLightOn ? 'Far Aç' : 'Far Kapat');
    notifyListeners();
  }

  void toggleMusic() {
    _isMusicPlaying = !_isMusicPlaying;
    if (!_isMusicPlaying) {
      sendCommand('O', description: 'Müzik Duraklat');
    } else if (_hasStartedMusic) {
      sendCommand('C', description: 'Müziğe Devam Et');
    } else {
      sendCommand('P', description: 'Müzik Oynat');
      _hasStartedMusic = true;
    }
    notifyListeners();
  }

  // Log Yönetimi
  void _addLog(String message, LogType type) {
    _logs.add(SerialLogModel(
      timestamp: DateTime.now(),
      message: message,
      type: type,
    ));

    if (_logs.length > _maxLogCount) {
      _logs.removeAt(0);
    }

    notifyListeners();
  }

  void _addSystemLog(String message) {
    _addLog(message, LogType.system);
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    // Uygulama kapanırken hâlâ süren async işler (komut gönderimi vb.) dispose sonrası
    // bildirim yapıp hata fırlatmasın.
    if (!_isDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stopKeepAlive();
    _discoveryTimer?.cancel();
    _discoveryStreamSubscription?.cancel();
    _stateSubscription?.cancel();

    final connection = _connection;
    _connection = null;
    if (connection != null && connection.isConnected) {
      // Güvenlik: Kapanırken dur komutu; komut gittikten sonra bağlantıyı kapat.
      connection.output.add(utf8.encode('S'));
      connection.output.allSent.whenComplete(connection.close).catchError((Object e) {
        debugPrint('Kapanışta bağlantı kapatılamadı: $e');
      });
    }
    super.dispose();
  }
}
