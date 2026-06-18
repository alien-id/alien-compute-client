# Alien Compute (menu-bar app)

A macOS menu-bar app that runs the compute client (`fleet-proxy`), shows balance
+ network status, lets you copy the local OpenAI-compatible URL, and reports
per-model token usage and spend for the last hour.

## Install (DMG)

```bash
./make-dmg.sh              # builds the app (bundling ../fleet-proxy) and packages "Alien Compute.dmg"
```

Open the DMG and drag **Alien Compute** into Applications. The proxy binary ships
inside the app bundle, so there's nothing else to install. The app is ad-hoc
signed (not notarized), so on first open you may need to right-click → Open.

## Build only

```bash
./build.sh                 # bundles ../fleet-proxy into "Alien Compute.app"
open "Alien Compute.app"
```

To bundle a different proxy build: `PROXY_SRC=/path/to/fleet-proxy ./build.sh`.

## First launch (onboarding)

On first launch a black, futuristic onboarding window appears: app logo +
description and a **Connect to network** button. Pressing it starts the client
and, once connected, shows the local OpenAI-compatible URL (with Copy). If the
network is unreachable it shows a notice and you can retry. Subsequent launches
skip onboarding and connect automatically. (State: `didOnboard` in `UserDefaults`.)

## What it does

- Runs `fleet-proxy -gateway <gateway> -listen 127.0.0.1:<port>` as a managed
  subprocess and stops it on quit.
- **Port:** prefers **4113**. If a leftover `fleet-proxy` holds it, that orphan
  is killed and 4113 reclaimed; if another service holds it, the next free port
  is used.
- Polls the proxy's local API every 4s (`/fleet/status`, `/fleet/capacity`).
- Menu-bar saucer icon with the live balance in USDC (or `off` / `…`).
- Menu (with SF Symbol icons): a **Connect / Disconnect** toggle on top, then
  gateway, balance, network, and a per-model breakdown of tokens consumed +
  USDC spent in the last hour. Plus Copy proxy URL, Copy wallet ID, Reconnect,
  Set gateway…, Open proxy log.

## Icons

- Menu bar: a vector flying-saucer silhouette (template image, tints to the bar).
- App / Finder / onboarding logo: a colored flying saucer drawn in Core Graphics,
  generated at build time (`tools/main.swift` → `iconutil` → `AppIcon.icns`).

## Currency

- Everything shown to the user is in **USDC**. Internally the proxy reports
  amounts in its own token; the app converts at a mock rate (`usdcPerToken`,
  default `$0.90`) in `Sources/FleetAPI.swift`.
- The balance folds in escrowed funds (unescrowed wallet + remaining escrow), so
  it reflects total available money and drops as tokens are consumed.

## Notes

- Default gateway is the live testnet (`http://15.237.243.199:9000`). Change it
  via **Set gateway…**; it persists in `UserDefaults`.
- Proxy state (keys, channel, alias pins) lives in `~/.fleet-proxy`, shared with
  the CLI. Proxy logs go to `~/Library/Logs/AlienCompute-proxy.log`.
- "Last hour" is bounded by uptime: the proxy keeps receipts in memory only, so
  the window resets when the proxy restarts.
