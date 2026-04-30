# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **full-stack** bookkeeping app (记账本) consisting of:
- **Frontend**: Flutter mobile app (Android only)
- **Backend**: Python FastAPI + MySQL (hosted at `YOUR_SERVER_IP:3306`)

## Build, Test, and Lint Commands

### Flutter Frontend

| Command | Purpose |
|---|---|
| `flutter pub get` | Install dependencies |
| `flutter run` | Run the app in debug mode on the default device |
| `flutter test` | Run all tests |
| `flutter test test/widget_test.dart` | Run a specific test file |
| `flutter analyze` | Run static analysis |
| `dart format .` | Format all Dart code |
| `dart run scripts/build_apk.dart` | Build Android APK with auto IP injection + restore |
| `flutter build apk` | Build Android APK (manual, ensure XML IP is correct) |
| `flutter build appbundle` | Build Android App Bundle |
| `dart run flutter_launcher_icons` | Regenerate Android launcher icons from `assets/icon/icon.png` (must be run manually after the icon is changed; not invoked automatically by `flutter build`) |

### FastAPI Backend

| Command | Purpose |
|---|---|
| `cd backend && python -m venv venv` | Create virtual environment |
| `venv\Scripts\activate` (Win) / `source venv/bin/activate` (Unix) | Activate venv |
| `pip install -r requirements.txt` | Install Python dependencies |
| `uvicorn main:app --reload --port 8000` | Run dev server |
| `python main.py` | Run via `if __name__ == "__main__"` (port 5300) |

## Architecture

### Frontend (`lib/`)

```
lib/
├── main.dart              # App entry point, theme config
├── config/
│   ├── api_config.dart         # Backend URL config (gitignored, copy from template)
│   └── api_config.template.dart # Template for users to set up their own backend
├── models/
│   ├── category.dart      # Category data model
│   └── transaction.dart   # Transaction data model
├── pages/
│   ├── home_page.dart     # Today's expense/income list with date filter
│   ├── login_page.dart    # Login / profile view
│   ├── navigate_page.dart # Main scaffold with drawer + page switching
│   ├── register_page.dart # User registration
│   └── statistics_page.dart # Charts: summary, pie chart, bar chart
├── services/
│   ├── api_service.dart   # Dio HTTP client, all backend APIs
│   ├── auth_service.dart  # Singleton: token persistence, login/logout
│   ├── storage_service.dart # SharedPreferences CRUD, daily auto-cleanup
│   └── sync_service.dart  # Local-to-backend batch sync on login (mutex-protected)
├── utils/
│   ├── text_parser.dart   # Natural language parsing: amount, type, category, note
│   ├── icon_utils.dart    # Backend icon name -> MaterialIcons codePoint
│   └── toast_utils.dart   # showCenterToast() overlay helper
└── widgets/
    ├── add_record_sheet.dart   # Bottom sheet for adding/editing transactions
    └── transaction_card.dart   # Individual transaction list item
```

### Backend (`backend/`)

```
backend/
├── main.py              # Single-file FastAPI app: models, schemas, auth, CRUD, stats
├── requirements.txt     # Python dependencies
└── .env                 # Local env vars (ignored by git)
```

Backend is a monolithic `main.py` using synchronous SQLAlchemy with MySQL (`mysql+pymysql`).

Key backend features:
- **Token expiration**: JWT access tokens expire after **7 days** (`ACCESS_TOKEN_EXPIRE_MINUTES = 10080`), reducing re-authentication frequency for mobile users
- **Startup MD5 checksum**: On every startup, the backend computes and prints the first 8 chars of `main.py`'s MD5 digest, enabling operators to verify code updates via `docker logs`
- **Docker volume mount**: `docker-compose.yml` mounts `./main.py` as read-only into the container, so code changes take effect on restart without rebuilding the image. `PYTHONDONTWRITEBYTECODE=1` prevents stale `.pyc` caches

