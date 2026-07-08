# BrenksChat — project instructions

Private messenger. This repo is a monorepo:

- `mobile/android-app/` — Flutter **Android client** (the main work target).
- `server/` — Node + TypeScript + socket.io backend (API `https://api.brenkschat.ru`, REST `/api/…`, Socket.IO `/socket.io/`).
- `client/` — web client (`https://brenkschat.ru`); **contract source of truth** for socket events / REST fields.
- `desktop/` — Flutter desktop client.

Unless told otherwise, work happens in `mobile/android-app/`. Other subdirs are read-only references for the API/socket contracts.

## Environment (machine-specific — adjust per device)

- Flutter is invoked via the local `flutter` binary (on the original dev machine: `C:\flutter\bin\flutter.bat`).
- The terminal may open in a different default directory and reset each command → always `cd` / `Set-Location` into `mobile/android-app` at the start of every shell command.
- Bundle id `ru.silentx.brenkschat_mobile`, `minSdk 23` (flutter_webrtc). **No Firebase.** AGP / Gradle / Kotlin versions are intentionally pinned — don't bump them (their build warnings are expected, not errors).

## Build & verify (per task — mandatory)

1. Edit Dart under `lib/` (read the file first, match neighbouring style).
2. `flutter analyze --no-fatal-infos <files>` → must print `No issues found!`.
3. `flutter build apk --debug` → can take ~1–10 min (native plugins). Run it in the background; Kotlin/Gradle/AGP *warnings* are not failures. Success = `√ Built build\app\outputs\flutter-apk\app-debug.apk`.
4. Reply in Russian, explain briefly, link the APK.

## Git

- Repo `github.com/roz1es/silentx.git`, branch **`mobile/android-app`** (never `main`, don't create new branches).
- Commit **only the specific changed `lib/` sources** by name. NEVER commit: `build/`, `node_modules/`, `.env` / secrets, `android/app/src/main/java/**/GeneratedPluginRegistrant.java`, or `android/app/build.gradle.kts` (unless deliberately changed). The APK is never committed.
- Commit messages in **Latin transliteration** (no Cyrillic), no double-quotes inside, ending with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- `git push` prints to stderr (PowerShell shows `NativeCommandError`) — that is **not** a failure; success is the `abc..def  mobile/android-app -> mobile/android-app` line.

## Server (`server/`)

- Don't touch without explicit per-task permission. Changes take effect **only after the user deploys** (`npm run build` + restart).
- No `node_modules` locally → can't `tsc`/test server code here; server edits are review-only (the user catches type errors on their build).
- Don't rename socket.io events or change REST field formats — the web `client/` is the contract source of truth.

## Design language

Graphite + gold ("стекло/золото" — glass + gold). Accent is **dynamic** (user-picked): presets Gold `#D8B76C` / Ruby `#CB5F6E` / Graphite `#9BA7B3` / Diamond `#7EC6DD`, plus a custom HSV picker (`lib/widgets/accent_picker.dart`). Replies to the user are in Russian.

## Theming (important gotcha)

- `accent` and companions (`softGold` / `goldDark` / `goldBorder` / `lightAccent`) in `lib/theme/app_theme.dart` are **top-level getters** from `AppSettings.instance.accentColor` — **not `const`**.
- **Therefore accent cannot be used in a `const` context** (`const Icon(color: accent)` → `invalid_constant`). `flutter analyze` catches it; fix by dropping the nearest `const`.
- Reactivity: the root `MaterialApp` is wrapped in `ListenableBuilder(AppSettings.instance)` in `lib/main.dart`; accent persists to SharedPreferences (`accent_id` / `accent_color`).
- A `CustomPainter` that depends on accent must take the color as a parameter and compare it in `shouldRepaint` (a `const CustomPaint` with `shouldRepaint => false` won't repaint on accent change).
- Theme switch = three chips Светлая / Тёмная / Система (`ThemeMode.system` supported). Settings screen (`_SettingsView` in `lib/screens/chat_list_screen.dart`) is a Telegram-style section list (Профиль / Оформление / Безопасность) via `_openSection`.

## Chat gestures

- Reply swipe is **LEFT only** (own + incoming). Double-tap a message = ❤️.
- **Right swipe exits the chat**, follows the finger, works anywhere — via the local fork `lib/widgets/swipe_back_route.dart` → `SwipeBackPageRoute` (not the `swipeable_page_route` package). Do **not** block back with `PopScope(canPop:false)` or switch the chat route to `MaterialPageRoute`.
- Gotcha: the swipe-return `AnimationController` must be created in `initState`, **not** as a lazy `late final` (a bubble disposed before it's ever swiped otherwise crashes with a red `RenderErrorBox`).

## Other traps

- Don't `showDialog` synchronously while a bottom sheet is closing (`_dependents.isEmpty` crash) — delay ~260 ms.
- Any `late final AnimationController` → create it in `initState`.
- Public profile / QR links go to `brenkschat.ru/u/<username>` (strip the `api.` prefix) via `lib/config.dart`.
- Local message notifications (no Firebase) via MethodChannel `brenks/notifications` — work only while the process/socket is alive; true push after process death needs FCM.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
