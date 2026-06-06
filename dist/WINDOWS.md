# Running the agent on Windows

The agent is a single self-contained `.exe` — no install, no runtime, no terminal knowledge needed.

## 1. Get the file onto the Windows PC
Copy `rfe-agent-windows-amd64.exe` to the Windows machine (USB stick, Tailscale file send,
shared folder, cloud drive — whatever you use). Put it anywhere, e.g. your Desktop.

## 2. Run it
Double-click `rfe-agent-windows-amd64.exe`.

- A **console window** opens showing the agent's cert fingerprint, a **pairing code**, and a QR code.
- **Windows SmartScreen** may say "Windows protected your PC" (the .exe isn't code-signed yet) →
  click **More info → Run anyway**.
- **Windows Firewall** will pop up asking to allow network access → tick **Private networks** and
  click **Allow access**. (This is what lets your phone reach it.)

Keep the console window open while you use the app. Closing it stops the agent.

## 3. Find the PC's address
Open Command Prompt and run `ipconfig` — note the **IPv4 Address** (e.g. `192.168.1.50`).
If both devices are on Tailscale, you can use the PC's Tailscale name/IP instead.

## 4. Pair from the phone
In the app: **Add computer → Manual tab** → enter:
- **Address:** `<that-ip>:8765`  (e.g. `192.168.1.50:8765`)
- **Pairing code:** the code shown in the console window

That's it — the app supports multiple computers, so your Windows PC shows up alongside any others.
You'll see `C:\`, `D:\`, etc. as drives.

## Notes
- Default port is `8765`. To change it: run from a terminal as
  `rfe-agent-windows-amd64.exe -addr 0.0.0.0:9000`.
- Data (TLS cert, device DB) is stored under `%AppData%\remote-file-explorer`.
- Running always-on as a proper **Windows Service** (auto-start, no console window) is on the
  roadmap (Phase 7) — for now, running the .exe directly is the way to test.
