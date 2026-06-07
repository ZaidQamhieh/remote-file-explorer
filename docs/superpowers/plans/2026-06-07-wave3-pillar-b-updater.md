# Wave 3 Pillar B — In-App Updater (Android) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the Android app over Wi-Fi/Tailscale with no USB and no app store — the PC agent serves the latest APK, the phone checks its version, downloads via the pinned client, and launches Android's installer (one tap).

**Architecture:** The agent scans `~/.rfe-agent/updates/` for `rfe-<versionName>-<versionCode>.apk` files and exposes `GET /v1/app/latest` (metadata) + `GET /v1/app/download` (bytes, via `http.ServeContent`). The app compares the agent's `versionCode` to its own `buildNumber`, downloads through `AgentClient`, and hands the APK to Android's package installer. iOS is excluded (`Platform.isAndroid` guards).

**Tech Stack:** Go (chi, stdlib), Flutter/Dart (Riverpod 2.6.1, dio, package_info_plus, an APK install plugin), Android `REQUEST_INSTALL_PACKAGES` + `FileProvider`.

**Spec:** `docs/superpowers/specs/2026-06-07-wave3-settings-updater-polish-design.md` (Pillar B).

**Environment:** `export PATH="$HOME/.local/go/bin:$PATH"` (Go, from `agent/`); `export PATH="$HOME/flutter/bin:$PATH"` (Flutter, from `app/`).

**Depends on / coordinates with Pillar A:** both add routes to `server.go` and methods to `agent_client.dart`. If executed in parallel worktrees, expect a small merge in those two files (handled at integration, as in Wave 2). This plan assumes the **current** `server.Config` (with `Settings`/without — either works; the updater only needs a new `UpdatesDir` field).

---

## File Structure

**Agent (Go)**
- Create: `agent/internal/updates/updates.go` — scan updates dir, parse versions
- Create: `agent/internal/updates/updates_test.go`
- Create: `agent/internal/server/update_handlers.go` — `/app/latest`, `/app/download`
- Create: `agent/internal/server/update_handlers_test.go`
- Modify: `agent/internal/server/server.go` — `Config.UpdatesDir`; register routes
- Modify: `agent/cmd/agent/main.go` — create+plumb `~/.rfe-agent/updates/`
- Modify: `protocol/openapi.yaml`

**App (Flutter)**
- Create: `app/lib/core/models/app_release.dart`
- Modify: `app/lib/core/api/agent_client.dart` — `latestRelease`, `downloadApk`
- Create: `app/lib/core/update/update_service.dart` — version compare + provider
- Create: `app/lib/features/settings/update_tile.dart` — "Check for updates" UI (Android-only)
- Modify: `app/lib/features/hosts/host_list_screen.dart` — launch-time update banner
- Modify: `app/pubspec.yaml` — add `package_info_plus`, `install_plugin` (or `open_filex`)
- Modify: `app/android/app/src/main/AndroidManifest.xml` — `REQUEST_INSTALL_PACKAGES`, `FileProvider`

---

## Task 1: `updates.Latest` — scan + parse APK versions

**Files:**
- Create: `agent/internal/updates/updates.go`
- Test: `agent/internal/updates/updates_test.go`

- [ ] **Step 1: Write the failing test**

```go
package updates

import (
	"os"
	"path/filepath"
	"testing"
)

func writeAPK(t *testing.T, dir, name string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte("dummy"), 0o644); err != nil {
		t.Fatalf("write %s: %v", name, err)
	}
}

func TestLatest_PicksHighestVersionCode(t *testing.T) {
	dir := t.TempDir()
	writeAPK(t, dir, "rfe-1.0.0-1.apk")
	writeAPK(t, dir, "rfe-1.2.0-12.apk")
	writeAPK(t, dir, "rfe-1.1.0-9.apk")
	writeAPK(t, dir, "notes.txt") // ignored

	rel, err := Latest(dir)
	if err != nil {
		t.Fatalf("latest: %v", err)
	}
	if rel == nil {
		t.Fatal("expected a release")
	}
	if rel.VersionCode != 12 || rel.VersionName != "1.2.0" {
		t.Fatalf("expected 1.2.0/12, got %s/%d", rel.VersionName, rel.VersionCode)
	}
	if rel.Filename != "rfe-1.2.0-12.apk" {
		t.Fatalf("wrong filename: %s", rel.Filename)
	}
	if rel.Size != 5 {
		t.Fatalf("expected size 5, got %d", rel.Size)
	}
}

func TestLatest_EmptyDirReturnsNil(t *testing.T) {
	rel, err := Latest(t.TempDir())
	if err != nil {
		t.Fatalf("latest: %v", err)
	}
	if rel != nil {
		t.Fatalf("expected nil, got %+v", rel)
	}
}

func TestLatest_MissingDirReturnsNil(t *testing.T) {
	rel, err := Latest(filepath.Join(t.TempDir(), "does-not-exist"))
	if err != nil {
		t.Fatalf("expected no error for missing dir, got %v", err)
	}
	if rel != nil {
		t.Fatal("expected nil for missing dir")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/updates/ -v`
