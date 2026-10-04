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

<!-- feature:pairing-codes -->
## Pair a phone

When you are signed in with the account, **Pair a phone with a one-time code** (under the device list)
opens a screen that makes a pairing code for the RFE phone app, so you do not have to walk to the PC and
run `rfe-agent pair`.

1. Press **Generate a code**. The app asks the agent for a code and shows it in large type with the
   time it has left (10 minutes). Nothing is made until you press the button.
2. On the phone, add this PC's address and enter the code. The phone is paired as an ordinary device.
3. Press **Select the code** (or click the code once) and Ctrl+C if you need to copy it. The app does
   not copy it for you: a code on the clipboard can be read by other programs and clipboard history.

A code works once. **Generate a new code** shows another one; it does not cancel an earlier one, which
stays valid until it is used or its time is up. The code leaves the window when you press **Back**, open
Settings, sign out, or when the time runs out, and it is never written to `state.json`, the keystore or
the log. Only an account sign-in may do this: a computer paired with a code or approved on the PC sees
"This login cannot create pairing codes" and the agent mints nothing.
<!-- /feature:pairing-codes -->

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

<!-- feature:file-browser -->
## Files

**Files** (top right, when you are signed in) browses the files the agent shares with this computer.
Opening a file selects it and shows **Download <name>** next to Refresh; pressing it starts a download on the Transfers screen (see Transfers). Going to another folder or pressing Refresh or Back drops the button. Uploads start from the Transfers screen.

1. **Locations.** The first screen lists where you may start: the folders the agent was confined to
   (`-roots`, or a per-device folder), or, when the agent has no folder limit, its drives with their
   free space. Choose one to open it.
2. **A folder** shows each entry's name, type, size (a folder shows how many items it holds, up to
   `1000+`) and modified time. A link shows where it points (`name → target`). The path above the
   list is a trail: each earlier step is a button that goes there. **Refresh** reads the folder again.
3. **Sort** by pressing a column heading; press it again to reverse. Folders always stay above files.
   The agent sends a folder by name, 500 entries at a time. If it has more, **Load more** appends the
   next page, and sorting applies only to what is loaded so far.
4. **A file** (Enter, Space or a click on its name) does nothing to the file itself in this screen: it
   is handed to the transfers screen when that is installed, and otherwise the status line says which
   file you chose. **A link** is looked up first: the agent decides whether it may be followed, and a
   link that leaves the folders the agent allows is refused with the agent's own words (below).

**Keyboard.** Tab reaches the list once; Up and Down, Home and End move between rows; Enter or Space on
a name opens a folder or chooses a file; Tab then reaches that row's Rename and Delete. Backspace goes up
one folder (from the top of a location it goes to the locations, then back). Escape closes the name box
or cancels a delete that is waiting for its second press.

