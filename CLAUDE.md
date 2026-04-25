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
| `flutter build apk` | Build Android APK |
| `flutter build appbundle` | Build Android App Bundle |

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
│   └── sync_service.dart  # Local-to-backend batch sync on login
├── utils/
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

Backend is a monolithic `main.py` using synchronous SQLAlchemy with MySQL (`mysql+pymysql`), with SQLite fallback for local development.

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
- `SyncService.syncLocalToBackend()` is called on login to upload offline records, then clears local cache.
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
