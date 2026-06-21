# macOS Network, Wi-Fi and VPN Diagnostics

This toolkit diagnoses interface, Wi-Fi, DHCP, DNS and VPN problems and includes a repair workflow.

## Diagnostic usage

```bash
chmod +x src/macos_network_diagnostics.sh
sudo ./src/macos_network_diagnostics.sh --target 1.1.1.1 --dns-name example.com
```

## Repair usage

Preview repairs:

```bash
chmod +x src/macos_network_repair.sh
./src/macos_network_repair.sh --repair --dry-run
```

Apply resolver repair:

```bash
sudo ./src/macos_network_repair.sh --repair
```

Renew DHCP:

```bash
sudo ./src/macos_network_repair.sh --service "Wi-Fi" --renew-dhcp
```

Reset DNS to automatic values:

```bash
sudo ./src/macos_network_repair.sh --service "Wi-Fi" --reset-dns
```

Cycle Wi-Fi:

```bash
sudo ./src/macos_network_repair.sh --cycle-wifi
```

Manage a configured VPN connection:

```bash
./src/macos_network_repair.sh --vpn-start "Company VPN"
./src/macos_network_repair.sh --vpn-stop "Company VPN"
```

## Repair behaviour

- Flushes local resolver caches.
- Restarts the macOS name-resolution service.
- Can renew DHCP for one selected service.
- Can return one selected service to automatic DNS values.
- Can cycle the detected Wi-Fi interface.
- Can start or stop one configured VPN service.
- Supports confirmation prompts, dry-run, logs and verification.

Network sessions may be interrupted during repair. The tool does not remove VPN profiles, forget Wi-Fi networks or change proxy settings automatically.

## Author

Dewald Pretorius — L2 IT Support Engineer
