# ANDA AKE — Safety-Critical SAR Alarm System

> **ANDA AKE**, Arama Kurtarma (SAR) ekipleri için geliştirilmiş, kritik görev bildirimlerini "Nükleer Alarm" seviyesinde duyuran, **WebSocket tabanlı** bir Flutter + Node.js uygulamasıdır.

## 🏗 Mimari (Architecture)

Bu sistem **Firebase'den bağımsız** olarak çalışır. Alarm dağıtımı, Raspberry Pi üzerinde çalışan bir **Node.js WebSocket sunucusu** aracılığıyla yapılır.

```
┌─────────────────────────────────────────────┐
│           Raspberry Pi (anda.biricik.de)     │
│  ┌───────────────────────────────────────┐  │
│  │  Node.js Server (Express + ws)        │  │
│  │  POST /api/trigger-alarm → Broadcast  │  │
│  │  WS /ws → Real-time alarm delivery    │  │
│  │  GET /api/pending-alarms → Polling    │  │
│  └───────────────────────────────────────┘  │
│              Docker Container               │
└─────────────────────────────────────────────┘
              ↕ WebSocket + HTTP
┌─────────────────────────────────────────────┐
│           Flutter Android Client             │
│  ┌─────────────────────────────────────────┐│
│  │ Foreground Service (anti-Doze)          ││
│  │ WebSocket Client + Polling Fallback     ││
│  │ Nuclear Alarm (DND bypass, max volume)  ││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

## 🚨 Özellikler (Nükleer Mod)

Bu uygulama, normal "Rahatsız Etme" (DND) veya "Sessiz" modları aşarak kullanıcının dikkatini kesinlikle çekmek için tasarlanmıştır:

*   **DND Bypass**: `ACCESS_NOTIFICATION_POLICY` izni sayesinde, telefon "Rahatsız Etme" modunda bile alarm çalar.
*   **Maksimum Ses**: Alarm tetiklendiğinde cihazın ses seviyesi **%100**'e yükseltilir.
*   **WakeLock**: Alarm ekranı açıldığında ekranın kapanması engellenir.
*   **Kilit Ekranı (Full Screen Intent)**: Telefon kilitli olsa bile alarm ekranı direkt olarak açılır.
*   **Sürekli Titreşim & Ses**: Kullanıcı "ACKNOWLEDGE" butonuna basana kadar alarm devam eder.
*   **Foreground Service**: Android Doze modunu atlatarak WebSocket bağlantısını canlı tutar.

## 🛡 Safety-Critical Tasarım Desenleri

| Desen | Kaynak | Uygulama |
|---|---|---|
| **Acceptance Tests** | Ch.4 | Her alarm hem sunucu hem istemci tarafında doğrulanır |
| **Heartbeat Watchdog** | Ch.3 | 15 sn ping/pong, 3 cevapsız = bağlantı kesilir |
| **Recovery Block** | Ch.4 | WebSocket birincil kanal, HTTP polling yedek kanal |
| **Forward Error Recovery** | Ch.3 | Üssel geri çekilme ile otomatik yeniden bağlantı |
| **Error Confinement** | Ch.2 | Bir istemcinin hatası diğerlerini etkilemez |
| **N-Version Programming** | Ch.2 | Dual-channel alarm teslimi (WS + polling) |

## 📂 Proje Yapısı

```
lib/
├── config.dart                        # Merkezi yapılandırma (URL, API key, vb.)
├── main.dart                          # Ana uygulama, C2 Dashboard UI
├── alarm_screen.dart                  # Nükleer alarm ekranı
├── background/
│   └── foreground_task_handler.dart   # Android Foreground Service
├── models/
│   └── alarm_message.dart             # Alarm veri modeli
├── safety/
│   └── acceptance_test.dart           # İstemci tarafı alarm doğrulama (AT-1..AT-6)
└── services/
    ├── notification_service.dart      # Yerel bildirimler (fullScreenIntent)
    └── websocket_service.dart         # WebSocket istemcisi

server/
├── Dockerfile                         # Sunucu Docker imajı
├── server.js                          # Node.js WebSocket + REST sunucusu
└── package.json                       # Bağımlılıklar (express, ws, uuid)
```

## 🧪 Test

### Yerel Alarm Testi
1. Uygulamayı açın.
2. Dashboard'daki **"TRIGGER LOCAL ALARM TEST"** butonuna basın.
3. *Zorlu koşul:* Telefonu sessize alın, ekranı kilitleyin ve testi tekrarlayın.

### Sunucu Üzerinden Alarm Testi
```bash
curl -X POST http://anda.biricik.de/api/trigger-alarm \
  -H "Content-Type: application/json" \
  -H "X-API-Key: anda-ake-secret-key-change-me" \
  -d '{"title": "ACİL DURUM", "body": "EKİP TOPLANIYOR - KIRMIZI ALARM", "priority": "critical"}'
```

### Sunucu Durumu Kontrolü
```bash
curl http://anda.biricik.de/api/health
```

## 🛠 Kurulum

### Sunucu (Docker)
```bash
docker-compose up -d anda-ake
```

### İstemci (Flutter)
```bash
flutter pub get
flutter run
```

### Android İzinleri
Uygulama ilk açıldığında aşağıdaki izinleri talep eder:
*   Bildirim erişimi (`POST_NOTIFICATIONS`)
*   DND erişimi (`ACCESS_NOTIFICATION_POLICY`)
*   Pil optimizasyonu muafiyeti (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`)
