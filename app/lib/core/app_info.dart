/// This app's own version string, cached at startup.
///
/// Format: `<versionName>+<buildNumber>` (e.g. `1.10.0+18`), matching the
/// `X-RFE-Client-Version` header sent by [AgentClient] on every authenticated
/// request. Populated once in `main()` via `PackageInfo.fromPlatform()` —
/// reading it later is synchronous so [AgentClient]'s constructor can stay
/// synchronous. Empty until populated (e.g. in tests that never call
/// `main()`); an empty value is sent as an empty header, which the contract
/// allows.
String appClientVersion = '';