Expected: FAIL — `undefined: Latest`.

- [ ] **Step 3: Write minimal implementation**

```go
// Package updates discovers the newest Android APK the agent should serve to
// the app. APKs are dropped in the updates dir named rfe-<versionName>-<versionCode>.apk
// (e.g. rfe-1.2.0-12.apk); versionCode is the monotonic comparison key.
package updates

import (
	"os"
	"path/filepath"
	"regexp"
	"strconv"
)

// Release describes one available APK.
type Release struct {
	VersionName string `json:"versionName"`
	VersionCode int    `json:"versionCode"`
	Filename    string `json:"-"`
	Size        int64  `json:"size"`
}

// rfe-<versionName>-<versionCode>.apk
var apkPattern = regexp.MustCompile(`^rfe-(.+)-(\d+)\.apk$`)

// Latest returns the highest-versionCode APK in dir, or nil if the dir is
// empty or missing.
func Latest(dir string) (*Release, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var best *Release
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		m := apkPattern.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		code, err := strconv.Atoi(m[2])
		if err != nil {
			continue
		}
		if best != nil && code <= best.VersionCode {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return nil, err
		}
		best = &Release{
			VersionName: m[1],
			VersionCode: code,
			Filename:    e.Name(),
			Size:        info.Size(),
		}
	}
	return best, nil
}

// Path returns the absolute path to a release's APK within dir.
func Path(dir string, rel *Release) string {
	return filepath.Join(dir, rel.Filename)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/updates/ -v`
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add agent/internal/updates/updates.go agent/internal/updates/updates_test.go
git commit -m "feat(agent): updates.Latest scans APK dir for newest version"
```

---

## Task 2: Update handlers — `/app/latest` and `/app/download`

**Files:**
- Create: `agent/internal/server/update_handlers.go`
- Test: `agent/internal/server/update_handlers_test.go`

- [ ] **Step 1: Write the failing test**

```go
package server

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestLatestAppHandler(t *testing.T) {
	dir := t.TempDir()
	_ = os.WriteFile(filepath.Join(dir, "rfe-2.0.0-20.apk"), []byte("apk-bytes"), 0o644)

	rr := httptest.NewRecorder()
	latestAppHandler(dir)(rr, httptest.NewRequest(http.MethodGet, "/v1/app/latest", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("code = %d", rr.Code)
	}
	if body := rr.Body.String(); !contains(body, `"versionCode":20`) || !contains(body, `"versionName":"2.0.0"`) {
		t.Fatalf("unexpected body: %s", body)
	}
}

func TestLatestAppHandler_NoneIs204(t *testing.T) {
	rr := httptest.NewRecorder()
	latestAppHandler(t.TempDir())(rr, httptest.NewRequest(http.MethodGet, "/v1/app/latest", nil))
	if rr.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", rr.Code)
	}
}

