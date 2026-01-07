# ANDA AKE

**ANDA AKE**, Arama Kurtarma (SAR) ekipleri için geliştirilmiş, kritik görev bildirimlerini "Nükleer Alarm" seviyesinde duyuran bir Flutter uygulamasıdır.

## 🚨 Özellikler (Nükleer Mod)

Bu uygulama, normal "Rahatsız Etme" (DND) veya "Sessiz" modları aşarak kullanıcının dikkatini kesinlikle çekmek için tasarlanmıştır:

*   **DND Bypass**: `ACCESS_NOTIFICATION_POLICY` izni sayesinde, telefon "Rahatsız Etme" modunda olsa bile alarm çalar.
*   **Maksimum Ses**: Alarm tetiklendiğinde cihazın medya ve zil sesi seviyesi otomatik olarak **%100**'e yükseltilir.
*   **WakeLock**: Alarm ekranı (`AlarmScreen`) açıldığında ekranın kapanması engellenir.
*   **Kilit Ekranı (Full Screen Intent)**: Telefon kilitli olsa bile alarm ekranı direkt olarak açılır (Android 10+ için özel izin gerektirir).
*   **Sürekli Titreşim & Ses**: Kullanıcı "ACKNOWLEDGE" (Onayla) butonuna basana kadar alarm döngüsel olarak devam eder.

## 🛠 Kurulum ve Gereksinimler

### 1. Android İzinleri
Uygulama ilk açıldığında aşağıdaki izinleri talep eder:
*   **Bildirim Erişimi**: `POST_NOTIFICATIONS`
*   **DND Erişimi**: `ACCESS_NOTIFICATION_POLICY` (Ayarlardan manuel onay gerekebilir).

### 2. Firebase Kurulumu
*   Projenin `android/app/` dizininde geçerli bir `google-services.json` dosyası olmalıdır.
*   Firebase Console'dan alınan **Server Key** veya **Token** kullanılarak test yapılabilir.

## 🧪 Nasıl Test Edilir?

### FCM Test Bildirimi
Firebase Console veya Postman üzerinden aşağıdaki `data` payload'ı ile bildirim gönderin:

```json
{
  "to": "<DEVICE_FCM_TOKEN>",
  "priority": "high",
  "data": {
    "title": "ACİL DURUM",
    "body": "EKİP TOPLANIYOR - KIRMIZI ALARM",
    "mission_id": "12345"
  },
  "android": {
    "priority": "high",
    "notification": {
      "channel_id": "sar_channel_critical",
      "sound": "alarm"
    }
  }
}
```

### Manuel Test
1.  Uygulamayı açın.
2.  Ana ekrandaki **"TEST ALARM"** butonuna basın.
3.  *Zorlu Koşul:* Telefonu sessize alın, ekranı kilitleyin ve testi tekrarlayın.

## 📂 Proje Yapısı

*   `lib/main.dart`: Firebase başlatma, FCM dinleyicileri, Bildirim Kanalı ayarları.
*   `lib/alarm_screen.dart`: Nükleer alarm mantığı (Ses döngüsü, WakeLock, Max Ses).
*   `android/app/src/main/AndroidManifest.xml`: Kritik izinler (`USE_FULL_SCREEN_INTENT`, `WAKE_LOCK`).
