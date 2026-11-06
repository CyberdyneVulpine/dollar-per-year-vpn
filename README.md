# Dollar per year VPN

_Stop paying VPN providers too much money._

This is a guide for running your own WireGuard VPN on a tiny VPS that **costs about a dollar a year** (often less). You rent the box, you hold the keys, and you pick where your traffic exits.

This repo is the guide itself: step-by-step markdown plus a shell script you can pull straight from GitHub onto the server.

## What you'll create

- A small Alpine Linux VPS (the writeup uses [TierHive](https://tierhive.com/) and their cheapest tier)
- WireGuard on UDP with a forwarded port from the host panel
- Helper commands on the server: `wg-add`, `wg-remove`, `wg-list`

Nothing here is a hosted service. It is instructions and scripts you run on hardware you pay for.

## How to read it

Go in order:

1. **[Server setup](server-setup.md)** - account, create the VPS, log in, updates, autoupdate cron
2. **[WireGuard setup](wireguard-setup.md)** - install script, add phones/laptops, list or revoke clients

See also **[Security and privacy](security.md)** (what this is and is not good for).

One-liner installs (run on the server):

```sh
# Updates + daily autoupdate (server setup section 4)
curl -fsSL https://raw.githubusercontent.com/CyberdyneVulpine/dollar-per-year-vpn/main/server-updates.sh | sh

# WireGuard + wg-add / wg-remove / wg-list
curl -fsSL https://raw.githubusercontent.com/CyberdyneVulpine/dollar-per-year-vpn/main/wireguard-setup.sh | sh
```

Scripts: [`server-updates.sh`](server-updates.sh), [`wireguard-setup.sh`](wireguard-setup.sh)

## Notes

- Costs and panel URLs in the guide are tied to TierHive; the ideas transfer to other providers if you adjust ports and networking.
- Rerunning `wireguard-setup.sh` wipes existing VPN clients on the server. See the WireGuard doc before you run it twice.