### API Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/` | Health check + DB version |
| POST | `/token` | OAuth2 login (form-data username/password) |
| POST | `/users/` | Register new user (auto-creates default categories) |
| GET | `/users/me/` | Get current user profile |
| GET | `/categories/` | List categories (with JWT auth, optional type filter) |
| POST | `/categories/` | Create a new category |
| GET | `/transactions/` | List transactions (supports skip/limit/type/category_id/date filters) |
| POST | `/transactions/` | Create a transaction |
| GET | `/transactions/{id}` | Get single transaction |
| PUT | `/transactions/{id}` | Update transaction |
| DELETE | `/transactions/{id}` | Delete transaction |
| GET | `/summary/` | Financial summary (income/expense/balance + MoM change) |
| GET | `/category-stats/` | Expense breakdown by category (labels/values/colors/amounts) |
| GET | `/trends/` | Income/expense trends over time (day/month/quarter/year) |

### State Management

UI authentication state is managed via `AuthService` (singleton `ChangeNotifier`).
- `main.dart` awaits `AuthService.instance.initialize()` before `runApp`
- Pages listen to `AuthService.instance` via `addListener`/`removeListener`
- `ApiService` registers `onUnauthorized` callback for automatic logout on 401

### Data Flow

- `HomePage` loads from `ApiService.getTransactions()` when logged in, or `StorageService.loadTodayItems()` when offline.
- Adding a record: if logged in -> API create -> refresh list; if offline -> local storage -> refresh list.
- **Smart input**: `AddRecordSheet` includes a "Smart Recognition" text field. After 1s debounce, `TextParser.parse()` extracts amount, income/expense type, category, and note from natural language (e.g., "打车26", "工资8500"). Uses priority-ranked regex pipeline with negation filtering.
- `SyncService.syncLocalToBackend()` is called on login to upload offline records, then clears local cache. Uses a `Completer`-based mutex to prevent concurrent sync executions and duplicate uploads.
- `StorageService` persists JSON to `SharedPreferences` under `menu_items_today` and auto-clears when the date changes.

### Assets

Images are in `assets/images/` (e.g., `me.png`, `record.png`, `login.png`, `analyse.png`).
Register new assets in both `pubspec.yaml` and reference with `AssetImage('assets/images/xxx.png')`.

### Lint Configuration

`analysis_options.yaml` extends `package:flutter_lints/flutter.yaml` but explicitly disables `prefer_const_constructors`, `prefer_final_fields`, `use_key_in_widget_constructors`, `prefer_const_literals_to_create_immutables`, `prefer_const_constructors_in_immutables`, and `avoid_print`. Do not add `const` keywords or widget `Key` parameters unless requested.

### Dependencies

#### Flutter
- `dio` — HTTP client
- `shared_preferences` — Local key-value storage
- `provider` — State management framework
- `collection` — `firstWhereOrNull` utility

#### Python
- `fastapi` — Web framework
- `uvicorn` — ASGI server
- `sqlalchemy` — ORM
- `passlib[bcrypt]` — Password hashing
- `python-jose[cryptography]` — JWT handling
- `python-multipart` — OAuth2 form parsing
- `pymysql` — MySQL driver
- `python-dotenv` — Environment variable loading
- `cryptography` — Required by python-jose

### Testing

Tests are in `test/widget_test.dart`. After refactoring, the tests verify the app renders the home page title and that the navigation drawer opens correctly.

### Platform Notes

- The app is configured for Android only. Other platform directories were removed.
- `SystemChrome.setSystemUIOverlayStyle` is called in `main()` to configure the status bar.
- `ApiService` auto-detects Android emulator (`10.0.2.2`) vs production URL to minimize connection wait time.
- **Backend URL configuration**: Production and emulator URLs are defined in `lib/config/api_config.dart` (gitignored). New developers should copy `api_config.template.dart` to `api_config.dart` and fill in their own server address.
- **Build automation**: `scripts/build_apk.dart` wraps `flutter build apk` and automatically injects the real server IP from `api_config.dart` into `network_security_config.xml` before building, then restores the `YOUR_SERVER_IP` placeholder afterward. This prevents accidental IP leaks in Git while ensuring the APK works on ColorOS/MIUI.
- **Network security for domestic ROMs**: `AndroidManifest.xml` sets `usesCleartextTraffic="true"` and references `network_security_config.xml`, which explicitly whitelists the production server, `10.0.2.2`, and `localhost` for cleartext traffic. This is necessary because ColorOS, MIUI, and other domestic OEM ROMs may ignore or override the global cleartext flag. The config also includes `debug-overrides` for packet capture tools.
