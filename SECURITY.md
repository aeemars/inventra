# Inventra Security & Production Deployment Guide

## 1. Firebase Console Security Checklist

### App Check Enforcement
- [ ] Go to **Firebase Console → App Check**.
- [ ] Register your Android app (Play Integrity), iOS app (DeviceCheck / App Attest), and Web app (reCAPTCHA v3 / Enterprise).
- [ ] **Enforce App Check** for Cloud Firestore and Cloud Functions to prevent unauthorized API requests from non-app clients.

### API Key & Auth Restrictions
- [ ] Go to **Google Cloud Console → APIs & Services → Credentials**.
- [ ] Locate the Android API Key and restrict it to your package name and SHA-1 fingerprint.
- [ ] Locate the iOS API Key and restrict it to your iOS Bundle ID.
- [ ] Locate the Web API Key and restrict HTTP referrers to your authorized domain(s).
- [ ] Disable unused Auth providers in **Firebase Console → Authentication → Sign-in method**.

---

## 2. Dependency Audit & CI Integration

### Functions Audit
Run security audit on Node dependencies before each release:
```bash
cd functions
npm audit
```

### Flutter Dependency Check
Check for outdated or vulnerable packages:
```bash
flutter pub outdated
```
