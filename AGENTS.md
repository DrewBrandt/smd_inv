# Repo Notes

## Flutter Commands

- Do not run `flutter test` inside the sandbox for this repo. The Flutter SDK lives at `C:\flutter`, and sandboxed runs cannot write the lock/cache files Flutter needs at startup.
- Prefer running Flutter commands outside the sandbox from this workspace. `flutter test` already has an approved elevated prefix and should be used that way by default.
- Root cause seen in this repo: Flutter needs write access to `C:\flutter\bin\cache\lockfile` and may also touch `~\AppData\Roaming\.dart-tool`.
