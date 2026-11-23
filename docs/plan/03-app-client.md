# 03. جانب التطبيق (Flutter)

ينفّذ عقد `01-update-protocol.md` داخل التطبيق الحالي. الكود اليوم يقرأ كل البيانات من `rootBundle` مباشرة في `QuranRepository.load()` و`MushafLayoutRepository` و`QuranNavigationIndex.hizbs()`. هذه الخطة تضع طبقة واحدة بينهم وبين الملفات، ولا تغيّر شيئًا في منطق القراءة أو العرض.

## 1. الحزم الجديدة (Dart packages)

| الحزمة | السبب |
|---|---|
| `flutter_riverpod` | إدارة الحالة (D16) |
| `dio` | طلب البيان وتنزيل الملفات مع التقدم والإلغاء (D17) |
| `onesignal_flutter` | الإشعارات البعيدة (D18) |
| `flutter_local_notifications` | تذكير الورد اليومي، يُضاف مع مهمة L-02 لا قبلها |
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
│   ├── providers.dart         كل Providers طبقة التحديثات (§10)
│   └── network.dart           dioProvider والـinterceptors (§11)
│   └── remote_config.dart     قراءة المفاتيح بأنواعها وافتراضياتها (01 §4)
├── features/updates/
│   ├── updates_page.dart      شاشة «التحديثات والمصادر»
│   ├── update_sheets.dart     شيتات التحديث الثلاثة (§6)
│   └── announcement_sheet.dart
├── notifications/
│   ├── notifications_service.dart  تهيئة OneSignal والإذن والوسوم وفتح الروابط (§12)
│   └── notification_consent_sheet.dart
├── app/deep_links.dart        تحليل الروابط الداخلية quranqiraat://…
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
    11. شيت «تحديث بيانات جاهز» (§6). «تطبيق الآن» منه أو من شاشة التحديثات: activatePending() وإعادة تحميل QuranRepository دون إعادة تشغيل التطبيق. غير ذلك: التفعيل عند الفتح التالي (D8)
