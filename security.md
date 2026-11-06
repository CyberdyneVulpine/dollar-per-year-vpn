# Security and privacy

Quick reality check before you rely on this for anything serious.

**Good fit:** cheap exit in a country you pick (geo blocks, "show up as NYC", routing your own traffic). You control the box and the WireGuard keys.

**Weak fit:** hiding who you are from someone looking at the exit IP. That IP is basically yours. A big commercial VPN puts tons of users on the same addresses, so "this IP did something" is harder to pin on one person. You don't get that crowd effect on a lone VPS.

Your host still has any info you give them (although prepaid credit cards exist). WireGuard encrypts the tunnel; it doesn't make you invisible. Log into normal accounts and those sites still know it's you.

**Keep configs private.** A `.conf` or QR is full access. Use `wg-remove` when you drop a device. Some websites block datacenter IPs no matter what.

Not legal advice. If you need real anonymity, this isn't the guide for that.
