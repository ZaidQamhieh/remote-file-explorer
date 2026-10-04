# RFE Desktop user guide

RFE Desktop is the PC-side partner of the RFE agent. It connects to an `rfe-agent` you run on a PC,
checks that it is the agent you mean, signs this computer in, and lists the devices paired with that
agent. This guide covers installing it, trusting an agent, the three ways to sign in, where things are
kept, and what every message means.

## What you need

- An `rfe-agent` running on the PC you want to reach, and its address (`host:port`).
- Linux with a Secret Service provider (GNOME Keyring, KeePassXC or KDE Wallet) running and unlocked.
  See [keystore.md](keystore.md).
- For "approve on the PC": an agent from `agent-v1.43.0-rc.1` or newer. Everything else works with
  `agent-v1.42.6` or newer. See [agent-compatibility.md](agent-compatibility.md).

## Install

When a release exists, download the `.deb` or the `.AppImage` from the release page.

- Debian and Ubuntu: `sudo apt install ./RFE-Desktop_1.0.0_amd64.deb` (use the file's real name; a
  release's files have hyphens, a local build's `.deb` has a space in it). The package recommends
  `gnome-keyring` or `keepassxc`.
- Any Linux: make the AppImage executable (`chmod +x`) and run it. It does not bring a keystore.

Check a download before you install it: each release lists `SHA256SUMS` and a software bill of
materials (`rfe-desktop.sbom.json`, CycloneDX) next to the packages. With the sums file and the package
in your downloads folder, `scripts/verify-download.sh SHA256SUMS "<package file>"` (from this repository)
prints `OK` or fails, and `sha256sum -c --ignore-missing SHA256SUMS` does the same without it.

Until then, build it yourself: [README.md](../README.md).

## Connect and trust an agent

1. Type the agent's address, for example `192.168.1.20:8765`, and press **Check certificate**. The app
   connects without sending any password and reads the agent's certificate.
2. It shows the certificate's SHA-256 fingerprint. On the PC run `rfe-agent status` and compare the two.
   Trust the agent only if they match exactly. This is the step that protects you from a different
   machine on the network answering in the agent's place: the agent's certificate is self-signed, so
   the fingerprint is the only identity it has.
3. After you trust it, the app remembers the fingerprint for that exact `host:port`. Every later
   connection to that address must present the same certificate or the app refuses it.

**Find agents** on the first screen lists agents on the same network that advertise themselves (mDNS,
`_rfe._tcp`). **Use** only fills in the address; it does not connect, sign in or trust anything. Anyone
on the network can advertise a service with that name, so a listed agent is exactly as unverified as one
you typed: you still press **Check certificate** and compare the fingerprint with `rfe-agent status`. The
search takes a few seconds and happens only when you press the button. Agents on other networks, or on
networks that block multicast (many guest and corporate networks), are not listed; type their address.

If the certificate changes (the agent was reinstalled or its data folder was deleted), the app shows a
warning with the old fingerprint and asks you to compare again. Only continue if you know why it changed.

To make the app forget an agent, open **Settings**, find it under **Trusted agents** and press
**Forget** twice. If you were signed in to it, you are signed out on this computer; the device stays
valid on the agent until it is revoked there.

## Sign in

After you trust an agent you have three choices.

| | Account | Pairing code | Approve on the PC |
|---|---|---|---|
| You need | a username and password made with `rfe-agent adduser` | a code from `rfe-agent pair` | someone at the PC |
| This computer can | list and manage every device | list and manage only itself | list and manage only itself |
| The password | is sent once over the pinned connection and never stored | not used | not used |

**Approve on the PC.** Press **Ask the PC to approve this computer**. The app shows an eight-digit
match code. The PC shows the same code in a notification, or in `rfe-agent pair requests`. Approve
only if the two codes are identical: the code is computed from the certificate this app saw, so a
machine in the middle shows a different one. Then `rfe-agent pair accept` on the PC. The app waits for
the answer and stops after the request expires.

In every case this computer is registered with the agent as a device with its own key. **Sign out**
revokes that device on the agent and removes the saved login here. If the agent cannot be reached,
the app signs out on this computer only and says so; the login then still works until it is revoked
on the PC.

## The window

The app follows the system's light or dark setting and scales with the system's display scaling. It
remembers the window's size and position. Starting it a second time does not open a second copy: the
first window is brought forward.

