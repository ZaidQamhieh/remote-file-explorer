# Install the host agent

This guide installs the Remote File Explorer agent for the signed-in desktop user. It does not
require administrator/root privileges. The agent serves the phone app over HTTPS and stores its
certificate, settings, database, and paired-device records in that user's `~/.rfe-agent` directory
(on Windows, the equivalent user profile directory).

## 1. Download the right archive

Open the [host-agent releases](https://github.com/ZaidQamhieh/remote-file-explorer/releases) and
choose the latest release named `agent-vX.Y.Z` (for example, `agent-v1.3.0`). Download both the
archive for the host computer and `SHA256SUMS` from that release.

Choose the archive for the computer's operating system and CPU:

| Computer | Archive suffix |
| --- | --- |
| Linux, Intel/AMD 64-bit (`x86_64`) | `linux-amd64.tar.gz` |
| Linux, ARM 64-bit (`aarch64`) | `linux-arm64.tar.gz` |
| macOS, Intel | `darwin-amd64.tar.gz` |
| macOS, Apple silicon | `darwin-arm64.tar.gz` |
| Windows, Intel/AMD 64-bit | `windows-amd64.zip` |
| Windows, ARM 64-bit | `windows-arm64.zip` |

On Linux, `uname -m` reports `x86_64` or `aarch64`. On macOS, choose **Apple menu → About This
Mac** to see whether the processor is Intel or Apple silicon. On Windows, open **Settings → System
→ About** and check **System type**.

## 2. Verify the download

The release includes SHA-256 checksums so you can detect an incomplete or corrupted download. In
the commands below, replace the example archive name with the exact downloaded filename.

Linux:

```sh
cd ~/Downloads
asset='agent-v1.3.0-linux-amd64.tar.gz'
grep -F "  $asset" SHA256SUMS | sha256sum --check -
```

macOS:

```sh
cd ~/Downloads
asset='agent-v1.3.0-darwin-arm64.tar.gz'
grep -F "  $asset" SHA256SUMS | shasum -a 256 -c -
```

Windows PowerShell:

```powershell
Set-Location "$HOME\Downloads"
$asset = 'agent-v1.3.0-windows-amd64.zip'
$line = Get-Content .\SHA256SUMS | Where-Object { $_ -match "\s+$([regex]::Escape($asset))$" }
if (-not $line) { throw "No checksum found for $asset" }
$expected = ($line -split '\s+')[0].ToLowerInvariant()
$actual = (Get-FileHash ".\$asset" -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "Checksum mismatch for $asset" }
Write-Output "Checksum OK: $asset"
```

These checksums are published beside the archives in the same GitHub release. They verify file
integrity; the host binaries are not code-signed, and a checksum from the same release does not
independently authenticate its publisher.

## 3. Put the binary in a stable user-owned location

Keep the binary in this location after installing its login service. The service refers to the
binary's full path, so moving or deleting it later will prevent the service from starting.

Linux (replace the archive name for your CPU):

```sh
mkdir -p "$HOME/.local/bin"
tar -xzf "$HOME/Downloads/agent-v1.3.0-linux-amd64.tar.gz" -C "$HOME/.local/bin" rfe-agent
chmod 755 "$HOME/.local/bin/rfe-agent"
```

macOS (replace the archive name for your CPU):

```sh
mkdir -p "$HOME/.local/bin"
tar -xzf "$HOME/Downloads/agent-v1.3.0-darwin-arm64.tar.gz" -C "$HOME/.local/bin" rfe-agent
chmod 755 "$HOME/.local/bin/rfe-agent"
```

Windows PowerShell (replace the archive name for your CPU):

```powershell
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\RFE'
New-Item -ItemType Directory -Force $installDir | Out-Null
Expand-Archive -LiteralPath "$HOME\Downloads\agent-v1.3.0-windows-amd64.zip" -DestinationPath $installDir -Force
$agent = Join-Path $installDir 'rfe-agent.exe'
```

## 4. Start it and enable start-at-login

Run `install` from the same user account that will own the files. This registers a per-user service
and starts it immediately:

| Host | Command |
| --- | --- |
| Linux | `"$HOME/.local/bin/rfe-agent" install` |
| macOS | `"$HOME/.local/bin/rfe-agent" install` |
| Windows PowerShell | `& $agent install` |

It uses systemd `--user` on Linux, a launchd LaunchAgent on macOS, and a standard-user Scheduled
Task on Windows. No administrator/root account or service account is created. Check the result with
`"$HOME/.local/bin/rfe-agent" status` on Linux/macOS, or `& $agent status` on Windows. The service
line reports whether the agent is installed and its current state.

The agent listens for HTTPS on its configured port (8765 by default). This command does not change
the computer's firewall, router, or public DNS settings. Connecting from outside the local network
requires a route you configure yourself, such as Tailscale or an explicitly configured direct HTTPS
route. The agent has no plaintext HTTP mode. The native phone app can trust the self-signed agent
certificate through the fingerprint pin established during pairing. Browsers do not trust that
self-signed certificate by default: public web-companion access is not ready out of the box and
requires an owner-managed browser-trusted certificate and renewal/proxy path. The current installer
does not provision certificates or configure a proxy; a TLS-terminating proxy that presents a
different certificate will not work with the native app's pinned connection on that same route.

## 5. Create the pairing QR and verify the fingerprint

With the agent running, open a second terminal or PowerShell window and run:

Linux/macOS:

```sh
"$HOME/.local/bin/rfe-agent" pair
```

Windows PowerShell:

```powershell
& $agent pair
```

The command prints a one-time pairing code, a QR, LAN/Tailscale addresses when available, and the
host's certificate fingerprint. On the phone, open **Add computer → Scan QR**. Verify that the
fingerprint shown by the phone matches the value displayed in the trusted host terminal (or another
trusted, independent channel) before completing pairing. A QR and fingerprint received together
through an untrusted network are not independent proof of the host's identity. Pairing codes expire
and can only be used once. A newly code-paired device starts with browse access only. Sign in or
register a host account on an owner device to grant download, upload, modify, delete, share-link,
and app-catalog permissions separately under **Settings → Devices**. The host's configured roots,
per-device jail, read-only mode, and global share-link switch continue to limit access.

## 6. Manage the local agent

Run these commands from the same account that installed the service:

| Action | Linux/macOS | Windows PowerShell |
| --- | --- | --- |
| Show host details and service state | `"$HOME/.local/bin/rfe-agent" status` | `& $agent status` |
| Start the installed agent | `"$HOME/.local/bin/rfe-agent" start` | `& $agent start` |
| Stop it for now | `"$HOME/.local/bin/rfe-agent" stop` | `& $agent stop` |
| Remove start-at-login and stop the service | `"$HOME/.local/bin/rfe-agent" uninstall` | `& $agent uninstall` |

Stopping the agent leaves its start-at-login entry installed; it will start again at the next login.
Use `start` to run it again now. `uninstall` stops the agent and removes the login entry, but keeps
the certificate, configuration, database, and paired devices in `~/.rfe-agent` (under your Windows
user profile on Windows). To remove that data as well, first uninstall the service, then remove
that directory yourself after making any backup you need.

To update the agent, stop and uninstall it, replace the binary at the same path, then run `install`
again. Keep the data directory so existing paired devices and host identity are preserved.

## Upload limits and abandoned sessions

Each upload is limited to **64 GiB**. The agent reserves the declared size while a session is open,
with a maximum of **4 open sessions and 64 GiB reserved per paired device**, plus **16 open sessions
and 128 GiB reserved across the host**. If a device or the host reaches a limit, the API returns
`429 RESOURCE_LIMIT`; finish or delete an existing session before opening another. The per-upload
limit is intentional to bound the impact of a declared sparse-file reservation. These reservations
do not check free disk space and cannot account for other applications writing to the same disk.

An open upload remains resumable while it receives chunks or owner status/resume requests. If it has
no such activity for **7 days**, the agent removes the stale session and its temporary file during its
hourly cleanup. Active status, chunk, and completion requests hold a session lease, so stale cleanup
leaves them untouched; a manual delete during active work returns `409 TRANSFER_ACTIVE`. If
temporary-file removal fails after a session row was deleted, a later age-gated cleanup removes the
unreferenced file once it is older than the same 7-day period.

## Release tags

Host agent binaries are released separately from the Android app. A maintainer publishes them by
creating and pushing an `agent-vX.Y.Z` tag (for example, `agent-v1.3.0`). The resulting dedicated
release contains six archives and `SHA256SUMS`:

- Linux amd64 and arm64
- macOS amd64 and arm64
- Windows amd64 and arm64

The artifacts are not code-signed. The checksums detect accidental corruption but do not provide a
signature or protect against a compromised release account.
