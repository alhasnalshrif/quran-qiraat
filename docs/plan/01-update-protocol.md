# 01. عقد التحديثات (Update Protocol)

إصدار العقد: **`protocol 1`**. هذا الملف يحدد بالضبط ما يرسله السيرفر وما يفهمه التطبيق. السيرفر (`02-server.md`) والتطبيق (`03-app-client.md`) ينفّذان هذا العقد ولا يضيفان عليه. الأنواع نفسها مكتوبة كمخطط zod في `packages/contracts` (مهمة S-02)، ونسخة Dart منها في التطبيق (مهمة A-02).

**أمثلة مشتركة:** `packages/contracts/fixtures/` فيها مثال البيان في §2.2 موقّعًا بمفتاح اختبار (`test-key.json`، للاختبارات فقط ولا يُثق به في أي بناء حقيقي)، ونسخة مكسورة من كل حالة رفض. اختبارات السيرفر (TypeScript) واختبارات التطبيق (Dart، بالمسار النسبي من جذر المستودع) تقرأ نفس الملفات، فلا يختلف الطرفان في فهم العقد.

## 1. الحزم (Packs)

### 1.1 قائمة الحزم المعتمدة

كل حزمة لها معرّف ثابت لا يتغير أبدًا، وصيغة، وملفات. المسار `bundledPath` هو مكان النسخة المضمّنة في التطبيق اليوم.

| `packId` | `format` | الملفات (`path` داخل الحزمة) | `bundledPath` | يقرؤها في التطبيق |
|---|---|---|---|---|
| `editions-manifest` | `editions-manifest@1` | `editions_manifest.json` | `assets/editions_manifest.json` | `QuranRepository.load` |
| `hafs-text` | `kfgqpc-ayahs@1` | `quran_hafs.json` | `assets/quran_hafs.json` | `QuranRepository.load` |
| `riwayah-shubah-text` | `kfgqpc-ayahs@1` | `quran_shubah.json` | `assets/quran_shubah.json` | `QuranRepository.load` |
| `riwayah-qalun-text` | `kfgqpc-ayahs@1` | `quran_qalun.json` | `assets/quran_qalun.json` | `QuranRepository.load` |
| `hafs-layout-1405` | `mushaf-layout@1` | `hafs_madani_604.json`، `manifest.json` | `assets/mushaf/layout/` | `MushafLayoutRepository` |
| `mapping-hafs-qalun` | `ayah-map@1` | `hafs_to_qalun.json` | `assets/mappings/hafs_to_qalun.json` | `QuranRepository.load` |
| `qiraat-farsh` | `qiraat-variants@1` | `variants.json`، `LICENSE-QuranTajweedEngine.txt` | `assets/qiraat/` | `QiraatVariants.parse` |
| `published-differences` | `published-differences@1` | `published_differences.json` | `assets/published_differences.json` | `parsePublishedDifferences` |
| `navigation-hizbs` | `hizb-starts@1` | `hafs_hizbs.json`، `LICENSE-QuranMeta.txt` | `assets/navigation/` | `QuranNavigationIndex.hizbs` |

حزم المراحل التالية (تُضاف لهذا الجدول عند تنفيذ مهامها؛ إضافة حزمة جديدة لا تغيّر رقم العقد):
`riwayah-warsh-text`، `riwayah-bazzi-text`، `riwayah-qunbul-text`، `riwayah-duri-text`، `riwayah-susi-text` بصيغة `qiraat-ayahs@1`؛ و`riwayah-pages` بصيغة `riwayah-pages@1`؛ و`hafs-layout-1441` بصيغة `mushaf-layout@1`؛ و`audio-catalog` بصيغة `audio-catalog@1`.

### 1.2 قواعد الصيغ

- الصيغة تُكتب `اسم@رقم`. الرقم يزيد فقط عند تغيير **غير متوافق** (حذف حقل، تغيير معنى). إضافة حقل اختياري لا ترفع الرقم.
- التطبيق يحمل قائمة الصيغ التي يقرؤها (`supportedFormats`) ويرسلها ضمنيًا عبر رقم البناء: السيرفر يعرف من جدول `pack_versions.min_app_build` أي بناء يقرأ أي إصدار.
- كل صيغة لها مدقق (validator) في `packages/contracts/formats/` يشغّله السيرفر عند الرفع، ونسخة مقابلة في التطبيق تشغَّل بعد التنزيل وقبل التفعيل. المدقق يتحقق من البنية والحد الأدنى من المعنى:

