# Secure My Mac — Claude Code proje talimatları

## 0. Amaç
Halka açık yerlerde kısa süreliğine tek başına bırakılan MacBook için yüklenebilir, yerel bir macOS **kurcalama/hareket alarmı yardımcısı** geliştir. Kullanıcı korumayı etkinleştirip Mac'i kilitleyebilmeli, algılanabilen şüpheli müdahalede yüksek sesli yerel alarm alabilmeli ve isteğe bağlı iMessage uyarısı gönderebilmelidir. Uygulama hırsızlığı fiziksel olarak önlemez ve değerli eşyaları yanında taşımanın yerine geçmez.

**Kullanıcı arayüzünün dili:** Bugünkü MVP'de eksiksiz Türkçe ve İngilizce yerelleştirme ZORUNLUDUR. Destekleniyorsa macOS'un tercih ettiği dili kullan (tr → Türkçe, diğer durumlarda İngilizce); Ayarlar içinden uygulama çalışırken dil değiştirilebilsin. Geliştiriciye ilerlemeyi ve kararları basit Türkçeyle açıkla. Güvenle kendin yapabileceğin işlemler için kullanıcıya karmaşık komutlar çalıştırma. Proje adı **Secure My Mac**. Prototip bundle identifier: `com.local.SecureMyMac` (gerektiğinde değiştirilebilir).

## 1. Bugünkü MVP — kesin öncelik sırası
Bugün çalışan bir derleme hedefle; temel akış çalışmadan kapsamlı görsel cilaya veya yeni bağımlılıklara zaman ayırma.

### P0 — Mutlaka çalışmalı
- **İlk derlemeden itibaren eksiksiz Türkçe/İngilizce yerelleştirme:** Ayarlar → Dil seçenekleri `System Default / Sistem Varsayılanı`, `English / İngilizce`, `Türkçe / Turkish`. Dil değiştirildiğinde yeniden başlatmadan uygulamanın sahip olduğu bütün metinler anında güncellensin: karşılama ve PIN oluşturma, koruma durumları, ana düğme, alarm ekranı, `It Was Me / Bendim`, açıklamalar, Ayarlar, durum/menü çubuğu öğeleri, yerel bildirimler, iMessage şablonları, tanılama durumları, izin rehberleri, hata/başarı mesajları, test uyarıları ve kullanıcıya gösterilen olay günlüğü etiketleri. İç olay kodları dilden bağımsız kalsın; yalnızca gösterim sırasında çevrilsin. Dil tercihini uygulama yeniden açıldığında koru. Sistem Varsayılanı macOS dilini izlesin; desteklenmiyorsa İngilizceye dönsün. `Secure My Mac` marka adını, dosya adlarını, telefon numaralarını, PIN'i ve macOS'un kendi sistem pencerelerini çevirme. Aynı ekranda dilleri karıştırma. Uygulama ve kabul ayrıntıları için 3a bölümüne bak.
- Swift + SwiftUI ile yerel macOS uygulaması: küçük, şık, tek pencereli arayüz; menü çubuğu durumu; boşta/koruma açık/alarm durumları.
- İlk kullanımda 4–6 haneli **uygulama PIN'i** belirleme ve tekrar girerek doğrulama. Güvenli saklama (Keychain veya uygun korumalı depolamada salt uygulanmış parola hash'i; ASLA düz metin veya loglarda değil). Korumayı kapatmak için PIN zorunlu. Uygulama PIN'i macOS giriş parolasından ayrıdır. Normal işletim sistemi güvenliğini atlamayan belgelenmiş bir kurtarma prosedürü sağla; PIN'in hırsızlığa karşı aşılmaz olduğunu iddia etme.
- `Activate Protection` → 5 saniye geri sayım (ayar yok, sabit; sensör geri sayımla birlikte başlar) → izleyiciyi devreye alma → belgelenmiş/desteklenebilir ve test edilmiş yöntemle gerçek macOS ekran kilidini deneme. Kilidin gerçekleşip gerçekleşmediğini doğrula, başarısızlığı göster. Sahte tam ekran pencereyle sistem kilidinin yerini doldurma.
- Pakete eklenmiş ÖZGÜN veya LİSANSI UYGUN ses dosyasıyla yerel alarm. Teknik olarak mümkün olduğu sürece yetkili biçimde kapatılana kadar tekrar etsin. Belirgin bir `Test Alarm` kontrolü olsun. Ses seviyesi makul bir üst sınırla kısıtlansın; sesin hiçbir koşulda kapatılamayacağı söylenmesin. Sessiz/güvenli test yönergeleri ver.
- Zaman damgalı yerel olay günlüğü: koruma açıldı, kapandı, alarm, bildirim denemesi, başarısızlık, sahibi tarafından onaylanmış yanlış alarm.
- **Sahibin yanlış alarmı kapatması (zorunlu):** Alarm tetiklenince ekranda normal `Deactivate` yolunun yanında belirgin `It Was Me / Bendim` seçeneği olsun. Dokununca PIN doğrulama penceresi açılsın. YALNIZCA doğru PIN'den sonra alarmı durdur, bekleyen yinelenen uyarıları iptal et, korumayı kapat (`Not Protected`), `Owner confirmed / Disarmed` olayını kaydet ve isteğe bağlı TEK bir takip iMessage'ı gönder: `Secure My Mac: Owner verified. Protection deactivated.` Yeniden korumaya almak için kullanıcının ayrıca `Activate Protection` demesi zorunlu. Yanlış PIN sesi durdurmamalı ve korumayı kapatmamalı. Sahibi geri dönüp normal macOS kilidini açtıktan sonra bu alarm ekranına erişebilmeli.
- Donanımda hareket algılama bulunmasa bile alarmın ve arayüzün tamamını test etmek için Mac kilitli değilken bir **test tetikleme** düğmesi/klavye kontrolü.
- Çalışır durumda kurcalama algılayıcısı yoksa uygulama kendini `protected` olarak tanıtmasın. `Motion sensor unavailable` durumunu açıkça göster; ayrıca etiketlenmiş manuel demo modu sağla.

