# Remote File Explorer

A mobile app that turns your phone into a full graphical file explorer for your Windows, macOS, and
Linux computers — browse, manage, and transfer files over a Finder/Explorer-style GUI, with no SSH
or terminal required.

- **`app/`** — Flutter mobile app (Android-focused)
- **`agent/`** — Go host service that runs on each Windows/macOS/Linux computer
- **`protocol/`** — OpenAPI 3 contract shared by both sides (source of truth)
- **`docs/`** — architecture and setup guides

The app connects to the agent over HTTPS/TLS. On a local network, connect by IP address or
hostname without a VPN. **Tailscale is optional** for remote access; the app can also save a
direct HTTPS hostname or IP as a fallback route. That route works only after the PC owner configures
public DNS (if needed), router NAT, and firewall access to the agent. The app never opens ports or
changes router settings, and its pinned certificate means a TLS-terminating proxy with a different
certificate is not compatible. The agent advertises itself over mDNS/DNS-SD, but the Flutter app
does not currently browse those records, so add a host by scanning its pairing QR or entering its
address. The project has no cloud relay or cloud database. See `docs/` for the full architecture.

## Status

The agent serves the v1 API for directory browsing, resumable transfers, search, previews, settings,
paired-device management, and in-app Android updates. Windows, Linux, and macOS hosts also expose a
permission-controlled app catalog and launch action. The Flutter app (currently v1.42.x) covers
these features with a Finder/Explorer-style UI and self-updates over the air.

## Pairing

Pairing is done from the host side with the agent's admin CLI:

```sh
rfe-agent pair         # prints a one-time pairing code, QR, and readable certificate fingerprint
```

Scan the QR displayed locally on the intended host, or obtain the pairing details through a
trusted independent channel. For manual pairing, compare the fingerprint with `rfe-agent status`
on the host console, then enter the address, code, and fingerprint in the app. The fingerprint
must be independently verified: a QR and fingerprint received together over the same untrusted
connection do not establish the host's identity. The app checks the pin before sending pairing
codes or account credentials. Successful pairing stores a per-device bearer token; no cloud
account is required.

## Host app access

Each paired device starts with app-list and app-launch access turned off. An admin device can
grant either permission in that computer's Settings under Devices → App access. Launch permission
requires list permission. The Apps button shows launchable apps registered for the host's current
user: Windows AppsFolder entries, Linux XDG desktop entries, or macOS apps in standard application
folders. This is a catalog of registered desktop apps, not every executable file on the computer;
macOS aliases and apps outside those folders are not included.

Run requests contain only a host-issued opaque app ID. The agent resolves it against the current
catalog and starts the app in the interactive desktop session; it does not accept a client command,
path, or arguments. Launch attempts are rate-limited and recorded in the host audit log. If the
agent is running without an active desktop session, launching is unavailable until that user signs
in to the desktop. This applies to all three host platforms.

## Install the host agent

Download the matching host binary, verify its SHA-256 checksum, install it for the signed-in user,
and pair the phone using a host-generated QR and independently verified certificate fingerprint.
The [host setup guide](docs/host-setup.md) has exact steps for Windows, macOS, and Linux, including
start-at-login, service controls, and uninstall. Connections use HTTPS only; the installer does not
configure a firewall, router, or public DNS. The native app pins the agent certificate, while
public web-companion access needs an owner-managed browser-trusted certificate/proxy path and is not
ready out of the box.

For development, run the agent with `cd agent && go run ./cmd/agent`; see
[`docs/development.md`](docs/development.md) for the developer workflow. The same agent process
serves the web companion at `https://<host>:8765/`.