## Settings

**Settings** (top right) shows the account and this computer's device id, the trusted agents, a
keystore test, the log level, a diagnostics report and the version. The log level controls what the
app keeps in memory (the last 500 events); nothing is written to disk.

**Create report** builds the diagnostics report for a bug report: versions, the agent's address and
pinned fingerprint, the recent errors and the log. It holds no password, token or key (secrets the app
handles are masked out of the log even if one slipped in). It does name the agent's address, and the
log names the hosts you tried, so read it before you post it in public. **Copy** puts it on the
clipboard; if the system refuses, the text is selected so Ctrl+C works.

## What is kept, and where

| What | Where |
|---|---|
| Device signing key, login token | the system keystore |
| Agent address, its fingerprint, account name, device id, log level | `state.json` in the app's data folder (`~/.local/share/app.rfe.desktop/` on Linux; Settings shows the exact path), readable only by you |
| Password | nowhere |

If `state.json` is damaged the app says so and does not guess; delete the file to start over (you will
compare fingerprints again).

## Troubleshooting

Find the message the window shows. Messages from the agent:

| The window says | Code | What to do |
|---|---|---|
| Wrong username or password. | `INVALID_CREDENTIALS` | Check the username and password (the password is case-sensitive). Accounts are made on the PC with `rfe-agent adduser`. |
| That pairing code is wrong, expired or already used. Generate a new one on the PC. | `INVALID_CODE` | Pairing codes work once and expire. Run `rfe-agent pair` on the PC for a new one. |
| The agent no longer accepts this sign-in attempt (it expired or was already used). Try again. | `INVALID_NONCE` | Press the button again. Each attempt asks the agent for a fresh challenge. |
| The agent could not verify this computer's device key. Try again; if it keeps failing, report it. | `INVALID_SIGNATURE` | Try again. If it keeps happening, open Settings, set the log level to Detailed, and report it. |
| The agent requires a device key proof that this app did not send. This is a bug in the app. | `DEVICE_KEY_REQUIRED` | The app and the agent disagree about the sign-in protocol. Update the app (see agent-compatibility.md); if both are current, report it. |
| The agent already knows a different key for this computer. Remove this computer from the agent's device list (rfe-agent remove <id> on the PC), then sign in again. | `DEVICE_KEY_MISMATCH` | The agent has a different key on file for this computer's device id. Remove the old entry on the PC (`rfe-agent devices`, then `rfe-agent remove <id>`) and sign in again, or use "Create a new device key for this computer" on the sign-in screen, which registers this computer as a new device. |
| Too many attempts. The agent allows only a few sign-in and pairing attempts per minute. Wait a minute, then try again. | `RATE_LIMITED` | Wait a minute. The agent limits sign-in and pairing attempts. |
| The agent already has pairing requests waiting for approval on the PC. Answer them or wait for them to expire, then try again. | `PAIR_BUSY` | On the PC, answer the waiting requests (`rfe-agent pair requests`, then `rfe-agent pair accept` or `reject`), or wait for them to expire. |
| The agent no longer accepts this login. Sign in again. | `UNAUTHORIZED` | The agent revoked or forgot this computer's login. The app returns to the sign-in screen; sign in again. |
| This login is not allowed to do that. Sign in with the account, not a pairing code, to manage devices. | `FORBIDDEN` | A pairing-code login can manage only itself. Sign out and sign in with an account to manage every device. |
| The agent has no such item. It may have expired. | `NOT_FOUND` | The item expired or was already collected. Start the action again. |
| The agent refused the request as malformed. This is a bug in the app. | `BAD_REQUEST` | This is a bug in the app. Report it with the log level set to Detailed. |
| The agent had an internal error. Check its log on the PC. | `INTERNAL` | Look at the agent's log on the PC. |

Messages from this app:

| The window says | What it means and what to do |
|---|---|
| agent address must be host:port (put an IPv6 address in brackets, like [::1]:8765) | The address has a scheme, path or typo. Use `host:port`, for example `192.168.1.20:8765`. |
| cannot reach the agent securely | Nothing answered, or the connection failed. Check that the agent is running, the address and port are right, and no firewall is in the way. The text after the colon is the reason. |
| This agent's certificate is not the one you trusted | The agent presented a different certificate than the one you pinned. Do not sign in. If you did replace or reinstall the agent, forget it under Settings, Trusted agents, and compare the new fingerprint. If you did not, something else is answering at that address. |
| the agent presented no certificate | The address answers but not with TLS. It is not an RFE agent. |
| the agent reports a different fingerprint than the pinned one | The agent's own report disagrees with the certificate it presented. Do not continue; compare fingerprints again. |
| fingerprint must be 64 hex characters | Internal check; reconnect from the first screen. |
| unexpected response | The address answered with something that is not an RFE agent reply. Check the address and the agent version. |
| unexpected request id, unexpected device id, unknown pairing status | The agent sent a value the app refuses to use. Update the agent and the app; if both are current, report it. |
| enter the pairing code | The pairing code field is empty. |
| This agent is too old to approve a new computer from the PC | Approval needs `agent-v1.43.0-rc.1` or newer. Pair with a code or sign in with an account, or update the agent. |
| The request was rejected on the PC. | The owner pressed reject. Ask again if it was a mistake. |
| The request expired or was already used. Ask again. | The request ran out of time, or its answer was already collected. Press the button again. |
| The request timed out. Ask again. | Nobody answered on the PC in time. |
| The PC approved this computer, but saving the login failed | The agent hands out the approval only once and the keystore refused to keep it. Fix the keystore ([keystore.md](keystore.md)), then ask again. |
| not signed in | Sign in first. |
| is no longer a trusted agent; connect and compare its fingerprint again | The pin was forgotten while a login for it existed. Connect to the agent again from the first screen. |
| Sign out first; the saved login belongs to the current device key. | A new device key can only be made while signed out. |
| Signed out on this computer only | The agent could not be told. Revoke this computer on the PC (`rfe-agent revoke <id>`) so its old login stops working. |
| is damaged (...); delete it to create a new device identity | An `identity.json` left by an early version cannot be read. Delete that file; the app makes a new device key at the next sign-in. |
| cannot start network discovery, network discovery stopped | The app could not listen for mDNS answers (no network interface, or the system refused). Type the agent's address instead. |
| unknown log level | Choose one of the levels in the list. |
| is damaged (...); delete it to start over | `state.json` cannot be read. Delete it (Settings shows where) and set the app up again. |
| read, create, open, write or rename a path failed | The app's data folder cannot be used: check that it exists and that you own it. |
| tls config, http client, random | The system could not set up a secure connection or random numbers. Report it. |

Messages about the system keystore (`the OS keystore ...`, `no OS keystore answered`) are explained
in [keystore.md](keystore.md).

<!-- feature:transfers -->
## Transfers

**Transfers** (top right, once you are signed in) downloads files from the computer and uploads files to
it, with a progress bar for each. Everything is done by the app's core over the same pinned connection as
the rest; the window only shows the progress.

- **Download a file:** type the file's path on the computer and press **Download**. The file is saved in
  your download folder under `RFE Desktop` (`~/Downloads/RFE Desktop` on most systems; the screen shows
  the exact folder). You cannot choose another folder. Only the file's name is used: folders in the
  path, dots at the start, control characters and a very long name are removed, so a download can never
  be written outside that folder or hidden. A name that is already taken is never replaced; the new
  file is saved as `name (1)`, `name (2)` and so on. The file only gets its real name when it is whole,
  and the app then asks the computer for the file's SHA-256 and compares it with the saved copy; a
  match is shown as "Verified by the computer", a difference discards the copy.
- **Upload a file:** type the file's full path on this computer (starting with `/`) and the folder on the
  computer to put it in, then press **Upload**. The path must be a regular file. A path that is itself a
  symbolic link is refused (type the real path); the app does not follow it. The file keeps its name, and
  a file of that name on the computer is never replaced. The computer checks every piece and the whole
  file before the file appears under its name.
- **Cancel** stops a waiting or running transfer. A download's unfinished file is deleted and an upload's
  unfinished copy is removed from the computer. **Retry** (after a failure or a cancel) starts again: a
  download continues from what it already has, an upload sends only the pieces the computer is missing.
  **Cancel** on a failed transfer gives up on it and removes the leftovers. **Clear finished**
  removes finished and cancelled transfers from the list.
- Two transfers run at a time; the others say "Waiting for a free slot". The list is kept only while the
  app runs. A download that was running when the app was killed leaves a hidden file starting with
  `.rfe-` and ending `.part` in the download folder; delete it.