| الصيغة | ما يتحقق منه المدقق |
|---|---|
| `kfgqpc-ayahs@1` | مصفوفة؛ كل عنصر فيه `sura_no` (1–114)، `aya_no` ≥ 1، `aya_text` نص غير فارغ؛ لا تكرار لـ (سورة، آية)؛ عدد الآيات يطابق `totalAyahs` في `editions-manifest` |
| `mushaf-layout@1` | 604 صفحة؛ كل كلمة `location` بصيغة `س:آ:ك`؛ نفس فحوص `tool/import_mushaf_layout.mjs --check` |
| `qiraat-variants@1` | `readers` عشرة، `transmitters` عشرون، كل `junctures[].segments[].ayah` آية موجودة في حفص، و`words` إما `null` أو `[بداية، نهاية]` بأرقام كلمات موجودة في التخطيط |
| `published-differences@1` | نفس قواعد `parsePublishedDifferences` الحالية |
| `ayah-map@1`، `hizb-starts@1`، `editions-manifest@1` | نفس التحقق الموجود اليوم في `QuranRepository.load` و`QuranNavigationIndex.hizbs` |
| `qiraat-ayahs@1` (المرحلة 2) | `surahs` فيها 114 مفتاحًا؛ آيات كل سورة مرقّمة 1..n بلا فجوات؛ n يطابق `qiraat-counts.json` في المصدر للرواية؛ كل `text` غير فارغ |
| `riwayah-pages@1` (المرحلة 2) | لكل رواية: كل آية في نصها لها صفحة 1–604؛ الصفحات غير متناقصة بترتيب المصحف |
| `audio-catalog@1` (المرحلة 4) | يُكتب مع مهمة U-01 قبل تنفيذها |

### 1.3 إصدار الحزمة

- `version`: عدد صحيح، يبدأ من 1 لكل `packId`، ويزيد بواحد مع كل إصدار جديد. لا يُعاد استخدام رقم أبدًا، حتى بعد السحب.
- النسخة المضمّنة في التطبيق لها رقم إصدار مسجّل في `assets/packs_bundled.json` (مهمة A-03):

```json
{ "protocol": 1, "packs": { "qiraat-farsh": 1, "hafs-text": 1, "…": 1 } }
```

- التطبيق يستخدم إصدارًا منزّلًا فقط إذا كان **أكبر** من المضمّن.

## 2. البيان (Manifest)

### 2.1 الطلب

```
GET /v1/manifest?platform=ios&build=7&channel=stable&protocol=1
If-None-Match: "<etag من آخر رد>"
```

| المعامل | القيم | ملاحظات |
|---|---|---|
| `platform` | `ios`، `android` (D9) | إلزامي |
| `build` | عدد صحيح ≥ 1 | إلزامي |
| `channel` | `stable`، `beta`، `internal` | افتراضي `stable` |
| `protocol` | `1` | إلزامي. السيرفر يرد 400 لأي رقم لا يدعمه |

لا تُرسل أي ترويسة أو معامل آخر. لا كوكيز.

### 2.2 الرد

`200 OK`، `Content-Type: application/json`، `ETag`، `Cache-Control: public, max-age=300`. أو `304 Not Modified`.

الغلاف الموقّع:

```json
{
  "keyId": "k1",
  "payload": "<base64 لبايتات JSON البيان بترميز UTF-8>",
  "signature": "<base64 لتوقيع Ed25519 على بايتات payload بعد فك base64>"
}
```

التوقيع على البايتات نفسها، لا على JSON بعد إعادة ترتيبه. لا حاجة لـ canonicalization.

محتوى `payload` بعد فكه:

```json
{
  "protocol": 1,
  "issuedAt": "2026-11-23T10:00:00Z",
  "expiresAt": "2026-11-30T10:00:00Z",
  "channel": "stable",
  "app": {
    "latestBuild": 9,
    "minSupportedBuild": 5,
    "storeUrl": "https://apps.apple.com/app/id000000000",
    "message": { "ar": "نسخة جديدة فيها …" }
  },
  "packs": [
    {
      "packId": "qiraat-farsh",
      "version": 2,
      "format": "qiraat-variants@1",
      "source": { "name": "Quran Tajweed Engine", "revision": "edd7afc0…" },
      "notes": { "ar": "تصحيح مواضع …" },
      "files": [
        {
          "path": "variants.json",
          "url": "https://cdn.example.com/packs/qiraat-farsh/2/variants.json",
          "sha256": "9f2c…",
          "size": 426472
        }
      ]
    }
  ],
  "revoked": [ { "packId": "qiraat-farsh", "version": 1 } ],
  "config": { "updates.checkIntervalHours": 6 },
  "announcements": [
    {
      "id": "a-2026-11-23-1",
      "title": { "ar": "…" },
      "body": { "ar": "…" },
      "url": null,
      "startsAt": "2026-11-23T00:00:00Z",
      "endsAt": "2026-12-01T00:00:00Z",
      "priority": "normal"
    }
  ]
}
```

