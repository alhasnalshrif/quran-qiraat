# 02. السيرفر ولوحة التحكم

ينفّذ عقد `01-update-protocol.md`. التقنيات: **Hono** و**Drizzle ORM** و**PostgreSQL** للسيرفر، و**React** و**Ant Design** للوحة. القرارات المرقّمة (D1…) في `README.md`.

## 1. هيكل المستودع

السيرفر واللوحة داخل نفس المستودع بجانب تطبيق Flutter، كـ pnpm workspace من الجذر:

```
quran/
├── pnpm-workspace.yaml          packages: [server, admin, packages/*]
├── package.json                 سكربتات الجذر فقط (lint, test, build)
├── packages/
│   └── contracts/               عقد البيان والحزم (zod) + مدققات الصيغ
│       ├── src/manifest.ts
│       ├── src/formats/*.ts     مدقق لكل صيغة في 01 §1.2
│       ├── src/config-keys.ts   مفاتيح 01 §4
│       └── test/
├── server/
│   ├── src/
│   │   ├── index.ts             تشغيل @hono/node-server
│   │   ├── app.ts               إنشاء Hono وتركيب الطرق
│   │   ├── env.ts               قراءة متغيرات البيئة والتحقق منها بـ zod
│   │   ├── db/schema.ts         جداول Drizzle (§3)
│   │   ├── db/client.ts
│   │   ├── routes/public.ts     /v1/*
│   │   ├── routes/admin/*.ts    /admin/api/*
│   │   ├── services/manifest.ts بناء البيان وتوقيعه
│   │   ├── services/storage.ts  S3/R2
│   │   ├── services/auth.ts     الجلسات وكلمات المرور
│   │   ├── services/onesignal.ts إرسال وإلغاء الإشعارات (D18)
│   │   └── middleware/          أخطاء، rate limit، auth، logging
│   ├── drizzle/                 ملفات الترحيل (drizzle-kit)
│   ├── test/
│   └── Dockerfile
├── admin/
│   ├── src/
│   │   ├── main.tsx             ConfigProvider: direction="rtl", locale=ar_EG
│   │   ├── api/                 عميل fetch + TanStack Query
│   │   ├── pages/               §6
│   │   └── components/
│   └── vite.config.ts
├── tool/publish_pack.mjs        CLI لرفع حزمة من المصدر (§7)
└── deploy/
    ├── docker-compose.yml       الإنتاج: server + postgres + caddy
    ├── docker-compose.dev.yml   التطوير: postgres + minio
    └── Caddyfile
```

النسخ المثبّتة (تُحدَّث بقرار فقط): Node 22، TypeScript 5 بإعداد `strict`، Hono 4، Drizzle ORM + drizzle-kit (آخر مستقر عند البدء)، zod 3، React 19، Ant Design 5، Vite 6، TanStack Query 5، react-router 7، Vitest للاختبارات.

## 2. متغيرات البيئة

تُقرأ في `server/src/env.ts` ويُرفض التشغيل إذا نقص أي إلزامي.

| المتغير | إلزامي | مثال | المعنى |
|---|---|---|---|
| `DATABASE_URL` | نعم | `postgres://quran:…@db:5432/quran` | |
| `PORT` | لا | `8787` | |
| `PUBLIC_BASE_URL` | نعم | `https://api.example.com` | |
| `CDN_BASE_URL` | نعم | `https://cdn.example.com` | بادئة روابط ملفات الحزم في البيان |
| `S3_ENDPOINT`، `S3_REGION`، `S3_BUCKET`، `S3_ACCESS_KEY_ID`، `S3_SECRET_ACCESS_KEY` | نعم | | تخزين الحزم (D4) |
| `MANIFEST_SIGNING_KEY` | نعم | base64 لمفتاح Ed25519 خاص (32 بايت seed) | D7 |
| `MANIFEST_KEY_ID` | نعم | `k1` | |
| `MANIFEST_TTL_DAYS` | لا | `7` | لحساب `expiresAt` (≤ 7) |
| `SESSION_SECRET` | نعم | 32 بايت عشوائية base64 | توقيع كوكي الجلسة |
| `ADMIN_ORIGIN` | نعم | `https://api.example.com` | لفحص CSRF |
| `LOG_LEVEL` | لا | `info` | |
| `ONESIGNAL_APP_ID_STABLE`، `ONESIGNAL_APP_ID_BETA` | نعم | | تطبيق OneSignal لكل قناة (D18) |
| `ONESIGNAL_REST_API_KEY_STABLE`، `ONESIGNAL_REST_API_KEY_BETA` | نعم | | مفاتيح سرية، على السيرفر فقط |

ملف `server/.env.example` بالقيم الوهمية يُرفع، و`.env` الحقيقي لا يُرفع أبدًا (يُضاف لـ `.gitignore`).

