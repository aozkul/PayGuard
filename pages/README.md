# PayGuard · GitHub Pages

UFFF ile ortak yapı: Türkçe/İngilizce/Almanca tanıtım, destek ve gizlilik. Yalnız `pages/public/` yayımlanır. Projenin diğer kaynakları değişmez.

```sh
node pages/build.mjs
node pages/check.mjs
```

Metinler `pages/content.json`, tasarım `pages/assets/site.css`. Yerel görseller `pages/assets/`. Eski support/privacy adresleri tam sayfa takma yollarıyla korunur. GitHub Pages kaynağı GitHub Actions olmalı; `.github/workflows/pages.yml` main dalında üretip doğrular ve yayımlar.

Canlı: https://aozkul.github.io/PayGuard/ · support/ · privacy/ · en/ · de/

Site hesap/analitik/izleme/harici font içermez. Uygulamanın veri davranışı kendi gizlilik metniyle açıklanır. Orijinal politika kaynakları depo kökünde ve git geçmişinde korunur. Yeni özellik veya fiyat varsayımı ekleme.