### P1 — P0'dan sonra
- Uyumlu Apple Silicon MacBook'larda, yalnızca BU bilgisayarda erişim doğrulandıktan sonra gerçek hareket algılama. Sensör okuyucuyu `MotionProvider` protokolü arkasına koy; `AppleSiliconMotionProvider` ve `SimulationMotionProvider` uygulamaları olsun. Yetenek kontrolü ve açıklayıcı hata sağla. Küçük titreşimler veya hafif ekran açısı değişiklikleriyle yanlış alarmı azaltmak için eşikler, başlangıç kalibrasyonu ve debounce (ör. peş peşe anormal örnekler, ayarlanabilir hassasiyet) kullan. Geri sayımdan sonra isteğe bağlı 5–10 saniyelik hazırlık süresi, hareketsiz referans kalibrasyonu ve alarm için birden fazla sürdürülen eşik aşımı değerlendir. Her hassasiyeti gerçek cihazda test et; sahibi ile hırsızı kusursuz ayırdığını vaat etme. Tüm cihazlarda çalışacağını varsayma. Ayrıcalıklı komut veya root servisi kullanmadan önce nedenini açıkla ve geliştiricinin onayını al. SIP atlatma, güvenliği devre dışı bırakma, gizli kalıcılık yok.
- Desteklenen güç API'leri ve bildirimleriyle güvenilir olduğu doğrulanırsa isteğe bağlı şarj kablosu çıkarılma tespiti. Kısa yol olarak keylogger veya küresel tuş izleme ekleme; klavye/fare hareketini fiziksel hırsızlıkla eş tutma.
- Oturum açılmış `Messages.app` üzerinden AppleScript / Apple Events ile, kullanıcının açıkça onayladığı alıcıya isteğe bağlı iMessage uyarısı; gereken Otomasyon izni. Önce `Send Test Alert`. Mesajlar veritabanını okumadan doğrudan gönderimi tercih et; sırf uyarı göndermek için Full Disk Access isteme. Alıcıyı güvenli sakla; telefon E.164 veya Apple ID e-postası doğrulaması yap. Hataları açıkça göster. Onaylanmamış alıcıya otomatik mesaj gönderme. Her alarm olayı için ör. tek uyarı; doğrulanmış devreden çıkarma için tek ayrı takip mesajı. 10–30 saniye timeout kullan; bildirim gönderimi alarmı bekletmesin. Giden iMessage yalnızca mesajdır; iPhone üzerinde özel ve güvenli, tıklanabilir `It Was Me` eylemi OLUŞTURAMAZ. Sahte eylemli bildirim düğmeleri kurma, `BENİM` yanıtına güvenme, doğrulanmamış mesajla uzaktan korumayı kapatma. Gerçek iPhone eylem düğmesi için güvenilir yardımcı iOS uygulaması, uzaktan kimlik doğrulama ve gönderim altyapısı gerekir; MVP dışında. MVP'de `It Was Me`, normal macOS kilidi açıldıktan sonra uygulama PIN'iyle Mac üzerinde çalışır.

