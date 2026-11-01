---
name: acceptance-tests
description: Secure My Mac kabul testi listesi (dil, PIN, alarm, Bendim akışı, sensör, iMessage, derleme). Özellik doğrularken veya sürüm öncesi kullan.
---

# Kabul testleri

- Ayarlarda `Language / Dil` seçimi var; English seçilince uygulamanın TAMAMI İngilizce, Türkçe seçilince TAMAMI Türkçe (PIN, alarm, durum, testler, hata, menü çubuğu, ayarlar). Yeniden başlatmadan değişiyor ve sonraki açılışta korunuyor.
- Her dilde `Send Test Alert`, alarm ve PIN ile doğrulanmış kapatma doğru iMessage içeriğini üretir (kullanılıyorsa yerel macOS bildirimlerini de). Marka ve işletim sisteminin kendi metinleri dışında Türkçe modunda sabit İngilizce veya tersi yoktur.
- İlk açılış PIN kurulumunu sunar. Hatalı PIN normal uygulama arayüzünden korumayı kapatamaz; doğru PIN kapatır.
- Alarmda `It Was Me` belirgindir; doğru PIN alarmı durdurur, korumayı kapatır, olayı kaydeder, `Not Protected` gösterir. Otomatik yeniden korumaya almaz. Yanlış PIN veya iptal sessizleştirmez/kapatmaz. Sahip normal macOS ekran kilidini açınca anlaşılmayan gizli bir kısayola ihtiyaç duymadan `It Was Me` kullanabilir.
- Küçük ekran eğimi veya hafif sarsıntı, gerçek donanım testinde varsayılan kalibre edilmiş hassasiyetle alarmı tetiklememelidir. Hassasiyet ayarını sensör desteği kanıtlandıktan sonra aç.
- Telefon mesajları yalnız bilgilendirir; uzaktan eylem yaptırmaz. Koruma kapatıldı takip mesajı gönderilemezse yerel koruma yine kapanır ve mesajın teslim belirsizliği arayüzde belirtilir.
- Koruma durumu yalnızca korumaya alma başarılıysa değişir; geri sayım iptal edilebilir.
- Yerel test tetikleyicisi alarmı bir kez başlatır ve olayı kaydeder.
- Alarm interneti veya Mesajlar uygulamasını beklemeden başlar.
- Test ters giderse uygulama güvenle durdurulabilir; geliştiriciyi kontrolsüz alarmda mahsur bırakma.
- Sensör desteklenip erişilebiliyorsa kalibrasyondan sonraki kontrollü hareket alarmı tetikler; hareketsiz Mac ilk gözlem süresinde yanlış alarm üretmez.
- iMessage testi: alıcı ayarlanmış ve kullanıcı onaylamış, Otomasyon izni istenmiş, hatalar görülebiliyor ve tekrar eden sensör örnekleri spam üretmiyor.
- Bütün UI düğmeleri çalışır; çalışan özellik gibi gösterilen boş fonksiyon yok.
- `xcodebuild` veya eşdeğer derleme başarılıdır; nasıl çalıştırılacağı belirtilir.