- A download of a very large file ends with "Checking the file" while the computer works out its
  SHA-256; an upload ends the same way while the computer checks the whole file.

For the file browser, the page offers `window.rfeTransfers.download(remotePath)` and
`window.rfeTransfers.upload(localPath, remoteDir)`. Each returns the transfer's id, or fails with the
messages below, and does not change the screen.

Messages about transfers from the agent (the window shows this wording instead of the generic one for
these codes):

| The window says | Code | What to do |
|---|---|---|
| The computer has no file at that path. It may have been moved or deleted. | `PATH_NOT_FOUND` | Check the path. File names are case-sensitive on Linux. |
| This login may not use that path on the computer. It is outside the folders it can reach. | `FORBIDDEN` | The agent limits this device to certain folders. Use a path inside them, or change the limit on the PC (`rfe-agent jail`). |
| The agent or this device is read-only, so it cannot accept uploads. | `READ_ONLY` | Turn read-only mode off on the PC. |
| This device has not been allowed to do that. Allow it on the computer, in the device's access settings. | `CAPABILITY_DENIED` | A pairing-code or approved device may be limited to browsing. Allow downloads or uploads for it on the PC. |
| A file with this name already exists on the computer. | `CONFLICT` | Uploads never replace a file. Rename the file here or pick another folder. |
| The file changed or was damaged while it was uploading. The upload was discarded; try again. | `HASH_MISMATCH` | Do not change the file while it uploads, then retry. |
| A piece of the file was damaged in transit three times in a row. Try again. | `CHUNK_HASH_MISMATCH` | The network is corrupting data. Retry; if it repeats, check the connection. |
| The file is too large for the computer to accept. | `PAYLOAD_TOO_LARGE` | The agent accepts at most 64 GiB per upload. |
| The computer has too many uploads open. Wait for one to finish, then retry. | `RESOURCE_LIMIT` | The agent allows a few open uploads per device and per computer. Wait, then retry. |
| The computer is still finishing the previous attempt. Retry in a moment. | `TRANSFER_ACTIVE` | The agent is still busy with the last attempt. Retry after a few seconds. |
| The computer closed this upload. Retry starts it again from the beginning. | `TRANSFER_NOT_OPEN` | The agent no longer holds the partly uploaded file. Retry. |

Messages about transfers from this app:

| The window says | What it means and what to do |
|---|---|
| enter the path of the file on the computer | The download path is empty. |
| enter the full path of the file on this computer | The upload path is empty. |
| enter the folder on the computer to upload into | The destination folder is empty. |
| that path on the computer is not usable | The path holds a character that cannot be sent or is longer than 4096 bytes. |
| cannot use the downloads folder | The app could not create `RFE Desktop` in your download folder. The text after it says why; check that you own the folder. |
| cannot find your Downloads folder | The system does not say where your download folder is. Create `~/Downloads` or set `XDG_DOWNLOAD_DIR`. |
| give the full path of the file, starting with / | The upload path is relative. Type the whole path. |
| that path is a symbolic link; type the real path of the file | The app does not follow a link. Type the path of the file the link points to. |
| that is not a regular file | The path is a folder, a device or something else that is not a plain file. |
| cannot read that file | The file is missing or you may not read it. The text after it says which. |
| the file changed while it was being opened; try again | The path was replaced by another file at that moment. Try again. |
| cannot write | The app could not write the unfinished download. Check free space and permissions of the download folder. |
| The downloaded copy does not match the file on the computer | The saved bytes differ from the file's SHA-256 on the computer, so the copy was deleted. Start the download again. If it repeats, the file may be changing. |
| the downloaded file could not be put in place | The finished file could not be given its name. Check the download folder's permissions. |
| the agent ended the download early | The connection ended before all the bytes arrived. Press Retry; the download continues. |
| no such transfer | The transfer is no longer in the list. |
| that transfer cannot be retried now | Retry works only on a failed or cancelled transfer. |
| a background task failed | Reading or checking a file stopped unexpectedly. Report it with the log level set to Detailed. |

In the list: "Waiting for a free slot" is a transfer queued behind two running ones, "Checking the file"
is a finished transfer being verified, and "Verified by the computer" means the computer confirmed the
file's SHA-256. A download from an older agent may finish without that line because it could not answer
the check.