```

- لا تنزيل متوازٍ لأكثر من ملفين.
- أي استثناء في أي خطوة يُلتقط، يُسجَّل في `state.json` (`lastError`)، ولا يصل للمستخدم إلا في شاشة التحديثات.
- إعادة تحميل البيانات: `ref.invalidate(quranRepositoryProvider)` (§10)، مع الاحتفاظ بموضع القراءة الحالي. بعد الخطوة 10 يُضاف شيت «تحديث بيانات جاهز» لطابور الشيتات (§6).

## 6. شيتات التحديث والإعلانات (D19)

كلها `showModalBottomSheet` بنفس شكل `QuranGlassSheet` الحالي، وعربية RTL. لا يظهر شيت فوق شيت أو نافذة مفتوحة: تُؤجَّل حتى تُغلق. شيت واحد في المرة، بالأولوية: إجباري ← بيانات جاهزة ← نسخة اختيارية ← إعلان.

| الشيت | متى | المحتوى | الإغلاق |
|---|---|---|---|
| **التحديث الإجباري** | `build < app.minSupportedBuild` | العنوان «يلزم تحديث التطبيق»، رسالة `app.message`، زر «فتح المتجر» (`storeUrl`)؛ على الويب «إعادة التحميل» | `isDismissible: false`، `enableDrag: false`، وزر الرجوع في Android لا يغلقه (`PopScope(canPop: false)`). يعود عند كل فتح حتى يُحدَّث |
| **نسخة جديدة اختيارية** | `build < app.latestBuild` | رسالة `app.message`، «تحديث» و«لاحقًا» | قابل للإغلاق. لا يعود لنفس `latestBuild` (يُحفظ `dismissed_latest_build`) |
| **تحديث بيانات جاهز** | اكتمل تنزيل حزمة أو أكثر (03 §5 خطوة 10) | اسم كل حزمة وملاحظاتها `notes.ar`، «تطبيق الآن» و«عند الفتح التالي» | قابل للإغلاق؛ الإغلاق = عند الفتح التالي (D8) |
| **إعلان** | إعلان فعّال لم يُغلق | العنوان والنص وزر الرابط إن وُجد | قابل للإغلاق، ويُحفظ معرّفه في `dismissed_announcements` فلا يتكرر. يحترم `features.announcements` |

الشيتات لا تظهر فوق صفحة المصحف أثناء التمرير بين الصفحات: تُعرض عند توقف المستخدم (أول ظهور لأدوات القراءة أو بعد 3 ثوانٍ بلا تمرير).

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
| `UpdateService` | `Dio` بـ adapter وهمي (override لـ `dioProvider`): 304، خطأ شبكة، Wi-Fi فقط، فحص يدوي مقابل تلقائي، احترام `checkIntervalHours` |
| الواجهة | الشيتات الأربعة وأولويتها؛ الإجباري لا يُغلق بالسحب ولا بزر الرجوع؛ الاختياري والإعلان لا يتكرران؛ شاشة المصادر |
| Riverpod | كل Provider في §10 يُختبر بـ `ProviderContainer` وoverrides لـ `dioProvider` و`packStoreProvider` |
| الإشعارات | الموافقة لا تُطلب قبل الشرط في §12؛ الرفض يُحفظ ولا يُعاد السؤال قبل 30 يومًا؛ كل رابط في §12 يفتح وجهته؛ رابط غير معروف يُتجاهل |
| بلا انحدار | كل الاختبارات الحالية (92) تمر مع `BundledDataSource` دون تعديل منطقها |

## 10. Riverpod (D16)

- `main.dart` يلف التطبيق بـ `ProviderScope`. `SharedPreferences` و`QuranRepository` يُقدَّمان كـ overrides بعد التحميل في `QuranBootstrap`.
- Providers طبقة التحديثات في `lib/updates/providers.dart`:

| Provider | النوع | يعطي |
|---|---|---|
| `dioProvider` | `Provider<Dio>` | نسخة Dio الوحيدة (§11) |
| `packStoreProvider` | `Provider<PackStore>` | |
| `dataSourceProvider` | `Provider<QuranDataSource>` | `PackedDataSource` على الأجهزة، `BundledDataSource` على الويب |
| `manifestProvider` | `AsyncNotifierProvider<ManifestNotifier, Manifest?>` | آخر بيان صالح، و`check({manual})` |
| `remoteConfigProvider` | `Provider<RemoteConfig>` | من البيان أو الافتراضيات |
| `appPolicyProvider` | `Provider<AppPolicy>` | إجباري/اختياري/لا شيء |
| `pendingPacksProvider` | `NotifierProvider<…, List<PackRelease>>` | حزم نُزّلت ولم تُفعَّل |
| `updateSheetQueueProvider` | `NotifierProvider<…, UpdateSheet?>` | الشيت التالي حسب الأولوية في §6 |
| `quranRepositoryProvider` | `AsyncNotifierProvider<…, QuranRepository>` | يُعاد تحميله عند «تطبيق الآن» |

- الواجهة تقرأ بـ `ref.watch` فقط. لا `setState` لحالة مشتركة في الكود الجديد.
- الاختبارات تستخدم `ProviderContainer(overrides: …)` بدل الشبكة والقرص الحقيقيين.

## 11. Dio (D17)

- `BaseOptions`: `connectTimeout` 10 ثوانٍ، `receiveTimeout` 30 ثانية للبيان و5 دقائق للملفات، `responseType` حسب الطلب، وترويسة `User-Agent: QuranQiraat/<version>+<build>` فقط.
- Interceptors بالترتيب: (1) إعادة المحاولة مرتين بفاصل 2 ثم 6 ثوانٍ لأخطاء الشبكة و5xx فقط، (2) تحويل الأخطاء إلى `UpdateError` بأنواع ثابتة (`offline`، `server`، `invalid`)، (3) سجل في وضع debug فقط.
- التنزيل: `dio.download` إلى `.incoming` مع `CancelToken` لكل حزمة، وتقدم يظهر في شاشة التحديثات. الإلغاء يحذف الملف الجزئي.
- `If-None-Match` يُضاف يدويًا لطلب البيان، و`validateStatus` يقبل 304.

## 12. الإشعارات: OneSignal (D18)

**التهيئة:** `OneSignal.initialize(<appId>)` عند الفتح، دون طلب إذن. `appId` ثابت غير سري في `lib/notifications/onesignal_config.dart` لكل قناة بناء.

**طلب الإذن:** لا يُطلب في أول فتح. يُعرض `notification_consent_sheet` (شرح: ماذا سيصل ولماذا، وأنه يمكن الإيقاف) بعد الجلسة الثالثة أو عند تفعيل الورد اليومي (L-02)، أيهما أسبق. «موافق» يستدعي `OneSignal.Notifications.requestPermission(true)`. «ليس الآن» يُحفظ ولا يُعاد قبل 30 يومًا. خيار في الإعدادات «الإشعارات» يشغّل ويوقف (`OneSignal.User.pushSubscription.optIn/optOut`).

**الوسوم:** فقط `channel`، `platform`، `build`، `lang` (D18). تُحدَّث عند كل فتح. لا `OneSignal.login` ولا أي معرّف خارجي.

**فتح الإشعار:** كل إشعار يحمل في `additionalData` حقل `link` برابط داخلي. `deep_links.dart` يحلله:

| الرابط | يفتح |
|---|---|
| `quranqiraat://page/<1-604>` | الصفحة في القارئ |
| `quranqiraat://ayah/<surah>/<ayah>` | الآية (بترقيم حفص) |
| `quranqiraat://updates` | شاشة التحديثات، ويبدأ فحصًا يدويًا |
| `quranqiraat://announcement/<id>` | شيت الإعلان |

رابط غير معروف أو غير صالح يُتجاهل ويفتح التطبيق عاديًا.

**الويب:** OneSignal Web SDK غير مستخدم في المرحلة الأولى؛ الويب بلا إشعارات.

**الإعداد المطلوب منك (N-01):** حساب OneSignal، تطبيق فيه، مفتاح APNs (.p8) من حساب Apple Developer، وملف Firebase (FCM) لأندرويد. التطبيق يحتاج Capability «Push Notifications» و«Background Modes: Remote notifications» في iOS، وNotification Service Extension لصور الإشعارات.
