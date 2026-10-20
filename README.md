# Arduino Controller App (Flutter)

📱 **Arduino Controller App**, Flutter kullanılarak geliştirilmiş, HC-05, HC-06 gibi Bluetooth seri modülleri aracılığıyla Arduino projelerinizi (robot, RC araç vb.) kontrol etmenizi sağlayan özelleştirilebilir bir mobil uygulamadır.

> ⚠️ **Yalnızca Android:** HC-05/HC-06 klasik Bluetooth (SPP) kullanır. iOS bu modüllere bağlanmaya izin vermediği için uygulama iOS'ta çalışmaz.

## 🚀 Özellikler

- **Bluetooth Bağlantısı**: Yakındaki cihazları arama ve eşleşmiş cihazlara kolayca bağlanma (`flutter_bluetooth_serial_plus` kullanarak).
- **Yön Kontrolleri**: İleri, geri, sağ, sol gibi hareket komutları için yön butonları.
- **Aksiyon Butonları**: Özel fonksiyonlar (örneğin; korna, farlar, ekstra motor hareketleri) atayabileceğiniz aksiyon butonları.
- **İzin Yönetimi**: Gerekli Bluetooth ve Konum izinlerini otomatik yönetme (`permission_handler`).
- **Ayarları Kaydetme**: `shared_preferences` ile tercihleri hafızada tutma imkanı.
- **Modern Arayüz**: Akıcı ve kullanıcı dostu arayüz tasarımı.

## 🛠 Kullanılan Teknolojiler & Paketler

Uygulama geliştirilirken aşağıdaki başlıca Flutter paketleri kullanılmıştır:

- [provider](https://pub.dev/packages/provider) (State Yönetimi)
- [flutter_bluetooth_serial_plus](https://pub.dev/packages/flutter_bluetooth_serial_plus) (Bluetooth Haberleşmesi)
- [permission_handler](https://pub.dev/packages/permission_handler) (İzin Kontrolleri)
- [shared_preferences](https://pub.dev/packages/shared_preferences) (Yerel Veri Saklama)

## 📱 Kurulum & Çalıştırma

Projeyi kendi bilgisayarınızda çalıştırmak için aşağıdaki adımları takip edin:

1. Depoyu bilgisayarınıza klonlayın:

   ```bash
   git clone https://github.com/FurkanOguzgoksu/arduino_controller_app.git
   ```

2. Proje dizinine gidin ve bağımlılıkları yükleyin:

   ```bash
   cd arduino_controller_app
   flutter pub get
   ```

3. Gerekli izinleri onayladığınızdan emin olun (Özellikle Android `AndroidManifest.xml` içerisindeki Bluetooth/Konum izinleri ayarlanmıştır).

4. Uygulamayı bağlı bir cihazda veya emülatörde çalıştırın (Bluetooth özellikleri fiziksel bir cihaz gerektirir):
   ```bash
   flutter run
   ```

## 🤖 Arduino Tarafı İçin Örnek Kod (Kaba Taslak)

Uygulama her komutu tek bir karakter olarak gönderir:

| Komut              | Anlamı                         | Komut     | Anlamı                 |
| ------------------ | ------------------------------ | --------- | ---------------------- |
| `F`                | İleri                          | `G`       | İleri sol              |
| `B`                | Geri                           | `I`       | İleri sağ              |
| `L`                | Sola dön                       | `H`       | Geri sol               |
| `R`                | Sağa dön                       | `J`       | Geri sağ               |
| `S`                | Dur / acil stop                | `W` / `w` | Far aç / kapat         |
| `P`                | Müziği ilk şarkıdan başlat     | `O`       | Müziği duraklat        |
| `C`                | Müziğe kaldığı yerden devam et | `N` / `V` | Sonraki / önceki şarkı |
| `#12` + satır sonu | Far pini 12 (`#A0`: A0 pini)   |           |                        |

- **Bağlantı sinyali:** Araç hareket ederken uygulama her 300 ms'de bir `.` gönderir. Arduino bir süre hiç veri alamazsa bağlantı kopmuş demektir (telefon uzaklaştı, uygulama kapandı...) ve aracı durdurmalıdır.
- **Far pini:** Farın bağlı olduğu pin projeden projeye değiştiği için uygulamadaki **Araç Ayarları**'ndan (kontrol ekranının üst çubuğu) girilir. Her araç için ayrı kaydedilir ve uygulama bağlanınca `#12` gibi bir satır gönderir. Bu satır yalnızca `#`, rakam ve `A` içerdiği için, bu özelliği bilmeyen Arduino kodları onu yok sayar.

Örnek bir Arduino kodu:

```cpp
#include <SoftwareSerial.h>
SoftwareSerial BTSerial(10, 11); // RX, TX

// Bu süre boyunca hiç veri gelmezse bağlantı kopmuş sayılır
const unsigned long BAGLANTI_ZAMAN_ASIMI = 1000;
unsigned long sonVeriZamani = 0;
bool hareketEdiyor = false;

// Far pini uygulamadan "#12" veya "#A0" satırıyla gelir
int farPini = -1;
String ayarSatiri;
bool ayarOkunuyor = false;

void setup() {
  Serial.begin(9600);
  BTSerial.begin(9600);
}

void loop() {
  if (BTSerial.available()) {
    char command = BTSerial.read();
    sonVeriZamani = millis();

    if (ayarOkunuyor) {
      if (command == '\n' || command == '\r') {
        ayarOkunuyor = false;
        farPiniAyarla(ayarSatiri);
      } else {
        ayarSatiri += command;
      }
    } else if (command == '#') {
      ayarOkunuyor = true;
      ayarSatiri = "";
    } else if (command == 'F') {
      // İleri git
      hareketEdiyor = true;
    } else if (command == 'S') {
      // Dur
      hareketEdiyor = false;
    } else if (command == 'W' && farPini >= 0) {
      digitalWrite(farPini, HIGH);
    } else if (command == 'w' && farPini >= 0) {
      digitalWrite(farPini, LOW);
    }
    // ... diğer komutlar ('.' yok sayılır, sadece bağlantının sürdüğünü gösterir)
  }

  // Güvenlik: bağlantı koptuysa aracı durdur
  if (hareketEdiyor && millis() - sonVeriZamani > BAGLANTI_ZAMAN_ASIMI) {
    // Motorları durdur
    hareketEdiyor = false;
  }
}

void farPiniAyarla(String yazi) {
  int pin = yazi.startsWith("A") ? A0 + yazi.substring(1).toInt() : yazi.toInt();
  // 0-1 seri port, 10-11 Bluetooth; projede başka işe kullanılan pinleri (motor, sensör...)
  // de burada reddedin
  if (pin < 2 || pin == 10 || pin == 11 || pin >= NUM_DIGITAL_PINS) {
    return;
  }

  if (farPini >= 0) {
    digitalWrite(farPini, LOW);
  }
  farPini = pin;
  pinMode(farPini, OUTPUT);
}
```

## 🤝 Katkıda Bulunma

Projeye katkıda bulunmak isterseniz "Pull Request" (PR) göndermekten veya bir "Issue" açmaktan çekinmeyin!

1. Bu depoyu Fork'layın
2. Yeni bir dal oluşturun (`git checkout -b feature/yeniOzellik`)
3. Değişikliklerinizi Commit'leyin (`git commit -m 'Yeni özellik eklendi'`)
4. Dalınıza Push'layın (`git push origin feature/yeniOzellik`)
5. Bir Pull Request açın!

## 📝 Lisans

Bu proje açık kaynak kodlu olup dilediğiniz gibi kullanabilir ve geliştirebilirsiniz.
