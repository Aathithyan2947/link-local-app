# Link Local — Mobile App

A neighbourhood community app: connect with neighbours, discover trusted local
service providers, and join events and interest groups around you.

Built with **Flutter** · **Riverpod** (state) · **go_router** (navigation) ·
**Dio** (networking).

## Getting started

```bash
flutter pub get

# Run (Chrome is the quickest for a look; iOS/Android also supported)
flutter run -d chrome
```

The app talks to the Link Local backend API. The host is auto-selected:
`localhost` on web/iOS, `10.0.2.2` on the Android emulator. Override it for a
physical device or a hosted backend:

```bash
flutter run --dart-define=API_BASE_URL=http://<your-host>:4000/api/v1
```

## Project structure

```
lib/
  core/
    config/        # API base URL + app config
    network/       # Dio client, interceptors, API errors
    router/        # go_router + auth-driven redirects
    storage/       # secure token storage
    theme/         # colors, typography, theme
    widgets/       # shared widgets (buttons, fields, header, ...)
  features/
    onboarding/    # splash + intro carousel
    auth/          # register / login / OTP / role selection / verification hold
    address/       # address capture, map pin, proof upload, per-city form
    services/      # service-category selection (service providers)
    home/          # home feed + Explore / Events / Profile tabs
    profile/       # profile completion hub + section editors
    reference/     # cities, service categories
    discovery/     # service providers, events, groups
```

## Features

- Onboarding → register/login (mobile OTP or email + password) → address capture
  (current location / search / map pin) → proof upload → resident vs service-provider
  → home.
- Home feed scoped to your city: service providers, community discussions,
  workshops/events, interest groups, referrals.
- Profile completion: education, profession, hobbies, family, pets, contacts,
  "can offer help with", address proof; service providers add services, products
  and delivery preferences.

## Permissions

- **Location** — to capture your address on the map (`geolocator`).
- **Camera / Photos** — to upload address-proof documents (`image_picker` /
  `file_picker`).

> Native plugins are used (location, camera, file picker), so after pulling
> dependency changes do a full `flutter run` rather than a hot reload.
