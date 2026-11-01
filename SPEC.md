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
