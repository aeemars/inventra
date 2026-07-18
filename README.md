# Inventra — Shop Management System

A production-ready Flutter + Firebase mobile app for SMEs to manage products, stock, sales, barcode scanning, staff access, and business reporting.


## Tech Stack
- **Flutter** (Dart) — Cross-platform mobile
- **Firebase Auth** — Email/password authentication
- **Cloud Firestore** — Real-time database
- **Cloud Functions** — Server-side stock validation, analytics
- **Riverpod** — State management
- **GoRouter** — Declarative routing with bottom nav shell
- **Hive CE** — Offline-first local storage
- **Mobile Scanner** — Barcode/QR scanning
- **fl_chart** — Analytics charts

## Setup Instructions

### Prerequisites
- Flutter SDK >= 3.5.0
- Node.js >= 18 (for Cloud Functions)
- Firebase CLI (`npm install -g firebase-tools`)

### 1. Clone & Install Dependencies
```bash
cd inventra
flutter pub get
```

### 2. Configure Firebase
```bash
# Login to Firebase
firebase login

# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure your Firebase project
flutterfire configure
```

Note: `lib/firebase_options.dart` is intentionally gitignored in this project. Each developer should regenerate it locally by running `flutterfire configure`.

For this codebase, Firebase authentication is enabled when Firebase is initialized for the current platform:

1. Android/iOS/macOS/Windows:
- Add platform config files from Firebase console (google-services.json / GoogleService-Info.plist as applicable).
- `bootstrap.dart` initializes Firebase automatically for these targets.

2. Web (Chrome):
- Run with Firebase web values via dart-defines:
```bash
flutter run -d chrome \
  --dart-define=FIREBASE_WEB_API_KEY=your_api_key \
  --dart-define=FIREBASE_WEB_APP_ID=your_app_id \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=your_sender_id \
  --dart-define=FIREBASE_PROJECT_ID=your_project_id \
  --dart-define=FIREBASE_AUTH_DOMAIN=your_project.firebaseapp.com \
  --dart-define=FIREBASE_STORAGE_BUCKET=your_project.firebasestorage.app
```

If Firebase is not initialized, auth providers now fail gracefully and show an authentication-unavailable message instead of crashing.

### 3. Deploy Firestore Rules & Indexes
```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

### 4. Deploy Cloud Functions
```bash
cd functions
npm install
npm run build
cd ..
firebase deploy --only functions
```

### 5. Download Fonts (optional — Google Fonts loads them at runtime)
Download [Inter font](https://fonts.google.com/specimen/Inter) and place files in `assets/fonts/`.

### 6. Run the App
```bash
flutter run
```

### 7. Environment Template
Create your local env file from the template:
```bash
cp .env.example .env
```
Use values from Firebase console for your local setup.

## Project Architecture

```
lib/
├── main.dart                    # Entry point
├── bootstrap.dart               # Firebase/Hive initialization
├── app.dart                     # MaterialApp.router
├── core/
│   ├── constants/               # Colors, typography, sizes, Firestore paths
│   ├── errors/                  # Failures and exceptions
│   ├── extensions/              # Context and DateTime helpers
│   ├── network/                 # Connectivity service
│   ├── router/                  # GoRouter with ShellRoute
│   ├── theme/                   # Material 3 theme
│   ├── utils/                   # Validators, formatters, debouncer
│   └── widgets/                 # Reusable UI components
├── features/
│   ├── auth/                    # Login, register, forgot password
│   ├── dashboard/               # My Shop dashboard
│   ├── inventory/               # Products CRUD, categories
│   ├── scanner/                 # Barcode scanning flow
│   ├── sales/                   # Cart, checkout, transactions
│   └── analytics/               # Reporting with charts
├── shared/
│   ├── models/                  # StockMovement, SaleTransaction
│   └── providers/               # Firebase DI providers
└── firebase/                    # Generated Firebase config

functions/                       # Cloud Functions (TypeScript)
├── src/index.ts                 # Stock validation, alerts, analytics
firestore.rules                  # Security rules
firestore.indexes.json           # Composite indexes
```

## Firestore Collections
| Collection | Scope | Description |
|------------|-------|-------------|
| `users` | Global | User profiles with role and shop link |
| `shops` | Global | Shop profiles |
| `shops/{id}/products` | Shop | Product inventory |
| `shops/{id}/categories` | Shop | Product categories |
| `shops/{id}/transactions` | Shop | Sales records |
| `shops/{id}/stock_movements` | Shop | Audit trail for stock changes |
| `shops/{id}/scan_history` | Shop | Barcode scan log |
| `shops/{id}/notifications` | Shop | Alerts and notifications |
| `shops/{id}/analytics_snapshots` | Shop | Daily aggregated metrics |
| `shops/{id}/settings` | Shop | Shop configuration |

## Security Rules
- All data scoped to shop (multi-tenant)
- Role-based access: Admin > Manager > Warehouse > Sales
- Transactions and stock movements are append-only (immutable audit trail)
- Analytics snapshots writable by Cloud Functions only

## Cloud Functions
| Function | Trigger | Purpose |
|----------|---------|---------|
| `validateStockDeduction` | HTTPS Callable | Atomic stock deduction in Firestore transaction |
| `checkLowStock` | Firestore onWrite | Creates notification when stock drops below reorder level |
| `aggregateDailySales` | Scheduled (daily) | Computes daily sales metrics per shop |

## Barcode Scan Flow
```
Scan → Debounce (500ms) → Search Local Cache → Search Firestore
  ├── Found → Product Sheet (Sell / Restock / Adjust / View)
  └── Not Found → Create New Product (barcode prefilled)
```

## Seed Data
After setting up Firebase, run the seed script to populate demo data:
```bash
# From the project root
dart run scripts/seed_data.dart
```
Or manually create test data through the app's UI.

## Testing
```bash
flutter test                    # Unit & widget tests
flutter test --coverage         # With coverage report
```