قواعد الحقول:

- `packs` تحتوي فقط أحدث إصدار منشور لكل حزمة في هذه القناة **يقرؤه هذا البناء** (`min_app_build ≤ build`). حزمة غير مذكورة = لا جديد لها.
- `revoked`: إصدارات سُحبت. التطبيق الذي فعّل واحدًا منها يرجع فورًا للإصدار السابق السليم عنده أو للمضمّن.
- `expiresAt`: بعده لا يُعتمد هذا البيان لتنزيل حزم جديدة (يمنع إعادة تشغيل بيان قديم). أقصى مدة 7 أيام.
- `app.minSupportedBuild`: إذا كان `build` أقل منه، يعرض التطبيق شاشة التحديث الإجباري (انظر `03-app-client.md` §6).
- `config`: مفاتيح وقيم من القائمة المعتمدة في §4 فقط. أي مفتاح غير معروف يُتجاهل.
- النصوص المعروضة للمستخدم كائنات لغوية `{ "ar": "…" }`. العربية إلزامية.

### 2.3 الأخطاء

كل خطأ من أي طريق:

```json
{ "error": { "code": "unsupported_protocol", "message": "…" } }
```

| الحالة | `code` |
|---|---|
| 400 | `invalid_request`، `unsupported_protocol` |
| 404 | `not_found` |
| 429 | `rate_limited` |
| 500 | `internal` |

التطبيق يتعامل مع أي خطأ أو انقطاع بنفس الطريقة: لا تغيير، ومحاولة في الموعد التالي.

## 3. التوقيع والمفاتيح

- الخوارزمية: Ed25519.
- التطبيق يحمل `trustedKeys` في الكود: `{ "k1": "<base64 public key>" }`.
- التدوير: يُضاف مفتاح `k2` للتطبيق في نسخة متجر، وبعد انتشارها يبدأ السيرفر التوقيع بـ `k2`، ثم يُحذف `k1` من النسخة التالية.
- البيان بـ `keyId` غير موثوق أو توقيع خاطئ أو `protocol` مختلف أو `expiresAt` منتهٍ: يُرفض بالكامل.
- الملفات نفسها غير موقّعة منفردة: سلامتها من `sha256` الموجود داخل البيان الموقّع.
- مفتاح الاختبار في `packages/contracts/fixtures/test-key.json` معرّفه `test`، ولا يوضع في `trustedKeys` لأي بناء يُنشر.

## 4. مفاتيح الإعدادات البعيدة المعتمدة

| المفتاح | النوع | الافتراضي في التطبيق | المعنى |
|---|---|---|---|
| `updates.checkIntervalHours` | int (1–168) | 6 | أقل مدة بين فحصين تلقائيين |
| `updates.wifiOnlyDefault` | bool | true | الافتراضي لخيار «التنزيل عبر Wi-Fi فقط» |
| `features.audio` | bool | true | إظهار زر التلاوة |
| `features.announcements` | bool | true | إظهار الإعلانات |
| `audio.reciters` | list | القائمة المضمّنة الحالية | قائمة القرّاء وروابطهم (المرحلة 3) |

إضافة مفتاح جديد: يُضاف هنا أولًا بنوعه وافتراضيه، ثم في الكود.

## 5. التوافق والترقية

| التغيير | ما يحدث |
|---|---|
| إصدار حزمة جديد بنفس الصيغة | يُنشر عاديًا لكل البناءات |
| صيغة جديدة غير متوافقة (`@2`) | يُرفع بـ `min_app_build` = أول بناء يقرأ `@2`. البناءات الأقدم تبقى على آخر `@1` |
| حزمة جديدة تمامًا | البناءات التي لا تعرفها لا تراها (تُرشَّح بـ `min_app_build`) |
| تغيير شكل البيان نفسه | `protocol 2`، والسيرفر يخدم 1 و2 معًا حتى يختفي `1` من الاستخدام |