### P2 — Sonraki sürümler; MVP'yi engellemez
Daha iyi uyku/kapak algılama, isteğe bağlı oturum açılışında çalıştırma, sağlam paketleme, kullanıcı kontrollü hassasiyet, kapsamlı ilk kurulum/yardım, imzalı ve notarize edilmiş sürüm, Windows fizibilitesi. MVP'de webcam/mikrofon kaydı, konum takibi, uzaktan kontrol, bulut sunucu, hesap açma, analitik veya ödeme YOK.

## 2. Önemli macOS kısıtları — yanlış vaat verme
- MacBook sensör desteği değişir. Apple'ın herkese açık Core Motion arayüzleri genel amaçlı MacBook hareket sensörü API'si değildir. Gerçek erişilebilir API'leri araştır ve test et. Topluluk projelerindeki Apple Silicon SPU/IOHID yaklaşımı belgelenmemiştir, root isteyebilir ve başka modellerde çalışmayabilir. Deneysel olarak ele al. İzinleri, modeli, OS sürümünü, gözlenen ölçümleri ve sınırları belgele.
- **Uyku ve kilit farklıdır:** Ekran kilidi ≠ uyku. Uyurken izleme süreci durabilir; uyku, sessiz mod, kapalı bilgisayar veya kullanılamayan hoparlörde alarm çalmayabilir. Önce kapak açık + ekran kilitli + Mac uyanık senaryosunu test et. Kapak kapalıyken sürekli koruma vaat etme.
- Uygulama PIN'i sadece çalışan uygulamada korumayı kapatmayı denetler; Force Quit, kapatma veya fiziksel hırsızlığı engelleyemez. Force Quit ya da sistem kontrollerini devre dışı bırakmaya çalışma. Güvenli bir testten çıkış planı tut.
- Uygulama iPhone'un Sessiz/Odak modunda sesli uyarıyı zorlayamaz. iMessage; Mac'in Mesajlar oturumuna, Otomasyon iznine, ağa ve alıcının iMessage ayarına bağlıdır ve gecikebilir. Kendi numarana atılan mesajın diğer Apple cihazında uyarı üretmesi güvenilir olmayabilir; çalıştığını söylemeden gerçek alıcıda TEST ET.
- Apple Find My kimliğini taklit etme, telifli alarm sesini kullanma veya Find My entegrasyonu varmış gibi gösterme. Özgün alarm sesi kullan.

