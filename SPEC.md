# SPEC: Push bildirimi (ntfy) ve iPhone'dan "Bendim<PIN>"

> **VAZGEÇİLDİ (1 Kas 2026):** ntfy/push kaldırıldı, uyarı yolu yalnızca iMessage. iPhone'dan `Bendim<PIN>` ile susturma iMessage üzerinden çalışır. Aşağıdaki metin tarihsel kayıt olarak duruyor.

Karar tarihi: 31 Eki 2026. Kullanıcı seçimi: ntfy.sh (ücretsiz, hesapsız), "Bendim + PIN" ile susturma.

## Neden
iMessage, aynı Apple ID'de Mac'e de senkronlanır; bildirim iPhone'a *ve* Mac'e düşer. Push (ntfy) yalnız abone olunan telefona gider.

## Davranış
- Ayarlar > Bildirimler: yol seçimi `Push (ntfy)` (varsayılan) veya `iMessage`.
- Push: uygulama ilk açılışta rastgele konu üretir (`smm-` + 24 karakter), Keychain'de saklar. Kullanıcı iPhone'da ntfy uygulamasını kurup bu konuya abone olur. `Yeni Konu` ile yenilenir.
- Gönderim: `POST https://ntfy.sh` (JSON), zaman aşımı 15 sn; alarm sesi gönderimi beklemez.
- Susturma: alarm sırasında uygulama 3 sn'de bir konuyu yoklar. Yanıt biçimi: `Bendim<PIN>` veya `Bendim <PIN>` (başka karakter yok; `Benim`, `It was me` de olur). PIN doğruysa alarm susar, koruma kapanır, tek takip mesajı gider. 3 yanlış PIN sonrası uzaktan yanıt kilitlenir. Yalnız alarmdan sonra gelen mesajlar işlenir.
- Test: `Test Mesajı Gönder` önce onay sorar (üçüncü taraf sunucu).

## Riskler (bilinçli kabul)
- PIN, ntfy.sh üzerinden düz metin geçer ve sunucuda kısa süre (~12 saat) önbellekte kalabilir.
- Konu adını bilen biri alarm metnini okuyabilir ve yanıt gönderebilir (PIN'i bilmeden susturamaz; 3 deneme).
- ntfy.sh ücretsiz katmanının hız sınırları vardır; günlük limit resmi kaynaktan doğrulanmadı.
- CLAUDE.md'nin "MVP'de bulut sunucu yok" kuralından kullanıcı onayıyla sapılmıştır.

## Daha güvenli alternatif (seçilmedi)
Alarm bildiriminde tek kullanımlık rastgele kod; gerçek PIN sunucuya hiç gitmez.

## Doğrulama
Birim testleri (sahte URL oturumu) çalışıyor. Gerçek iPhone ile uçtan uca test: yapılmadı.

---

# SPEC: Sadece kaldırma algıla (masada sürükleme/eğme alarm çalmasın)

## Neden
Mevcut algılayıcı referanstan her sapmayı hareket sayıyor (hassasiyet "En yüksek" = 0,02 g). Masada sağa-sola veya çapraz çekmek ve hafif eğmek yanlış alarm veriyor. İstenen: alarm yalnızca Mac **zeminden kaldırılınca** çalsın.

## Fizik / yaklaşım
İvmeölçer "temas bitti" ölçemez, yalnızca ivmeyi ölçer; kaldırma **tahmin edilir**.
- Referans yerçekimi vektörü `b`. Her örnek için sapma `d = a − b`, **dikey** bileşen `v = d·(b/|b|)`, **yatay** bileşen `h = |d − v·b/|b||`.
- Sürükleme / çapraz çekme: yatay ivme (`h` büyük, `v` ≈ 0). Hafif eğme: `h` büyük, `v` çok küçük. → alarm YOK.
- Kaldırma: yerçekimi yönünde (dikey) ivme; `|v|` **sürekli** eşiği aşar. → alarm.
- Kayıtlarımızda (21:15–21:25) sürükleme/eğme izlerinde en büyük `|v|` = 0,013 g, yatay `h` ise 0,36 g'ye kadar çıktı.

## Davranış (kullanıcı kararları)
1. **Dikey kural:** `v` işaretli değerinin son 0,2 sn ortalaması eşiği son 20 ortalamanın 8'inde aşarsa alarm. Kaldırma aynı yöne ivmelenir; masa sallama, vurma ve sürükleme ileri-geri gider, ortalamada sıfırlanır (sallama yanlış alarmı 1 Kas 21:38'de görüldü: `|v|` 0,08 g ama ortalaması 0,003 g).
2. **Büyük eğim kuralı:** son 0,5 sn'nin **ortalama ivme vektörü** referanstan 15°'den fazla dönmüşse alarm (ortalama, yan sallamayı siler). Yavaş kaldırmayı yakalar. Hafif eğme ve masada çekme alarm vermez.
3. **Yatay hareket tek başına asla alarm vermez.**
4. Hassasiyet ayarları (Düşük/Orta/Yüksek/En yüksek) **kalır**; artık dikey eşiği ve eğim sınırını belirler.
5. Mac masada küçük bir açıyla yeni yerine oturursa (3 sn tamamen sakin) referans güncellenir; böylece birkaç çekmeden sonra eğim sınırı birikmez.
6. Geri sayım, kalibrasyon, kilit anında hızlı kalibrasyon ve "geri sayımda hareket alarm çalmaz" davranışı aynen kalır.

## Riskler (bilinçli kabul)
- Çok yavaş ve yumuşak kaldırma, eğim sınırının altında kalırsa kaçabilir.
- Eşikler gerçek Mac'te ölçülerek ayarlanır; kusursuz ayrım vaat edilmez.
- Kısa kenar kaldırıp bırakma (eğim < sınır) alarm vermeyebilir.

## Doğrulama
- Birim test: sürükleme / çapraz / hafif eğme → alarm yok; dikey kaldırma, büyük kalıcı eğim → alarm.
- Gerçek kayıtlarla tekrar oynatma (sürükleme, çapraz, yavaş ve normal kaldırma) ve senin elle denemen.
