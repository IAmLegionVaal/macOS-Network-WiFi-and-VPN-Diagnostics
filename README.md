# macOS Network, Wi-Fi and VPN Diagnostics

A read-only Bash toolkit for collecting interface, Wi-Fi, DHCP, DNS, route, proxy, VPN, reachability, and recent network-event evidence.

## Usage

```bash
chmod +x src/macos_network_diagnostics.sh
sudo ./src/macos_network_diagnostics.sh --target 1.1.1.1 --dns-name example.com
```

## Checks performed

- Hardware ports and network services
- Interface, route, ARP, DNS, DHCP, Wi-Fi, proxy, and VPN information
- Ping, DNS lookup, route, and HTTPS reachability tests
- Recent network, Wi-Fi, DHCP, and VPN log events
- Text, CSV, and JSON reports

## Safety

The script does not join networks, change DNS, renew DHCP, connect VPNs, alter proxies, or modify interfaces.

## Author

Dewald Pretorius — L2 IT Support Engineer
