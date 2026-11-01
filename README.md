# Secure My Mac

Halka açık yerde kısa süre yalnız bırakılan MacBook için yerel bir kurcalama alarmı yardımcısı.
Hırsızlığı **fiziksel olarak önlemez**; değerli eşyaları yanında taşımanın yerine geçmez.

## Çalıştırma
```
./scripts/build-app.sh          # build/Secure My Mac.app üretir (ad-hoc imzalı, yerel kullanım)
open "build/Secure My Mac.app"
swift test                      # 13 birim testi (ses çalmaz, ekran kilitlenmez, mesaj gitmez)
```
Gereksinim: macOS 14+, Xcode/Swift 5.9+. Test edilen Mac: MacBook Pro M2 Pro (Mac14,10), macOS 27.0.1, Xcode 27.2.

## Durum tablosu (dürüst)
| Özellik | Durum |
|---|---|
| TR/EN arayüz, anlık dil değişimi, kalıcı seçim | Çalışıyor (anahtar eşleşmesi test edildi; görsel QA elle) |
| PIN (PBKDF2+tuz, Keychain), yanlış PIN reddi | Çalışıyor (birim testli) |
| Koruma aç/kapat, 3 sn geri sayım, iptal | Çalışıyor (birim testli) |
| Bendim → PIN → alarm sus → koruma kapat | Çalışıyor (birim testli, ses sessize alınarak) |
| Alarm sesi ve Test Alarm | Ses dosyası ve çalma kodu çalışıyor (kilitliyken çalma doğrulandı). Uygulamadaki **Test Alarm düğmesine basma** henüz denenmedi |
| Hareket algılama (gerçek ivmeölçer) | Çalışıyor: 1 Kas 14:27'de gerçek hareketle alarm, telefondan susturma ve mesajlar uçtan uca doğrulandı. Hareketsiz Mac'te sensör temiz (50 sn'de en büyük sapma 0,0066 g). **Koruma başladıktan 8–13 sn sonra temassız yanlış alarmlar görüldü (14:31–14:46; son ikisi 0,025 ve 0,035 g, yani çok küçük).** Önlem: geri sayım (varsayılan 5 sn) sırasında sensör aynı anda sakinleşip kalibre olur (kayan 1 sn'lik pencere: Mac 1 sn sakin kalınca hazır; kilit anında hazır değilse son 0,4 sn'den kalibre edilir), kilitlendiği an izleme açıktır; iki kuralı var: büyük ani hareket (≥0,06 g) hemen, çok hafif sapma (0,02 g) yalnızca ~0,4 sn sürerse alarm; yavaş oturma (~3 sn) referansa katılır. Yanlış alarm olursa ham veri `~/Library/Application Support/SecureMyMac/traces/` altına kaydedilir. **Bu yeni kuralları gerçek cihazda henüz deneyen olmadı.** Belgelenmemiş Apple arayüzü: başka model/sürümde çalışmayabilir |
| Demo modu | Yalnızca **simülasyon**; düğmeyle tetiklenir, gerçek koruma değildir. Açıkken gerçek sensör kullanılmaz |
| Ekran kilidi | Çalışıyor: 31 Eki 2026'da `SACLockScreenImmediate` çağrısı 0 döndü ve 2 sn sonra `CGSSessionScreenIsLocked=true` doğrulandı (belgelenmemiş API; uygulama içi düğme yoluyla değil, aynı çağrıyla ayrı programdan). Uygulamadaki ayar varsayılan kapalı |
| Kilitliyken alarm/izleme arka planda çalışır mı | Kısmen kanıtlandı: kilitliyken süreç çalıştı ve `AVAudioPlayer` 4 sn boyunca çaldı (`isPlaying=true`, `currentTime` ilerledi, döngü sardı). **Duyulduğu kullanıcıdan teyit bekliyor.** Uygulamanın kendi Task/zamanlayıcısıyla uçtan uca test ve uyku (sleep) durumu test edilmedi |
| iMessage + Test Message | Kullanıcı Apple ID e-postasını kendisi yazar (iCloud olmak zorunda değil; gmail, outlook vb. olur, yeter ki Mesajlar > Ayarlar > iMessage'da kayıtlı olsun). Mesajlar'da bulunan adresler öneri olarak gösterilir. Telefon numarası desteği kaldırıldı (bu Mac'te numara iMessage'a kayıtlı değildi, hata 22). Gönderince teslim durumu okunur (Tam Disk Erişimi ile) ve hata nedeni ekranda yazar. 1 Kas 13:09'da alarm mesajı "iletildi" göründü. Yalnız-e-posta yolu gerçek cihazda yeniden denenmedi |
| iPhone'dan yanıtla susturma (`Bendim<PIN>`) | **Gerçek iPhone ile doğrulandı (1 Kas 14:27 ve 14:41): doğru PIN alarmı susturup korumayı kapattı, yanlış PIN susturmadı.** 3 yanlış PIN sonrası kilit gerçek cihazda denenmedi. Birim testli (ayrıştırma, geçici veritabanı). iMessage yolunda Tam Disk Erişimi gerekir; kendi cihazlarından yazılan tüm mesajlar dinlenir, günlüğe yalnız sayı yazılır (içerik yazılmaz). Yalnızca alarm sırasında; 3 yanlış PIN'de kilitlenir |

## Sınırlar
- iPhone'dan yanıtla susturmada PIN iMessage'da yazılır ve **sohbet geçmişinde kalır** (Mac ve iPhone'da). Uçtan uca şifreli olsa da PIN'i sohbetten silmeniz önerilir. Rebuild sonrası ad-hoc imza değiştiği için Tam Disk Erişimi izni yeniden gerekebilir.
- Uyku ≠ kilit: Mac uyurken izleme durabilir. Önce "kapak açık + kilitli + uyanık" senaryosu test edilmeli.
- PIN yalnızca çalışan uygulamada korumayı kapatmayı denetler; Force Quit/kapatmayı engellemez.
- iMessage yalnızca bilgilendirir. Sessiz/Odak modunda ses çıkmayabilir. AppleScript'in başarılı dönmesi, mesajın ulaştığını kanıtlamaz.
- Kurtarma: PIN unutulursa uygulamayı Force Quit edip Keychain'den "com.local.SecureMyMac.pin" kaydını silin (Anahtar Zinciri Erişimi).

## Elle yerelleştirme QA
| Kontrol | EN | TR |
|---|---|---|
| Ayarlar → Language / Dil değiştir, yeniden başlatmadan güncelleniyor | ☐ | ☐ |
| Durum etiketleri, düğmeler, PIN penceresi | ☐ | ☐ |
| Menü çubuğu metinleri | ☐ | ☐ |
| Olay günlüğü etiketleri | ☐ | ☐ |
| Test Message / alarm / "sahip doğrulandı" mesaj metni | ☐ | ☐ |
| Uygulama yeniden açılınca dil korunuyor | ☐ | ☐ |