**Changes.** **New folder**, **Rename** and **Delete** appear only when the agent allows this computer to
change files and is not read-only; otherwise a note says so. A computer paired with a code starts with
looking only; the owner can allow more on the PC. **Delete** moves the entry to the agent's trash, where
it can be restored, and needs a second press. There is no permanent delete here. If the agent refuses a
change anyway, you see its refusal and nothing changes. A new name is one plain name (no `/` or `\`, no
control characters, not `.` or `..`); it cannot move an entry to another folder.

Every path is checked before it is sent (it must be absolute and have no `..` step), and the agent
checks it again against the folders it allows, including links: nothing outside them is listed.

<!-- end feature:file-browser -->

<!-- feature:multi-hosts -->
## Saved hosts

You can keep several agents and switch between them. **Hosts** (top right) or **Settings**, **Saved
hosts** lists every agent you have trusted, with the account signed in to it.

- **Switch** makes that host the one the window uses. If it has a saved login you land on its device
  list without typing a password; if not, you land on its sign-in screen with the account name filled
  in. **Open** (on the host in use) just goes to its device list.
- **Rename** changes only the name shown in the list (up to 64 characters). The address, certificate
  and login are not touched.
- **Remove**, pressed twice, deletes that host's saved login from the keystore, forgets its trusted
  certificate (you compare its fingerprint again if you ever add it back) and takes it off the list. The
  device stays registered on the agent until it is revoked there: **Sign out** first if you want that.
- **Add another host** opens the first screen. Check the certificate and sign in as usual; the login you
  had on the other host stays saved.

Each host has its own certificate pin and its own login token. A token is only ever sent to the agent it
came from. The app opens on the host you used last. A host that was added before this list existed
shows up in it automatically; nothing is lost.
<!-- /feature:multi-hosts -->

## What is kept, and where

| What | Where |
|---|---|
| Device signing key, login token | the system keystore |
| Agent address, its fingerprint, account name, device id, log level | `state.json` in the app's data folder (`~/.local/share/app.rfe.desktop/` on Linux; Settings shows the exact path), readable only by you |
| Password | nowhere |
| The saved hosts: name, address, account name, device id | `hosts.json` next to `state.json`, readable only by you. No secret is in it. A host's login token is in the keystore under its own entry |

If `state.json` is damaged the app says so and does not guess; delete the file to start over (you will
compare fingerprints again).

<!-- feature:device-actions -->
## Manage devices

When you signed in with an **account**, each row of the devices list has actions (a computer paired with a
code or approved on the PC sees only itself and gets none):

- **Access** opens the device's permissions: which file actions it may use (browse, download, upload,
  change, delete, make share links), whether it may see or start apps, a read-only switch, and a folder
  limit (an absolute path inside the agent's folders; empty means no limit). Only the settings you change
  are sent. A device that itself signed in with an account ignores the file permissions; the read-only
  switch and the folder limit still apply to it.
- **Revoke** blocks the device: the agent refuses its login from then on, and the row stays in the list
  marked Revoked. It can only get back in by being paired or signed in again.
- **Remove** deletes the device's row for good (an active device is blocked at the same time).

**Revoke** and **Remove** need two presses; the first one only arms the button and the second does it.
After every action the list is loaded again from the agent.

The agent has no way to rename a device from another device: a device's name is the one it gave when it
signed in. (The PC-side `rfe-agent` shows the same names.)

**This computer's own row.** Revoking or removing it signs this window out, and changing its own access can
lock it out. The first press shows a stronger warning ("Press the button again to sign this computer out"),
and the app itself refuses the action unless that second press confirms it. After it, the window is back
at the first screen and you sign in again.

Messages of these actions:

| The window says | What it means and what to do |
|---|---|
| This login is not an admin session, so the agent will not change other devices. | The agent answered 403. Only a sign-in with the account (not a pairing code, not an approval on the PC) may revoke, remove or change other devices. Sign out and sign in with the account, or use `rfe-agent revoke`, `remove` and `jail` on the PC. |
| That device is no longer on the agent | The agent answered 404: the device was removed (here, on the PC or from another computer) before the action arrived. The list has been loaded again; nothing else is needed. |
| This agent does not support that device action | The agent is too old for it. Update the agent, or use `rfe-agent` on the PC. |
| This is the computer you are using | You tried to revoke, remove or change the access of this computer's own device without the second, confirming press. Press the button again to confirm, or leave it. |
| Could not tell which device is this computer | The saved login has no device id and the agent did not say which listed device is this one, so nothing was changed. Refresh the list and try again. |
| Press the button again to sign this computer out | The warning shown when you arm Revoke or Remove on this computer's own row. Nothing has happened yet; press the button again to do it, or press somewhere else to cancel. |
| Allowing a device to launch apps needs it to be allowed to view apps as well. | Turn on "See the apps on this PC" together with "Start approved apps". |
| No setting was changed | Saving needs at least one changed setting. |
| The folder limit must be one path, up to 4096 characters, or empty. | Type one absolute path, or clear the box for no limit. |
| The agent refused that change: ... | The agent said no, and the text after the colon is its reason, for example a folder limit that is not inside the agent's folders. Nothing was changed. |
| Revoked, Removed, Saved the access of | The action worked. "This computer is signed out; sign in again to continue." follows when it was this computer's own row. |
| The list could not be refreshed | The action worked, but loading the list again failed (the text after the colon says why). Press Refresh. |

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
| Sign out first; the saved login belongs to the current device key. | A new device key can only be made while signed out. Making one also removes the logins saved for your other agents (their devices stay registered on those agents until removed there), so you sign in to each again. |
| Signed out on this computer only | The agent could not be told. Revoke this computer on the PC (`rfe-agent revoke <id>`) so its old login stops working. |
| is damaged (...); delete it to create a new device identity | An `identity.json` left by an early version cannot be read. Delete that file; the app makes a new device key at the next sign-in. |
| cannot start network discovery, network discovery stopped | The app could not listen for mDNS answers (no network interface, or the system refused). Type the agent's address instead. |
| unknown log level | Choose one of the levels in the list. |
| is damaged (...); delete it to start over | `state.json` cannot be read. Delete it (Settings shows where) and set the app up again. |
| read, create, open, write or rename a path failed | The app's data folder cannot be used: check that it exists and that you own it. |
| tls config, http client, random | The system could not set up a secure connection or random numbers. Report it. |
| this host is not in the saved list | The host was removed (perhaps from another window) before the action ran. Close Settings and open it again. |
| enter a name for the host | The new name is empty. Type a name, or press Cancel. |
| the name can be at most 64 characters | Use a shorter name. |
| the name cannot contain control characters | The name has a line break or another control character. Type it again on one line. |
| `hosts.json` is damaged (...); delete it to start over | The list of saved hosts cannot be read. Delete `hosts.json` (Settings shows the folder): the list is rebuilt from the agents you trusted, and every login stays where it is. Until then signing in to a second agent is refused so the list is not overwritten. |
| `hosts.json` was written by a newer version of this app | A newer app wrote the list. Update this app, or delete `hosts.json` to start over as above. |
| Signed out on this host. Sign in to continue. | You switched to a host that has no saved login (you signed out of it, or only trusted it). Sign in; the account name is filled in. |
| Type the new host's address. Your current login stays saved. | Shown when you press Add another host. Nothing was changed on the host you were using. |
| No host is saved yet. | The list is empty: connect to an agent from the first screen. |
| This login cannot create pairing codes. Only a session signed in with the account can; a computer paired with a code or approved on the PC cannot. | The agent refused (`FORBIDDEN`) because this computer is not an account session. Sign out and sign in with the account, or run `rfe-agent pair` on the PC. |
| This pairing code has expired. Generate a new one. | The code's 10 minutes are up and it was removed from the window. Press **Generate a code**. |
| unexpected response: the agent sent no pairing code | The agent answered without a code. Update the agent and the app; if both are current, report it. |
| Selected. Press Ctrl+C to copy. / Select the code with the mouse, then press Ctrl+C. | Not a problem: the window selected the code for you, or could not and asks you to select it by hand. |
| No pairing requests are waiting. | Nobody is asking to be paired right now. The list fills in by itself while the screen is open. |
| Loading pairing requests... | The window is asking the agent. If it stays, the agent is slow or unreachable; an error follows. |
| This login cannot answer pairing requests. | This computer was paired with a code or approved on the PC, and the agent lets only an account answer. Sign out and sign in with the account, or use `rfe-agent pair accept` or `reject` on the PC. |
| This agent is too old to list pairing requests | Answering from the window needs `agent-v1.43.0-rc.1` or newer. Update the agent, or answer on the PC. |
| The agent holds at most 3 waiting requests. | Shown when three are waiting: a fourth is refused (the device asking sees that the PC is busy) until you answer one or one expires. |
| Press again to accept | The first press on **Accept** only arms it. Press again within a few seconds to accept, after checking that the match code is the one shown on the device asking. |
| Accepted ..., Rejected ... | Your answer reached the agent. An accepted device collects its login on its own. |
| That request already expired or was answered on the PC. | The request ran out of time, or someone answered it (at the PC, or from another window) a moment before you did. Nothing was changed by your press. Ask the device to try again if it was a good one. |

<!-- feature:file-browser -->
Messages from the file browser:

| The window says | What it means and what to do |
|---|---|
| The agent says: ... (CODE) | The agent refused or could not do what you asked, and this is its own wording and code. Common ones: `FORBIDDEN` (the path, or a link, is outside the folders the agent allows; nothing was listed or changed), `CAPABILITY_DENIED` (this computer is not allowed that action; the owner can allow it on the PC), `READ_ONLY` (the agent is in read-only mode), `CONFLICT` (that name already exists), `PATH_NOT_FOUND` (it was moved or deleted; press Refresh). |
| a path must be absolute (start with / or a drive letter) | The app refused to send a path that is not absolute. Open it from the list instead of typing it. |
| a path cannot be empty, hold a NUL character or a .. step, or be longer than 4096 bytes | The app refused to send that path. A `..` step is never sent; the agent would clean it, but the app does not rely on that. |
| a name must be 1 to 255 bytes, with no / or \, no control characters, no space at either end, and not . or .. | The name you typed for a new folder or a rename is not one plain name. Choose another. |
| the agent did not say whether the delete worked | The agent answered without a result for the entry. Press Refresh to see whether it is still there. |
| unexpected route | Internal check on the address the app asked for. Report it. |
| No folder is open to this login. | The agent shows this computer nothing to browse. The sentence after it says why: the agent confined this computer to a folder it does not allow (change it on the PC), this computer is not allowed to browse (allow it on the PC), or the agent has not shared a folder with it. |
| This folder is empty. | There is nothing in it. |
| The agent lists more items than are shown. | The folder has more entries than one page. Press **Load more**. |
| The agent is read-only, so nothing here can be created, renamed or deleted. | The agent was started with `-read-only`. |
| This computer may look but not change files on this agent. | This login has no modify or delete permission. The owner can allow it on the PC. |
| Loading folder... | The agent is answering. The previous folder stays until the new one arrives. |
| Creating the folder..., Renaming..., Moving to the trash... | A change is in progress. |
| Press Delete again to move NAME to the trash. | The first press only arms Delete. Press it again, or Escape to cancel. |
| Moved to the trash: NAME | Done. Restore it from the agent's trash. |
| Selected PATH. | You chose a file; this screen has no download. |
| Sorted by COLUMN, ascending. | Announces the new order (it says when only the loaded entries were sorted). |
| Folder name | The label of the box for a new folder (a rename says "New name for NAME"). |

<!-- end feature:file-browser -->
Messages about the system keystore (`the OS keystore ...`, `no OS keystore answered`) are explained
in [keystore.md](keystore.md).

<!-- feature:app-catalog -->
## Apps on the PC

On the devices screen, **Apps on this PC** lists the apps the PC running the agent offers (on Linux, the
applications in its menu). Each row shows the app's name, category and a short form of its catalog id.
**Launch** opens the app on the PC's own screen; press it twice, the first press only arms it and the
button then reads "Launch?". Nothing runs on this computer. This app sends the agent only the app's
catalog id, never a command or a path, and the agent decides what that id means.

What it takes:

- The owner must give this computer two rights on the agent: *view apps* (to see the list) and *launch
  apps* (to start one). Neither comes with an account sign-in or a pairing code. Without *launch apps*
  the list is shown and the Launch buttons are replaced by a note.
- Someone has to be signed in to a graphical desktop on the PC, and the PC needs `gio` for the agent to
  start anything.
- A row that says "Cannot be launched" is listed but has no way to start.
- "The PC lists no apps." means the catalog is empty, not that an error happened.

Success means the PC's launcher accepted the request, not that the app finished starting.

Messages from the agent for these two screens:

| The window says | Code | What to do |
|---|---|---|
| This computer is not allowed to see the host's apps. On the PC's agent, turn on app viewing for this computer, then refresh. | `APP_VIEW_FORBIDDEN` | The owner has not given this computer the right to see the PC's apps. An account sign-in does not include it. Turn on "view apps" for this computer's device on the agent (an account session can change it), then press Refresh. |
| This computer may see the host's apps but not start them. On the PC's agent, turn on app launching for this computer. | `APP_LAUNCH_FORBIDDEN` | This computer may list apps but not start them. Turn on "launch apps" for it on the agent (it needs "view apps" too). The Launch buttons stay hidden until then. |
| That app is no longer in the host's catalog. It may have been uninstalled. Refresh the list. | `APP_NOT_FOUND` | The app was removed from the PC after the list was loaded. Press Refresh. |
| The host has no way to start that app. It is listed but cannot be launched from here. | `APP_NOT_LAUNCHABLE` | The PC knows the app but has no way to start it (for example its desktop entry has no command, or the program it names is missing). Nothing can be done from here. |
| The host is already starting another app. Wait a moment, then try again. | `APP_LAUNCH_BUSY` | The agent starts one app at a time. Wait a few seconds and press Launch again. |
| Nobody is signed in to a graphical desktop on the host, so there is nowhere to open the app. Sign in at the PC, then try again. | `NO_INTERACTIVE_SESSION` | The agent only opens apps on a screen someone is signed in to. Sign in to the PC's desktop, then try again. |
| The host's app launcher is not available (on Linux it needs the gio tool). Install it on the PC, then try again. | `APP_LAUNCH_UNAVAILABLE` | The agent's launcher is missing. On Linux the PC needs `gio` (the `glib2` or `libglib2.0-bin` package) on the agent's PATH. |
| The host tried to start the app and could not. Check that it still works on the PC. | `APP_LAUNCH_FAILED` | The launcher accepted the request but could not start the program. Try it on the PC itself. |
| Too many requests for the app list. Wait a minute, then refresh. | `APP_CATALOG_RATE_LIMITED` | The agent allows 60 list requests a minute per computer. Wait a minute. |
| Too many app launches. The agent allows only a few per minute. Wait a minute, then try again. | `APP_LAUNCH_RATE_LIMITED` | The agent allows 5 launches a minute per computer. Wait a minute. |
| The host's operating system does not support the app catalog yet. | `APP_CATALOG_UNSUPPORTED` | The agent runs on a system with no app catalog. Nothing can be done. |
| The agent refused the app id as malformed. This is a bug in the app. | `BAD_APP_ID` | The app sent an id the agent does not accept. This is a bug in the app. Report it with the log level set to Detailed. |

Messages from this app:

| The window says | What it means and what to do |
|---|---|
| unexpected app id | The app refused to put an id that does not look like `app_` and 64 hex digits into a request. Refresh the list; if it keeps happening, report it. |
| unknown launch status | The agent answered a launch with something other than "started". Update the agent and the app; if both are current, report it. |
| This agent has no app catalog. Update the agent on the PC, then try again. | The agent is older than the app catalog and answers `/apps` with a plain 404. Update it. |
| Asked the PC to open (app name). It can take a moment to appear on its screen. | Not an error: the PC's launcher accepted the request. If nothing appears, check the PC's screen and that the app starts there. |
| Cannot be launched, Launching not allowed | A row without a Launch button: the PC has no way to start that app, or this computer lacks the *launch apps* right (see above). |
<!-- feature:health-metrics -->
## Health and metrics

On the **Paired devices** screen, **Health and metrics** shows what the agent reports about itself and,
for an administrator, how busy the PC is.

- **The agent you are connected to**: the address this computer uses and the certificate fingerprint it
  pinned for it (compare it with `rfe-agent status`), then the agent's name, version, system, whether it
  is read-only, and the addresses it reports (LAN, Tailscale, MAC).
- **Health**: that the agent answers, how long it has been running, and the free and total disk space of
  its data folder.
- **Metrics** (administrators only): processor and memory in use (percent, at the moment of reading),
  bytes received and sent since the agent started (binary units: 1 KiB is 1024 bytes), the rate those
  grew at since the previous reading, and the agent's own clock. The rate needs two readings, so the
  first shows "Needs a second reading". If a total goes down the agent restarted, and the rate says so.
- **Refresh** reads again. **Refresh every 5 seconds while this screen is open** does it by itself; it
  stops when you leave the screen, open Settings (it resumes when you come back) or an error happens.
  The window keeps only the last reading, and the agent keeps no history.

A value the agent did not send reads "not reported" (an older agent, or one that withheld it) instead
of a made-up zero. The agent does not report the state of its helper programs, so none is shown.

| The window says | What it means and what to do |
|---|---|
| Metrics are for administrators. | This computer signed in with a pairing code or was approved on the PC, so the agent answers the metrics request with 403 (`FORBIDDEN`). The rest of the screen still works. Sign out and sign in with the account (`rfe-agent adduser`) to see the metrics. |
| No metrics were reported. | The agent answered the health request but not the metrics one; the text after it says why (for example it timed out). Press Refresh to try again. |
| Uptime and disk space could not be read | The agent's status request failed; the reason follows. The health part is still current. |
| The agent did not answer within 5 seconds. | The agent did not reply in time. It may be asleep, busy, or on another network. Check that it is running and the address is right, then press Refresh. Each of the three requests has its own five second limit and they run together, so the screen never waits longer. |
| unexpected response: the agent's health answer does not say ok | The address answered with something that is not an RFE agent's health reply. Check the address and the agent version. |
| Auto-refresh stopped after an error. | The error is shown above it. Auto-refresh does not retry by itself, so an agent that is off, or a locked keystore, is not asked every five seconds. Fix the cause, then press Refresh or turn auto-refresh on again. |
| not reported | That value was missing from the agent's answer. |

<!-- feature:audit-logs -->
## Audit and logs (admin)

On the devices screen, **Audit and logs (admin)** opens what the agent has recorded. It needs an
account sign-in: the agent refuses it for a computer paired with a code or approved on the PC, because
the trail describes every device, not just this one.

- **Audit log** (the default): pairings, registrations, sign-ins (failed ones included), device revokes,
  removals and changes, share links, agent restarts and app launches, newest first. File operations are
  deliberately not recorded. The agent keeps the most recent 5000 events and sends 100 at a time;
  **Load more** fetches the next older 100 and the button goes away when nothing older is left.
- **Agent log**: the last ~200 lines of the agent's own log, which it reads from the systemd journal
  (`journalctl --user -u rfe-agent.service`). It is empty when the agent does not run as that service.
- **Event**, **Contains** (agent log only) and **Time** narrow what is already loaded; they do not ask the
  agent again. To look further back, press **Load more** first. **Refresh** reads the newest events again.
- Times are shown in this computer's local time. Point at a time to see the exact timestamp the agent
  recorded.
- The text of an event (the name of a device or of an account somebody tried to sign in with) comes from
  whoever sent it, so the app shows it as plain text, replaces control characters, and cuts long text with
  an ellipsis. The full text, up to 400 characters, is in the tooltip of a cut cell.

| The window says | What it means and what to do |
|---|---|
| This login cannot read the audit log or the agent log. | The agent refused (403 FORBIDDEN). Sign out and sign in with an account (`rfe-agent adduser`), not a pairing code or an approval on the PC. |
| The audit log is empty. | The agent has recorded nothing yet. |
| No loaded event matches these filters. | Nothing already loaded fits the Event and Time choices. Widen them, or press **Load more** to look further back. |
| No log line matches these filters. | Nothing in the agent's last lines fits the text and Time. Clear them. |
| The agent's log is empty. | The agent could not read a journal. Run it as the `rfe-agent` service (`rfe-agent setup`), or read its output where you started it. |
| unexpected audit cursor, the page size must be | A bug in the app: it asked for a page the agent does not have. Report it with the log level set to Detailed. |

Any other message here (the agent is unreachable, the login was revoked) is one of the messages in the
tables above.
<!-- /feature:audit-logs -->

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