## 3. Uygulama deneyimi / tasarım
- Pazarlama sitesi değil; temiz, premium ve minimal yerel macOS görünümü. SwiftUI material, ferah boşluklar, açık/koyu tema desteği.
- Yaklaşık 420 px genişliğinde pencere. Üstte kalkan simgesi, Secure My Mac, durum etiketi (`Not Protected`, `Arming`, `Armed`, `Alarm`, `Unavailable`).
- Ortada büyük kalkan çizimi, belirgin tek ana düğme (`Activate Protection` / `Deactivate`), 5 saniyelik geri sayım, küçük durum açıklaması. Alarm ekranında, sesi kesip korumayı kapatmadan önce uygulama PIN'i gerektiren `It Was Me / Bendim` belirgin olsun. İşlem sonrası korumanın KAPALI kalacağını ve yeniden elle etkinleştirilmesi gerektiğini açıkla.
- Küçük ayar paneli: Language / Dil (System Default, English, Türkçe), PIN belirle/değiştir, hassasiyet (yalnız donanım sensörü destekleniyorsa), iMessage alıcısı, Test Message, Test Alarm, tanılama ve izinler.
- Menü çubuğu simgesi: koruma/alarm durumu, Uygulamayı Aç, durum, Çıkış. Çıkış seçildiğinde cihaz koruma altındaymış gibi sessizce ayrılma; normal uygulama içi koruma kapatma PIN gerektirsin. OS Force Quit'in önlenemeyeceğini kabul et.
- Tek ve açık durum makinesi: `idle -> arming -> armed -> alerting -> verifyingOwner -> idle` (PIN yanlış/iptal ise `alerting`). İzleme kurulumu başarılı değilse ekranı kilitlemek tek başına `armed` sayılmaz. Çift olay kaydını önlemek için `alarmTriggered`, `messageSent`, `ownerConfirmed` bayraklarını ayrı tut. Doğrulanmış `It Was Me` sonrasında tek son durum `Not Protected` olsun.
- Erişilebilir düğmeler ve etiketler; sahte/işlevsiz düğme olmasın.

## 3a. Yerelleştirme (ZORUNLU P0 — sonraya bırakma)
- Apple'ın yerelleştirme sistemlerini kullan: `en` ve `tr` içeren String Catalog (`Localizable.xcstrings`) ve sabit anahtarlar. MVP'de Xcode katalogları yoksa `en.lproj` ve `tr.lproj` altındaki `Localizable.strings` kullanılabilir. Kullanıcıya gösterilen Türkçe/İngilizce metinleri view'ların içine dağınık biçimde sabitleme.
- Tek bir `LocalizationManager` (`ObservableObject`/Observable state) ve `AppLanguage { system, en, tr }` enum'u kullan; seçimi `AppStorage`/UserDefaults ile koru. `system` için etkin dili macOS locale'den belirle. SwiftUI'ya `.environment(\.locale, Locale(identifier: ...))` yoluyla aktar. SwiftUI ortamı tek başına çevirmeyebileceği için tüm **AppKit/menü çubuğu, uyarılar, kodla oluşturulan hata metinleri ve iMessage içerikleri** ortak `localized(key, language:)` yardımcısını kullansın.
- Ayarlardan dil değişince arayüz (mümkünse menü çubuğu da) yeniden başlatmadan anında güncellensin. Görünen bütün durumlar ve olay günlüğü açıklamaları çevrilsin. Alıcının elle yazdığı adres, PIN ve dosya yolları aynen korunsun.
- Bildirim üretimi merkezî olsun: ör. `MessageTemplates.alarmDetected(language:)`, `MessageTemplates.ownerVerified(language:)`, `MessageTemplates.test(language:)`, isteğe bağlı `localNotification(language:)`. Her bildirim oluşturulup gönderilirken geçerli uygulama dili kullanılsın. Önceden gönderilmiş mesajları değiştirmeye çalışma, iPhone bildirim ekranını düzenleyebileceğini vaat etme.
- Hassas dosya/hesap bilgisi içermeyen zorunlu örnek mesajlar:
  - TR alarm: `Secure My Mac: Güvenlik uyarısı! MacBook'unuzda hareket algılandı. Koruma etkin.`
  - EN alarm: `Secure My Mac: Security alert! Movement detected on your MacBook. Protection is active.`
  - TR doğrulanmış kapatma: `Secure My Mac: Sahip doğrulandı. Alarm susturuldu ve koruma kapatıldı.`
  - EN doğrulanmış kapatma: `Secure My Mac: Owner verified. Alarm stopped and protection deactivated.`
  - TR test: `Secure My Mac: Bu bir test bildirimidir.`
  - EN test: `Secure My Mac: This is a test notification.`