## 3. قاعدة البيانات (Drizzle)

كل جدول له `created_at` و`updated_at` (timestamptz). المفاتيح بأنواعها:

### `packs`
| العمود | النوع | قيود |
|---|---|---|
| `id` | text | PK، نفس `packId` في العقد (`^[a-z0-9-]+$`) |
| `title_ar` | text | not null |
| `description_ar` | text | |
| `format_family` | text | not null، مثل `qiraat-variants` |

### `pack_versions`
| العمود | النوع | قيود |
|---|---|---|
| `id` | uuid | PK |
| `pack_id` | text | FK → packs.id |
| `version` | integer | not null، unique مع `pack_id` |
| `format` | text | not null، مثل `qiraat-variants@1` |
| `min_app_build` | integer | not null، افتراضي 1 |
| `status` | enum | `draft` (أُنشئ)، `validated` (نجح التحقق)، `published` (أُطلق في قناة واحدة على الأقل)، `revoked` (سُحب). الانتقالات المسموحة فقط: draft→validated→published→revoked، وvalidated→revoked |
| `source_name`، `source_revision` | text | |
| `notes_ar` | text | |
| `created_by` | uuid | FK → admin_users.id |

### `pack_files`
| العمود | النوع | قيود |
|---|---|---|
| `pack_version_id` | uuid | FK، جزء من PK |
| `path` | text | جزء من PK، بلا `..` ولا `/` في البداية |
| `object_key` | text | `packs/<packId>/<version>/<path>` |
| `sha256` | text | 64 hex |
| `size` | bigint | |

### `channel_releases`
| العمود | النوع | قيود |
|---|---|---|
| `channel` | enum | `stable`، `beta`، `internal` |
| `pack_version_id` | uuid | FK |
| `released_at` | timestamptz | |
| PK | | (`channel`، `pack_version_id`) |

الإصدار «الحالي» لحزمة في قناة = أكبر `version` لها في `channel_releases` بحالة `published` ويحقق `min_app_build ≤ build`.

### `app_platforms`
| العمود | النوع |
|---|---|
| `platform` | enum (PK): ios, android, web, macos, windows, linux |
| `latest_build`، `min_supported_build` | integer |
| `store_url` | text |
| `message_ar` | text |

### `remote_config`
| العمود | النوع | قيود |
|---|---|---|
| `key` | text | من القائمة في العقد §4 فقط (يُتحقق في الكود) |
| `channel` | enum | |
| `platform` | enum أو null | null = كل المنصات |
| `min_build`، `max_build` | integer أو null | |
| `value` | jsonb | يُتحقق من نوعه حسب المفتاح |

### `announcements`
`id` (text، مثل `a-2026-11-23-1`)، `title_ar`، `body_ar`، `url`، `channel`، `platform` (nullable)، `starts_at`، `ends_at`، `priority` (`normal`/`high`)، `published` (bool).

### `admin_users`
`id` uuid، `email` unique، `password_hash` (argon2id)، `role` (`owner`/`editor`)، `disabled` bool، `last_login_at`.

### `admin_sessions`
`id` (رمز عشوائي 32 بايت، يُخزَّن hash له فقط)، `user_id`، `expires_at` (14 يوم)، `created_ip_hash`.

### `notifications`
| العمود | النوع | قيود |
|---|---|---|
| `id` | uuid | PK |
| `channel` | enum | `stable` أو `beta` (لا إشعارات لـ internal) |
| `title_ar`، `body_ar` | text | not null، العنوان ≤ 60 حرفًا والنص ≤ 180 |
| `link` | text | رابط داخلي من قائمة 03 §12 فقط، أو null |
| `target_platforms` | text[] | فرعية من `ios`، `android` |
| `target_min_build`، `target_max_build` | integer أو null | تُترجم لفلاتر وسم `build` |
| `scheduled_at` | timestamptz أو null | null = فورًا |
| `status` | enum | `draft`، `scheduled`، `sent`، `failed`، `cancelled` |
| `onesignal_id` | text | معرّف الإرسال من OneSignal |
| `recipients` | integer | العدد الذي يعيده OneSignal |
| `error` | text | |
| `created_by` | uuid | FK |

### `audit_log`
`id`، `user_id`، `action` (مثل `pack_version.publish`)، `target` (text)، `details` (jsonb)، `at`.

الترحيل: `pnpm --filter server db:generate` ثم `db:migrate`. لا تعديل يدوي على قاعدة الإنتاج.

## 4. الطرق العامة `/v1`

كما في العقد §2 بالضبط. تفاصيل التنفيذ:

- `services/onesignal.ts` يغلّف OneSignal REST API (إرسال، إلغاء)، ويختار مفتاح القناة. لا يُستدعى إلا من طرق الإشعارات.
- `services/manifest.ts` يبني البيان من: `channel_releases` + `pack_files` + `app_platforms` + `remote_config` + `announcements` الفعّالة الآن، ثم يوقّعه.
- `packs` في البيان: لكل حزمة، أكبر إصدار حالته `published` في هذه القناة و`min_app_build ≤ build`.
- `revoked` في البيان: كل الإصدارات بحالة `revoked` للحزم التي يقرؤها هذا البناء (بغض النظر عن القناة).
- **الكاش**: البيان يُبنى لكل (platform، build، channel) ويُحفظ في الذاكرة 60 ثانية. أي نشر من اللوحة يمسح الكاش. `ETag` = sha256 للـ payload.
- `GET /v1/packs/:packId/:version/*path` → 302 إلى `CDN_BASE_URL/packs/...`. (التطبيق يستخدم الرابط المباشر من البيان عادة؛ هذا احتياطي.)
- `GET /healthz` → 200 `{ "ok": true }` بعد فحص الاتصال بقاعدة البيانات.
- **Rate limit**: 60 طلبًا في الدقيقة لكل IP على `/v1`. يُحسب في الذاكرة (سيرفر واحد حسب D5).
- **السجلات**: لا يُحفظ IP كاملًا. يُسجَّل hash يومي متغير للـ IP لأغراض الـrate limit فقط، ويُحذف بعد 7 أيام.
- **CORS** على `/v1`: `*` للقراءة (للويب).

## 5. طرق اللوحة `/admin/api`

كلها تتطلب جلسة، عدا `POST /admin/api/login`. الطلبات التي تغيّر بيانات تتطلب ترويسة `X-CSRF-Token` المطابقة لقيمة في الجلسة، وتُسجَّل في `audit_log`.

| الطريقة | المسار | الصلاحية | الوظيفة |
|---|---|---|---|
| POST | `/login` | — | بريد + كلمة مرور → كوكي `qs_session` (httpOnly, Secure, SameSite=Strict) |
| POST | `/logout` | أي | |
| GET | `/me` | أي | |
| GET | `/packs` | أي | الحزم مع آخر إصدار في كل قناة |
| POST | `/packs` | owner | إنشاء حزمة جديدة (معرّف من قائمة العقد فقط) |
| GET | `/packs/:id/versions` | أي | |
| POST | `/packs/:id/versions` | editor | إنشاء إصدار `draft` برقم تالٍ تلقائيًا، وصيغة، ومصدر، وملاحظات |
| POST | `/pack-versions/:vid/files` | editor | يعيد رابط رفع موقّع (presigned PUT، صالح 15 دقيقة) لكل ملف بـ `path` و`sha256` و`size` المتوقعة |
| POST | `/pack-versions/:vid/validate` | editor | يقرأ الملفات من التخزين، يطابق sha256 والحجم، يشغّل مدقق الصيغة. ينجح → `validated` |
| POST | `/pack-versions/:vid/release` | editor للـbeta/internal، owner للـstable | `{ channel }`. يتطلب `validated` أو `published` |
| POST | `/pack-versions/:vid/revoke` | owner | → `revoked`، يُزال من كل القنوات |
| GET/PUT | `/platforms/:platform` | owner | أحدث بناء، أقل مدعوم، رابط المتجر، الرسالة |
| GET/POST/PUT/DELETE | `/config` | owner | |
| GET/POST/PUT/DELETE | `/announcements` | editor | |
| GET | `/audit` | owner | بترقيم صفحات |
| GET | `/notifications` | editor | السجل مع الحالة وعدد المستلمين |
| POST | `/notifications` | editor | إنشاء مسودة. يُتحقق من `link` مقابل قائمة 03 §12 |
| POST | `/notifications/:id/test` | editor | إرسال لجهاز اختبار واحد (معرّف اشتراك OneSignal يُدخل يدويًا، لا يُحفظ) |
| POST | `/notifications/:id/send` | owner لـ stable، editor لـ beta | إرسال فوري أو جدولة عبر OneSignal REST (`POST /notifications` بـ `filters` على وسوم `channel` و`platform` و`build`، و`data.link`). النتيجة تُحفظ في الجدول |
| POST | `/notifications/:id/cancel` | editor | إلغاء المجدول في OneSignal وقبل وقته فقط |
| GET/POST/PUT | `/users` | owner | إضافة editor، تعطيل حساب |

أول حساب `owner` يُنشأ بأمر CLI: `pnpm --filter server create-owner --email …` (يطلب كلمة المرور تفاعليًا). لا يوجد تسجيل ذاتي.

الحماية: argon2id لكلمات المرور، 5 محاولات دخول فاشلة في 15 دقيقة لكل بريد ثم انتظار، كلمة مرور ≥ 12 حرفًا.