func TestDownloadAppHandler_StreamsBytes(t *testing.T) {
	dir := t.TempDir()
	_ = os.WriteFile(filepath.Join(dir, "rfe-2.0.0-20.apk"), []byte("apk-bytes"), 0o644)

	rr := httptest.NewRecorder()
	downloadAppHandler(dir)(rr, httptest.NewRequest(http.MethodGet, "/v1/app/download", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("code = %d", rr.Code)
	}
	if rr.Body.String() != "apk-bytes" {
		t.Fatalf("unexpected body: %q", rr.Body.String())
	}
	if ct := rr.Header().Get("Content-Type"); ct != "application/vnd.android.package-archive" {
		t.Fatalf("unexpected content-type: %s", ct)
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || indexOf(s, sub) >= 0)
}
func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/server/ -run "App" -v`
Expected: FAIL — `latestAppHandler undefined`.

- [ ] **Step 3: Write minimal implementation** — create `update_handlers.go`

```go
// Package server — in-app update route handlers (Android APK delivery).
package server

import (
	"net/http"
	"os"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/updates"
)

func latestAppHandler(dir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rel, err := updates.Latest(dir)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		if rel == nil {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		writeJSON(w, http.StatusOK, rel)
	}
}

func downloadAppHandler(dir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rel, err := updates.Latest(dir)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		if rel == nil {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "no update available")
			return
		}
		f, err := os.Open(updates.Path(dir, rel))
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		defer f.Close()
		info, err := f.Stat()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		w.Header().Set("Content-Type", "application/vnd.android.package-archive")
		// ServeContent adds Range support, Content-Length, 206/416 handling.
		http.ServeContent(w, r, rel.Filename, info.ModTime(), f)
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go test ./internal/server/ -run "App" -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add agent/internal/server/update_handlers.go agent/internal/server/update_handlers_test.go
git commit -m "feat(agent): /app/latest and /app/download handlers"
```

---

## Task 3: Wire updates dir into server + main

**Files:**
- Modify: `agent/internal/server/server.go` (Config + routes)
- Modify: `agent/cmd/agent/main.go`

- [ ] **Step 1: Add `UpdatesDir` to `Config`**

In `server.go`, add a field to `Config`:
```go
	UpdatesDir string // directory of downloadable APKs for in-app update
```

Register the routes inside the authenticated group (next to `/thumb`):
```go
			// In-app updater
			r.Get("/app/latest", latestAppHandler(cfg.UpdatesDir))
			r.Get("/app/download", downloadAppHandler(cfg.UpdatesDir))
```

- [ ] **Step 2: Create + plumb the dir in `main.go`**

After `thumbCacheDir` setup, add:
```go
	updatesDir := filepath.Join(*dataDir, "updates")
	if err := os.MkdirAll(updatesDir, 0o755); err != nil {
		log.Fatalf("updates dir: %v", err)
	}
```
Add `UpdatesDir: updatesDir,` to the `server.Config{...}` literal.

- [ ] **Step 3: Build + test**

Run: `cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go build ./... && go test ./...`
Expected: build clean; all tests PASS.

- [ ] **Step 4: End-to-end smoke (curl)**

```bash
cd agent && export PATH="$HOME/.local/go/bin:$PATH" && go build -o /tmp/rfe-agent ./cmd/agent
/tmp/rfe-agent -addr 127.0.0.1:8798 -data /tmp/rfe-b-test &
sleep 1
mkdir -p /tmp/rfe-b-test/updates
printf 'FAKEAPK' > /tmp/rfe-b-test/updates/rfe-9.9.9-999.apk
# pair (Wave 2 flow) -> $TOKEN, then:
curl -sk https://127.0.0.1:8798/v1/app/latest -H "Authorization: Bearer $TOKEN"
# expect {"versionName":"9.9.9","versionCode":999,"size":7}
curl -sk https://127.0.0.1:8798/v1/app/download -H "Authorization: Bearer $TOKEN" -o /tmp/got.apk
cat /tmp/got.apk   # expect FAKEAPK
kill %1
```
Expected: latest returns the metadata; download returns the bytes.

- [ ] **Step 5: Commit**

```bash
git add agent/internal/server/server.go agent/cmd/agent/main.go
git commit -m "feat(agent): serve in-app updates from data/updates dir"
```

---

## Task 4: OpenAPI — document update endpoints

**Files:**
- Modify: `protocol/openapi.yaml`

- [ ] **Step 1: Add paths + schema**

Under `paths:`:
```yaml
  /app/latest:
    get:
      summary: Latest available Android APK
      security: [{ deviceToken: [] }]
      responses:
        '200':
          description: Release metadata
          content:
            application/json:
              schema: { $ref: '#/components/schemas/AppRelease' }
        '204': { description: No update available }
  /app/download:
    get:
      summary: Download the latest APK (Range-enabled)
      security: [{ deviceToken: [] }]
      responses:
        '200': { description: APK bytes (application/vnd.android.package-archive) }
        '404': { description: No update available }
```

Under `components.schemas`:
```yaml
    AppRelease:
      type: object
      properties:
        versionName: { type: string }
        versionCode: { type: integer }
        size: { type: integer, format: int64 }
```

- [ ] **Step 2: Validate**

Run: `cd ~/Storage/Projects/remote-file-explorer && python3 -c "import yaml; yaml.safe_load(open('protocol/openapi.yaml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add protocol/openapi.yaml
git commit -m "docs(protocol): add /app/latest and /app/download"
```

---

## Task 5: App — `AppRelease` model + client methods

**Files:**
- Create: `app/lib/core/models/app_release.dart`
- Modify: `app/lib/core/api/agent_client.dart`
- Test: `app/test/models_test.dart` (append)

- [ ] **Step 1: Write the failing test** (append to `models_test.dart`)

```dart
import 'package:remote_file_explorer/core/models/app_release.dart';

// inside a new group:
  group('AppRelease', () {
    test('parses metadata', () {
      final r = AppRelease.fromJson({
        'versionName': '1.2.0',
        'versionCode': 12,
        'size': 1048576,
      });
      expect(r.versionName, '1.2.0');
      expect(r.versionCode, 12);
      expect(r.size, 1048576);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/models_test.dart`
Expected: FAIL — `app_release.dart` not found.

- [ ] **Step 3: Implement** — `app_release.dart`:

```dart
/// Mirror of the agent's GET /v1/app/latest payload.
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.size,
  });

  final String versionName;
  final int versionCode;
  final int size;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        versionName: json['versionName'] as String? ?? '',
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}
```

Add to `agent_client.dart` (import `../models/app_release.dart` at top), after the thumbnail section:

```dart
  // ---------------------------------------------------------------------------
  // In-app updates
  // ---------------------------------------------------------------------------

  /// Returns the latest APK the agent offers, or `null` when none (204).
  Future<AppRelease?> latestRelease() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/app/latest');
      final data = res.data;
      if (res.statusCode == 204 || data == null) return null;
      return AppRelease.fromJson(data);
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }

  /// Downloads the latest APK to [localFile], reporting [onProgress].
  Future<void> downloadApk({
    required File localFile,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.download(
        '/app/download',
        localFile.path,
        options: Options(responseType: ResponseType.stream),
        deleteOnError: true,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
      );
    } on DioException catch (e) {
      throw _apiError(e);
    }
  }
```

- [ ] **Step 4: Run test + analyze**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/models_test.dart && flutter analyze lib/core/api/agent_client.dart lib/core/models/app_release.dart`
Expected: tests PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/models/app_release.dart app/lib/core/api/agent_client.dart app/test/models_test.dart
git commit -m "feat(app): AppRelease model + latestRelease/downloadApk client methods"
```

---

## Task 6: App — dependencies + Android manifest

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Create: `app/android/app/src/main/res/xml/provider_paths.xml`

- [ ] **Step 1: Add dependencies**

In `app/pubspec.yaml` under `dependencies:` add:
```yaml
  package_info_plus: ^9.0.1
  install_plugin: ^2.1.0
```
(`install_plugin` exposes `InstallPlugin.installApk(path, appId)` and requests the install permission. If it fails to resolve at `pub get` time, fall back to `open_filex: ^4.5.0` and open the APK file — Android routes `.apk` opens to the package installer. Pick whichever resolves; the rest of the plan calls a single `_installApk(path)` helper defined in Task 7 so only that helper changes.)

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter pub get`
Expected: resolves without downgrading `flutter_riverpod` below 2.6.1 (verify the resolved line in output stays `flutter_riverpod 2.6.1`).

- [ ] **Step 2: Android manifest permissions + FileProvider**

In `app/android/app/src/main/AndroidManifest.xml`, add inside `<manifest>` (above `<application>`):
```xml
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
```
Inside `<application>`, add a FileProvider so the installer can read the downloaded APK on Android 7+:
```xml
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/provider_paths"/>
        </provider>
```
(If `install_plugin` registers its own provider authority, skip this block and use the plugin's documented authority. The Task 7 helper passes `applicationId` so it matches.)

- [ ] **Step 3: Provider paths**

Create `app/android/app/src/main/res/xml/provider_paths.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-cache-path name="apk_cache" path="."/>
    <cache-path name="cache" path="."/>
</paths>
```

- [ ] **Step 4: Verify build still compiles**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter build apk --debug`
Expected: `✓ Built ... app-debug.apk`.

- [ ] **Step 5: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/android/app/src/main/AndroidManifest.xml app/android/app/src/main/res/xml/provider_paths.xml
git commit -m "build(app): add update deps + Android install permission/FileProvider"
```

---

## Task 7: App — UpdateService (version compare)

**Files:**
- Create: `app/lib/core/update/update_service.dart`
- Test: `app/test/update_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/app_release.dart';
import 'package:remote_file_explorer/core/update/update_service.dart';

void main() {
  group('isUpdateAvailable', () {
    test('true when release code is higher than installed', () {
      final rel = const AppRelease(versionName: '1.2.0', versionCode: 12, size: 1);
      expect(isUpdateAvailable(installedBuild: 11, release: rel), isTrue);
    });
    test('false when equal', () {
      final rel = const AppRelease(versionName: '1.2.0', versionCode: 12, size: 1);
      expect(isUpdateAvailable(installedBuild: 12, release: rel), isFalse);
    });
    test('false when installed is newer', () {
      final rel = const AppRelease(versionName: '1.2.0', versionCode: 12, size: 1);
      expect(isUpdateAvailable(installedBuild: 13, release: rel), isFalse);
    });
    test('false when release is null', () {
      expect(isUpdateAvailable(installedBuild: 5, release: null), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/update_service_test.dart`
Expected: FAIL — `update_service.dart` not found.

- [ ] **Step 3: Implement** — `update_service.dart`:

```dart
import '../models/app_release.dart';

/// Pure version comparison — true when [release] is newer than the installed
/// build number. Kept free of plugins so it is unit-testable.
bool isUpdateAvailable({
  required int installedBuild,
  required AppRelease? release,
}) {
  if (release == null) return false;
  return release.versionCode > installedBuild;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter test test/update_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/update/update_service.dart app/test/update_service_test.dart
git commit -m "feat(app): UpdateService version comparison (tested)"
```

---

## Task 8: App — "Check for updates" UI + installer (Android-only)

**Files:**
- Create: `app/lib/features/settings/update_tile.dart`
- Modify: `app/lib/features/hosts/host_list_screen.dart` (launch-time check banner)

This task is integration UI (plugin + platform installer) verified manually on a device, not via unit test.

- [ ] **Step 1: Create `update_tile.dart`**

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
// Installer import — matches the dependency chosen in Task 6:
import 'package:install_plugin/install_plugin.dart';

import '../../core/api/agent_client.dart';
import '../../core/models/app_release.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/update/update_service.dart';

/// A Settings tile that checks the host for a newer APK and installs it.
/// Hidden on non-Android platforms.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key, required this.host});
  final Host host;

  @override
  ConsumerState<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<UpdateTile> {
  String _status = '';
  bool _busy = false;
  double? _progress;

  Future<void> _checkAndInstall() async {
    if (!Platform.isAndroid) return;
    setState(() {
      _busy = true;
      _status = 'Checking…';
      _progress = null;
    });
    try {
      final store = await ref.read(hostStoreProvider.future);
      final token = await store.getToken(widget.host.id);
      final client = AgentClient(widget.host, deviceToken: token);

      final AppRelease? rel = await client.latestRelease();
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;

      if (!isUpdateAvailable(installedBuild: installed, release: rel)) {
        setState(() {
          _busy = false;
          _status = 'Up to date (v${info.version})';
        });
        return;
      }

      setState(() => _status = 'Downloading v${rel!.versionName}…');
      final dir = await getExternalCacheDirectories();
      final base = (dir != null && dir.isNotEmpty)
          ? dir.first
          : await getTemporaryDirectory();
      final file = File('${base.path}/update-${rel!.versionCode}.apk');
      await client.downloadApk(
        localFile: file,
        onProgress: (r, t) {
          if (t > 0) setState(() => _progress = r / t);
        },
      );

      setState(() => _status = 'Launching installer…');
      await _installApk(file.path, info.packageName);
      setState(() {
        _busy = false;
        _status = 'Installer launched — confirm to update.';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'Update failed: $e';
      });
    }
  }

  // Single point of plugin integration (swap here if using open_filex).
  Future<void> _installApk(String path, String appId) async {
    await InstallPlugin.installApk(path, appId: appId);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !kIsWeb) {
      // Updater is Android-only; render nothing elsewhere.
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: const Icon(Icons.system_update),
      title: const Text('Check for updates'),
      subtitle: _status.isEmpty ? null : Text(_status),
      trailing: _busy
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2, value: _progress),
            )
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _checkAndInstall,
    );
  }
}
```

(If Task 6 chose `open_filex`, replace `_installApk` body with:
`await OpenFilex.open(path, type: 'application/vnd.android.package-archive');`
and swap the import.)

- [ ] **Step 2: Surface it in Settings**

In `app/lib/features/settings/settings_screen.dart` (created in Pillar A), add `UpdateTile(host: widget.host)` to the `ListView` children (e.g. just before the trailing `SizedBox(height: 24)`). Add the import `import 'update_tile.dart';`.

> If Pillar A is not yet merged when implementing this, instead add a temporary
> standalone route: a `MaterialPageRoute` to a minimal `Scaffold` containing
> `UpdateTile`, reachable from the host card menu, and reconcile during integration.

- [ ] **Step 3: Launch-time banner (optional but in-scope)**

In `host_list_screen.dart`, after the host store loads, kick off a best-effort check for the most-recently-used host and show a dismissible `MaterialBanner` "Update available → vX.Y.Z" with an "Update" action that pushes the Settings screen. Guard the whole thing with `if (Platform.isAndroid)`. Keep it best-effort (swallow errors) so a missing/old agent never blocks the host list.

```dart
// Inside HostListScreen.build, after `data: (store) {` resolves hosts, you can
// trigger this from initState of a small ConsumerStatefulWidget wrapper, or call
// it once via ref.listen. Minimal version: a method on a stateful host list.
Future<void> _maybeOfferUpdate(BuildContext context, WidgetRef ref, Host host) async {
  if (!Platform.isAndroid) return;
  try {
    final store = await ref.read(hostStoreProvider.future);
    final token = await store.getToken(host.id);
    final client = AgentClient(host, deviceToken: token);
    final rel = await client.latestRelease();
    final info = await PackageInfo.fromPlatform();
    final installed = int.tryParse(info.buildNumber) ?? 0;
    if (!isUpdateAvailable(installedBuild: installed, release: rel)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text('Update available → v${rel!.versionName}'),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsScreen(host: host),
              ));
            },
            child: const Text('Update'),
          ),
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Later'),
          ),
        ],
      ),
    );
  } catch (_) {
    // best-effort; never block the host list
  }
}
```
Add imports for `dart:io`, `package_info_plus`, `app_release.dart`, `update_service.dart`, and `../settings/settings_screen.dart` as needed.

- [ ] **Step 4: Analyze + build**

Run: `cd app && export PATH="$HOME/flutter/bin:$PATH" && flutter analyze lib/ && flutter build apk --debug`
Expected: `No issues found!` then `✓ Built ... app-debug.apk`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/settings/update_tile.dart app/lib/features/hosts/host_list_screen.dart
git commit -m "feat(app): in-app update check + one-tap installer (Android)"
```

---

## Pillar B Verification (run after all tasks)

- [ ] `cd agent && go test ./...` — green.
- [ ] Build a release APK with an explicit higher build number:
      `cd app && flutter build apk --release --build-name=9.9.9 --build-number=999`
      then copy it to the agent's updates dir as `rfe-9.9.9-999.apk`:
      `cp build/app/outputs/flutter-apk/app-release.apk ~/.rfe-agent/updates/rfe-9.9.9-999.apk`
- [ ] On a phone running a lower-numbered build: open the app → "Update available" banner
      appears (or Settings → Check for updates reports it) → tap → APK downloads over the
      pinned client → Android install prompt → confirm → app relaunches as 9.9.9. **No USB.**
- [ ] With no APK in the updates dir: `/app/latest` → 204; Settings check says "Up to date".
- [ ] Confirm the updater UI is absent on a non-Android run (e.g. `flutter run -d linux`),
      proving the `Platform.isAndroid` guard.