- Şu durum/eylem anahtarlarını sağla: `Not Protected / Koruma Kapalı`, `Arming / Koruma Başlatılıyor`, `Protected / Koruma Açık`, `Alarm / Alarm`, `Unavailable / Kullanılamıyor`, `It Was Me / Bendim`, `Activate Protection / Korumayı Başlat`, `Deactivate / Korumayı Kapat`.
- Bildirim gönderim anında seçilen dili kullansın; dil değişimi yeni bildirimlere ve ekrana yansısın. iPhone için ayrıca dil ayarı gerekmesin.
- Her iki dilde kesilen etiketleri, PIN/güvenlik akışlarını, menü çubuğunu, test mesajını, simüle alarmı, sahibi doğrulanınca takip mesajını ve uygulama yeniden açıldığında seçimin korunmasını test et. README'ye testleri veya elle yapılabilecek bir yerelleştirme QA tablosu ekle.

## 4. Önerilen mimari
Swift 6/SwiftUI, gerektiğinde AppKit, Foundation, Security framework/Keychain, isteğe bağlı yerel bildirimler için UserNotifications, yalnız donanım fizibilitesi doğrulanırsa IOKit kullan. Açık sorumluluklu az sayıda dosyayı tercih et.

Kod yapısı için `Sources/SecureMyMac/` (Models, Services, Views) altına bak; dosya ağacı burada tutulmuyor.

Mimari kurallar:
- `ProtectionCoordinator` korumaya alma/kapatma ve durum geçişlerini yönetir, olayları sırayla ele alır; yarış durumlarını ve tekrar eden alarmları önle.
- Sensör callback'i ağ isteğini veya UI'yi bloke etmesin.
- Bildirimi timeout ile asenkron gönder; ses interneti/Mesajlar'ı beklemeden başlasın.
- Ayarları yerel ve izinlere duyarlı sakla; sabit telefon numarası, kimlik bilgisi, API anahtarı koyma.
- `Unsupported` / `Permission denied` / `Sleeping` / `Disconnected` gibi durumları açıkça göster.
- Güvenli iptal ve temiz çıkış sağla.

## 5. Kapsam kuralı

**Kapsam kuralı:** macOS hareket/iMessage işlevini engelliyorsa çalışıyormuş gibi gösterme. Dürüstçe test edilebilen temel uygulamayı simüle olayla teslim et; engelleri görünür biçimde işaretle.

## 6. Kabul testleri
Kabul testi listesi `.claude/skills/acceptance-tests` skill'ine taşındı; özellik doğrularken veya sürüm öncesi o skill'i kullan.

## 7. Claude Code çalışma tarzı
- Benimle **basit ve kısa Türkçe** konuş. Ne değiştirdiğini, çalıştırmam gereken tek komutu ve onaylamam gereken izin penceresini söyle.
- Yalnız plan yazma; kodu uygula, çalıştırılabilir uygulamayı oluştur. Küçük doğrulanabilir adımlarla ilerle, sık sık derle ve derleme hatalarını düzelt.
- Riskli işlemlerden (sudo/root, sistem gizlilik izinleri, ekranımı kilitleme, gerçek kişiye iMessage, dosya silme, oturum açma yardımcıları yükleme) önce açıkla ve izin iste.
- Desteklenmeyen güvenlik garantileri verme. Gerçek API ve testleri kullan. Emin değilsen belirsizliği belirt.
- README'yi kurulum, testler, sınırlamalar ve test edilen Mac modelleriyle güncel tut.

