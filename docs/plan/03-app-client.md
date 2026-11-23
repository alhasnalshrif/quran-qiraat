# 03. جانب التطبيق (Flutter)

ينفّذ عقد `01-update-protocol.md` داخل التطبيق الحالي. الكود اليوم يقرأ كل البيانات من `rootBundle` مباشرة في `QuranRepository.load()` و`MushafLayoutRepository` و`QuranNavigationIndex.hizbs()`. هذه الخطة تضع طبقة واحدة بينهم وبين الملفات، ولا تغيّر شيئًا في منطق القراءة أو العرض.

## 1. الحزم الجديدة (Dart packages)

| الحزمة | السبب |
|---|---|
| `http` | طلب البيان وتنزيل الملفات |
| `crypto` | sha256 |
| `cryptography` | التحقق من توقيع Ed25519 (يعمل على كل المنصات بما فيها الويب) |
| `path_provider` | مجلد دعم التطبيق لحفظ الحزم |
| `connectivity_plus` | خيار «Wi-Fi فقط» |
| `package_info_plus` | رقم البناء الحالي |

## 2. الملفات الجديدة

```
lib/
├── updates/
│   ├── protocol.dart          أنواع العقد: SignedManifest, Manifest, PackRelease, PackFile, Announcement, AppPolicy (fromJson فقط، بلا منطق)
│   ├── trusted_keys.dart      const trustedKeys = {'k1': '<base64>'}
│   ├── manifest_client.dart   طلب البيان، ETag، التحقق من التوقيع والصلاحية
│   ├── pack_store.dart        حفظ وتفعيل وسحب الحزم على القرص، وحالة كل حزمة
│   ├── pack_validators.dart   مدقق لكل صيغة (نفس قواعد 01 §1.2)
│   ├── data_source.dart       QuranDataSource: يعطي بايتات أي ملف حزمة من المفعّل أو المضمّن
│   ├── update_service.dart    ينسّق كل ما سبق، ويُشغَّل عند الفتح
│   └── remote_config.dart     قراءة المفاتيح بأنواعها وافتراضياتها (01 §4)
├── features/updates/
│   ├── updates_page.dart      شاشة «التحديثات والمصادر»
│   ├── force_update_page.dart
│   └── announcement_banner.dart
assets/packs_bundled.json      إصدارات الحزم المضمّنة (01 §1.3)
```

## 3. `QuranDataSource`: نقطة القراءة الوحيدة

```dart
abstract interface class QuranDataSource {
  /// يعيد نص ملف من حزمة، من الإصدار المفعّل إن وُجد وإلا المضمّن.
  Future<String> loadString(String packId, String path);
  Future<ByteData> load(String packId, String path);
  /// الإصدار المستخدم فعلًا لكل حزمة، للعرض في شاشة المصادر.
  Map<String, PackState> get states;
}
```

- `BundledDataSource`: يقرأ من `rootBundle` حسب `bundledPath` في جدول العقد §1.1. يُستخدم في الاختبارات وفي الويب (D9).
- `PackedDataSource`: يقرأ من القرص للحزم المفعّلة، ويرجع لـ `BundledDataSource` لأي حزمة غير مفعّلة.
- **التغيير في الكود الحالي** (مهمة A-04): كل `rootBundle.loadString('assets/…')` في `QuranRepository.load()` و`MushafLayoutRepository` و`QuranNavigationIndex.hizbs()` يُستبدل بـ `dataSource.loadString(packId, path)`. `QuranRepository.load({QuranDataSource? source})` يأخذ المصدر، وافتراضيه `BundledDataSource` حتى لا تنكسر الاختبارات.

## 4. التخزين على القرص

```
<ApplicationSupportDirectory>/packs/
├── state.json                     { "active": { "qiraat-farsh": 2 }, "previous": { "qiraat-farsh": 1 }, "pending": { … } }
├── qiraat-farsh/
│   ├── 1/ variants.json …
│   └── 2/ variants.json …
└── .incoming/                     تنزيلات جارية، تُحذف عند البدء إن وُجدت
```

- يُحتفظ بإصدارين على الأكثر لكل حزمة (المفعّل والسابق). الأقدم يُحذف بعد تفعيل الأحدث بنجاح.
- `state.json` يُكتب ذريًّا: كتابة ملف مؤقت ثم `rename`.

## 5. تسلسل التحديث

