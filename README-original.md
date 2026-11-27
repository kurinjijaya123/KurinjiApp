# Kurinji Cup Sambarani – iOS (SwiftUI)

Native port of the PHP inventory app. Offline, single-device, same SQLite schema and business rules.

## Set up (Xcode 15+, iOS 17+)
1. Xcode > File > New > Project > iOS App (SwiftUI), name `Kurinji`.
2. Delete the generated `ContentView.swift` and `KurinjiApp`-style @main file.
3. Drag in everything from `Sources/` (tick "Copy items if needed").
4. Replace the project's `Assets.xcassets` with `Resources/Assets.xcassets` (or drag the 5 imagesets in).
5. Drag `Resources/inventory.db` in, tick the app target (it is copied to the Documents folder on first launch).
6. Run. Login: `admin` / `Kurinji@123`.

## Notes
- Changing the password: replace the SHA-256 hash in `AppState` (KurinjiApp.swift).
- Data lives on the phone. Reinstalling the app wipes it, so use Files/iCloud backup or a server API if you need multi-device sync.