## 6. لوحة التحكم (React + Ant Design)

كل الصفحات عربية RTL. التنقل بقائمة جانبية (`Layout.Sider`).

| الصفحة | المسار | المكونات الأساسية | ما تفعله |
|---|---|---|---|
| الدخول | `/login` | `Form` | |
| الرئيسية | `/` | `Statistic`، `Table` | أحدث إصدار لكل حزمة في كل قناة، وتنبيه إن كان stable أقدم من beta |
| الحزم | `/packs` | `Table` | قائمة الحزم |
| حزمة | `/packs/:id` | `Table` للإصدارات، `Tag` للحالة | |
| إصدار جديد | `/packs/:id/new` | `Steps`: البيانات ← رفع الملفات (`Upload` مع تقدم) ← التحقق ← النشر | يحسب sha256 في المتصفح قبل الرفع |
| تفاصيل إصدار | `/pack-versions/:vid` | `Descriptions`، أزرار نشر/سحب مع `Popconfirm` | |
| النسخ والمنصات | `/platforms` | `Form` لكل منصة | |
| الإعدادات البعيدة | `/config` | `Table` قابل للتعديل، القيمة بنوع المفتاح | المفاتيح من `packages/contracts` فقط |
| الإعلانات | `/announcements` | `Form` + معاينة بشكل بطاقة التطبيق + `DatePicker.RangePicker` | |
| المستخدمون | `/users` | `Table` | owner فقط |
| الإشعارات | `/notifications` | `Table` للسجل، و`Form` للإنشاء: عنوان ونص بعدّاد أحرف، `Select` للرابط الداخلي (صفحة/آية/التحديثات/إعلان) مع حقوله، المنصات، نطاق البناء، `DatePicker` للجدولة، ومعاينة بشكل إشعار الهاتف | إرسال تجريبي ثم إرسال مع `Popconfirm` يذكر القناة والجمهور |
| سجل التدقيق | `/audit` | `Table` بفلاتر | owner فقط |

اللوحة تُبنى ملفات ثابتة ويخدمها نفس سيرفر Hono على `/admin` (بلا CORS، نفس الأصل).

## 7. أداة نشر الحزم `tool/publish_pack.mjs`

```
node tool/publish_pack.mjs --pack qiraat-farsh --server https://api.example.com \
  --source-name "Quran Tajweed Engine" --source-revision <sha> --notes "…" \
  assets/qiraat/variants.json assets/qiraat/LICENSE-QuranTajweedEngine.txt
```

تسجّل الدخول (يطلب كلمة المرور)، تنشئ إصدارًا، ترفع الملفات، تشغّل التحقق، وتتوقف عند `validated`. النشر لقناة يتم من اللوحة فقط، عمدًا.

## 8. الاختبارات

| المستوى | الأداة | ما يُغطّى |
|---|---|---|
| contracts | Vitest | كل مدقق صيغة بحالات صحيحة وخاطئة؛ تطابق مخطط البيان مع مثال العقد |
| server | Vitest + PostgreSQL حقيقي (خدمة في CI) + MinIO + OneSignal وهمي (خادم HTTP محلي يسجل الطلبات) | بناء البيان لكل حالة في العقد §2 (ترشيح بـ build، السحب، القنوات، انتهاء الصلاحية)، التوقيع والتحقق منه، كل طريق في §5 مع الصلاحيات وCSRF |
| admin | Vitest + Testing Library | النماذج الأساسية، وتدفق رفع إصدار |
| تكامل | سكربت | سيرفر محلي + نشر حزمة + تطبيق Flutter في اختبار يقرأ البيان وينزّل ويتحقق (مهمة A-09) |

## 9. النشر (D5)

- `deploy/docker-compose.yml`: `server` (صورة من `server/Dockerfile` فيها اللوحة المبنية)، `postgres:16` بمجلد بيانات دائم، `caddy` لـ HTTPS تلقائي.
- النسخ الاحتياطي: `pg_dump` يومي إلى نفس R2 في مجلد `backups/`، والاحتفاظ 30 يومًا.
- CI (`.github/workflows/server.yml`): lint، typecheck، اختبارات contracts والسيرفر واللوحة، بناء الصورة. النشر عند tag `server-v*` فقط.
- المراقبة: `/healthz` يُفحص من خدمة خارجية مجانية كل 5 دقائق.

## 10. ما ليس في هذه المرحلة

حسابات للمستخدمين، مزامنة العلامات بين الأجهزة، إحصاءات استخدام. (الإشعارات صارت ضمن الخطة عبر OneSignal، D18.) أي منها يحتاج قرارًا جديدًا في سجل القرارات وقسمًا هنا قبل البدء.