## 8. Teknik inceleme için referanslar
- Apple Silicon ivmeölçer topluluk denemesi: https://github.com/olvvier/apple-silicon-accelerometer (belgelenmemiş, root isteyebilir; yalnız fizibilite referansı)
- MacBook hareket-alarm ürünü örneği: https://chassis.watch/ (ilham; tüm Mac modellerinde çalıştığının kanıtı değil)
- Messages AppleScript izni kavramı: https://imsg.sh/send.html (giden Mesajlar otomasyonu)

## 9. Skill kullanımı
Skill'ler yardımcıdır, zorunlu değildir. Bölüm 7'deki riskli işlemler ve onay kuralları skill kullanımında da aynen geçerlidir.
- Yalnızca **kurulu** ve mevcut işe **gerçekten uygun** skill'i kullan.
- Küçük değişikliklerde (metin düzeltme, tek view'da ufak stil ayarı, küçük bug fix) skill zorunlu değildir.
- Genelde tek işe **tek skill** yeterlidir; birden fazlasını yalnızca gerçekten gerekiyorsa birlikte kullan.
- Bir skill kurulu değilse **kurulum önermeden** işe devam et.

Uygun olduğunda kullanılabilecek skill'ler:

| Skill | Ne zaman uygun? |
|---|---|
| `senior-security` | PIN saklama (Keychain/hash), Apple Events/Otomasyon izni, iMessage, ekran kilidi ve sensör erişimi gibi güvenlik konuları. |
| `code-reviewer` | Anlamlı aşama tamamlandığında (ör. durum makinesi, `It Was Me`, `MessagesNotifier`) derleme/test öncesi. |
| `senior-frontend` | Yalnızca SwiftUI için genel UI kararları; web odaklı React/Tailwind tavsiyelerini bu projeye uygulama. |
| `ui-ux-pro-max` / `frontend-design` | Ana pencere, alarm ekranı ve ayarlarda büyük tasarım kararları; önerileri yerel SwiftUI/macOS diline uyarla, web kalıplarını kopyalama. |
| `skill-creator` | Tekrarlanan akış (ör. TR/EN QA) skill'e dönüştürülecekse. |
| `pdf` / `docx` / `pptx` / `deep-research` | Yalnız ilgili belge, sunum veya araştırma görevi gerektiğinde. |

## 10. Otomasyon önerileri (`claude code setup`)
`claude code setup` bu proje için **isteğe bağlı öneri aracıdır**.
- MCP, hook, subagent veya slash command önerilerini her adımda ya da tekrar tekrar sunma.
- Yalnız gerçekten tekrarlanan veya elle zahmetli işte öner (ör. aynı build/test komutunu üçüncü kez çalıştırma veya sürekli lokalizasyon testi).
- Öneri kısa olsun: *ne* + *neden* + kopyalanabilir komut.
- **Onaysız kurulum veya ayar değişikliği yapma.** Önce öner, ben evet dersem uygula.
- Bölüm 1 ve 2 sınırlarına uy: sudo/root, gizli kalıcılık (login helper vb.), SIP/güvenlik atlatma ve gizli servis isteyen otomasyon önerme.
- Hook/MCP önerileri PIN, Keychain içeriği, alıcı numarası veya e-postayı log'a, çıktıya ya da dış hizmete yazmasın; gerçek iMessage yollayan veya ekran kilitleyen otomasyonu onaysız çalıştırma.
- MVP kapsamına girmeyen veya gerekli olmayan özellik önerme.

**Bugünkü başarı kriteri:** Gerçek bir macOS uygulaması açılıyor; güvenli PIN ile görsel olarak korumaya alınıp kapatılıyor; test alarmı çalıyor; bir müdahale olayı gösterilebiliyor; `It Was Me` → PIN → sesi durdur + korumayı kapat akışı çalışıyor. Yeniden korumaya alma bilinçli kullanıcı eylemi gerektiriyor. Gerçek ivmeölçer ve iPhone bildirimleri yalnızca bu Mac üzerinde test edilerek çalıştığı doğrulanırsa ek başarıdır. Kanıtlamadan çalışıyor deme.