```
عند فتح التطبيق
 └─ PackStore.activatePending()        (D8: تفعيل ما نُزّل في الجلسة السابقة)
 └─ تحميل QuranRepository من PackedDataSource
     └─ فشل تحميل حزمة مفعّلة؟ → تعطيلها، الرجوع للسابقة ثم المضمّنة، إعادة التحميل، تسجيل السبب في state.json
 └─ بعد ظهور أول صفحة، في الخلفية: UpdateService.check()
     1. لم يمر updates.checkIntervalHours منذ آخر فحص؟ → توقف (إلا إذا كان يدويًا)
     2. GET /v1/manifest مع If-None-Match (فقط إن كان البيان المحفوظ لم تنتهِ صلاحيته) → 304؟ استخدم المحفوظ وتوقف
     3. تحقق: keyId موثوق، التوقيع، protocol == 1، expiresAt لم ينتهِ → وإلا تجاهل البيان كله
     4. حفظ config والإعلانات وسياسة النسخة (تُستخدم فورًا)
     5. revoked يشمل إصدارًا مفعّلًا؟ → تعطيله فورًا، وطلب إعادة تحميل البيانات
     6. لكل حزمة: version > المفعّل والمضمّن؟ وكانت الصيغة مدعومة؟ → أضفها لقائمة التنزيل
     7. «Wi-Fi فقط» مفعّل والشبكة ليست Wi-Fi؟ → توقف (تبقى القائمة للمرة القادمة)
     8. لكل ملف: تنزيل إلى .incoming، مطابقة size وsha256 → خطأ؟ حذف وتوقف لهذه الحزمة
     9. تشغيل مدقق الصيغة على الملفات → خطأ؟ حذف وتوقف
    10. نقل المجلد إلى packs/<id>/<version>/ وتسجيله في pending
    11. إن كان الفحص يدويًا وضغط المستخدم «تطبيق الآن»: activatePending() وإعادة تحميل QuranRepository دون إعادة تشغيل التطبيق
```

- لا تنزيل متوازٍ لأكثر من ملفين.
- أي استثناء في أي خطوة يُلتقط، يُسجَّل في `state.json` (`lastError`)، ولا يصل للمستخدم إلا في شاشة التحديثات.
- إعادة تحميل البيانات: `QuranBootstrap` يعيد إنشاء الجلسة (`loadQuranSession`) بنفس المصدر، ويحتفظ بموضع القراءة الحالي.

## 6. سياسة النسخة والإعلانات

- `build < app.minSupportedBuild`: `ForceUpdatePage` تغطي التطبيق كله، فيها رسالة `app.message` وزر يفتح `storeUrl`. على الويب: زر «إعادة التحميل».
- `build < app.latestBuild` فقط: شريط صغير قابل للإغلاق مرة لكل `latestBuild`.
- الإعلانات: `AnnouncementBanner` فوق الصفحة عند ظهور أدوات القراءة فقط، إعلان واحد في المرة (الأعلى أولوية ثم الأحدث)، ويُحفظ معرّفه بعد الإغلاق في `SharedPreferences` (`dismissed_announcements`) فلا يتكرر. يحترم `features.announcements`.
- لا يُعرض إعلان أو تحديث فوق نافذة مفتوحة (شيت المقارنة مثلًا).

## 7. شاشة «التحديثات والمصادر»

تحل محل شاشة «المصادر وحالة المراجعة» الحالية (`reading_text_comparison_page.dart`) وتُفتح من نفس المكانين (المكتبة والمقارنة). تحتوي:

1. لكل حزمة: الاسم العربي، الإصدار المستخدم (مضمّن/منزّل)، المصدر ورقم نسخته، تاريخ آخر تحديث.
2. آخر فحص ونتيجته، وزر «البحث عن تحديثات» ثم «تطبيق الآن» عند وجود تنزيل جاهز.
3. خيار «التنزيل عبر Wi-Fi فقط».
4. رقم النسخة ورقم البناء. الضغط عليه 7 مرات يُظهر اختيار القناة (`stable`/`beta`)، يُحفظ في `SharedPreferences` (`update_channel`).
5. «الرجوع للبيانات الأصلية»: يعطّل كل الحزم المنزّلة ويعود للمضمّن.

## 8. الويب (D9)

- في المرحلة 1: الويب يستخدم `BundledDataSource` فقط، ويطلب البيان لسياسة النسخة والإعلانات والإعدادات.
- تحديث حزم الويب يتم بنشر نسخة ويب جديدة (`tool/build_web.mjs`) كما اليوم.
- مهمة لاحقة (A-10): حفظ الحزم في Cache Storage تحت مفتاح الرابط، بنفس التحقق.

## 9. الاختبارات

| ما يُختبر | كيف |
|---|---|
| تحليل البيان والتحقق من التوقيع | بيانات ثابتة موقّعة بمفتاح اختبار (المفتاح العام للاختبار فقط في `test/`)؛ حالات: سليم، توقيع خاطئ، keyId مجهول، منتهي، protocol مختلف |
| `PackStore` | مجلد مؤقت: تنزيل، sha256 خاطئ، مدقق يفشل، تفعيل، سحب، الرجوع للسابق، بقاء إصدارين فقط، `state.json` بعد انقطاع في منتصف الكتابة |
| `QuranDataSource` | الرجوع للمضمّن لكل حزمة غير مفعّلة؛ حزمة تالفة تُعطَّل ويُعاد التحميل |
| `UpdateService` | `http` وهمي: 304، خطأ شبكة، Wi-Fi فقط، فحص يدوي مقابل تلقائي، احترام `checkIntervalHours` |
| الواجهة | شاشة التحديث الإجباري، الشريط، الإعلان لا يتكرر بعد الإغلاق، شاشة المصادر |
| بلا انحدار | كل الاختبارات الحالية (92) تمر مع `BundledDataSource` دون تعديل منطقها |
