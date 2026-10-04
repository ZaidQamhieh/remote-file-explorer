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

<!-- feature:pair-inbox -->
## Pairing requests

When a phone or another computer asks to be paired with **Ask the PC to approve this computer**, you
can answer it here instead of at the terminal. On the Paired devices screen press **Pairing
requests**. It lists every request the agent is holding, oldest first:

| Column | What it is |
|---|---|
| Device | The name the asking device gave itself. It is whatever that device sent, so do not trust it on its own. If the request would take over a device that is already paired, a line under the name says which one. |
| From | The network address the request came from. |
| Waiting, Expires in | How long ago it was made, and how long you have left. A request lasts 2 minutes. |
| Match code | The code the agent worked out for this request. The device asking shows its own code. |

**Accept only if the code matches the one shown on the device asking.** The code is computed from the
certificate each side saw, so a machine in the middle shows a different one. Press **Accept** twice (the
first press only arms it and the button says so; it disarms by itself after a few seconds). The device
can then collect its login, and it starts with browse access only. **Reject** answers at once and needs no second press. Either way the row leaves the list and
the window says what it did.

The list refreshes by itself every few seconds, only while this screen is open: leaving it (Back,
Settings, signing out) stops the refreshing. **Refresh** asks again at once. Rows are updated in place,
so a button you have tabbed to keeps the keyboard focus and never moves to another request.

Only an account sign-in can answer requests. A computer paired with a code or approved on the PC sees a
warning instead of the list: sign out and sign in with the account, or answer on the PC with
`rfe-agent pair accept` or `reject`. The agent holds at most three waiting requests; a fourth device is
told the PC is busy until you answer one or one expires.

<!-- end feature:pair-inbox -->

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
| No pairing requests are waiting. | Nobody is asking to be paired right now. The list fills in by itself while the screen is open. |
| Loading pairing requests... | The window is asking the agent. If it stays, the agent is slow or unreachable; an error follows. |
| This login cannot answer pairing requests. | This computer was paired with a code or approved on the PC, and the agent lets only an account answer. Sign out and sign in with the account, or use `rfe-agent pair accept` or `reject` on the PC. |
| This agent is too old to list pairing requests | Answering from the window needs `agent-v1.43.0-rc.1` or newer. Update the agent, or answer on the PC. |
| The agent holds at most 3 waiting requests. | Shown when three are waiting: a fourth is refused (the device asking sees that the PC is busy) until you answer one or one expires. |
| Press again to accept | The first press on **Accept** only arms it. Press again within a few seconds to accept, after checking that the match code is the one shown on the device asking. |
| Accepted ..., Rejected ... | Your answer reached the agent. An accepted device collects its login on its own. |
| That request already expired or was answered on the PC. | The request ran out of time, or someone answered it (at the PC, or from another window) a moment before you did. Nothing was changed by your press. Ask the device to try again if it was a good one. |

Messages about the system keystore (`the OS keystore ...`, `no OS keystore answered`) are explained
in [keystore.md](keystore.md).
