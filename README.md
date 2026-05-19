# Introducing: **FleetForge**

_A hardened, one-shot FleetDM deployment script forged for secure infra labs and production bootstrap._

You can also go with:

- **GhostFleet**
- **FleetShield**
- **IronFleet**
- **FleetOps Bootstrap**
- **BlackDock Fleet**
- **Fleet Bastion**
- **RedForge Fleet**

My favorite for this project is **FleetForge** because the script is basically building a hardened FleetDM stack from scratch with automated security controls.

---

# GitHub Documentation — FleetForge

## FleetForge

Secure, Automated FleetDM Deployment & Hardening Script

> One-shot deployment script for FleetDM with hardened MySQL, Redis, Caddy reverse proxy, IP allowlisting, systemd sandboxing, and automated production bootstrap.

---

## Features

- Fully automated FleetDM installation
- Automatic latest release fetching from GitHub API
- Hardened MySQL configuration
- Hardened Redis configuration
- Least-privilege Fleet database user
- Secure systemd sandboxing
- Caddy reverse proxy setup
- Automatic HTTPS via Caddy
- IP allowlisting for admin access
- UFW firewall bootstrap
- Strict localhost-only backend exposure
- Automatic validation and service health checks
- Defensive defaults throughout deployment

---

## Architecture

```
                INTERNET
                    |
         [ Caddy Reverse Proxy ]
                    |
        +---------------------------+
        | HTTPS + IP Allowlisting   |
        +---------------------------+
                    |
             127.0.0.1:8080
                    |
                [ FleetDM ]
                    |
      +---------------------------+
      | MySQL        Redis        |
      | 127.0.0.1   127.0.0.1     |
      +---------------------------+

```

---

# What This Script Installs

|Component|Purpose|
|---|---|
|FleetDM|Endpoint management platform|
|MySQL|Fleet backend database|
|Redis|Queue/cache backend|
|Caddy|Reverse proxy + automatic TLS|
|UFW|Basic firewall rules|

---

# Security Hardening Included

## MySQL Hardening

- Binds MySQL to localhost only
- Removes anonymous users
- Removes remote root access
- Removes test databases
- Disables `local_infile`
- Disables symbolic links

---

## Redis Hardening

- Binds Redis locally only
- Enables protected mode
- Requires password authentication
- Disables dangerous commands:
    - `FLUSHDB`
    - `FLUSHALL`
    - `CONFIG`
    - `SHUTDOWN`

---

## FleetDM Hardening

The generated systemd service includes:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `PrivateDevices=true`
- `ProtectSystem=full`
- `ProtectHome=true`
- `ProtectKernelTunables=true`
- `ProtectControlGroups=true`
- `RestrictRealtime=true`
- `RestrictSUIDSGID=true`
- `LockPersonality=true`
- `MemoryDenyWriteExecute=true`

---

## Caddy Protection

- Automatic HTTPS
- Reverse proxy isolation
- IP allowlisting
- Backend hidden behind localhost-only exposure

Example generated policy:

```
@blocked {    not remote_ip YOUR_ALLOWED_IPS}respond @blocked "Forbidden" 403reverse_proxy 127.0.0.1:8080
```

---

# Requirements

- Ubuntu/Debian-based server
- Root privileges
- Public domain name
- DNS pointed to the server
- Ports:
    - 80/tcp
    - 443/tcp

---

# Installation

## Clone Repository

```
git clone https://github.com/YOUR_USERNAME/fleetforge.gitcd fleetforge
```

---

## Make Script Executable

```
chmod +x fleetforge.sh
```

---

## Run Installer

```
sudo ./fleetforge.sh
```

---

# During Installation

The installer will prompt for:

- Fleet database password
- Redis password
- Domain name
- Whitelisted admin IPs

Example:

```
ENTER DOMAIN NAME: fleet.example.comENTER WHITELISTED IPs:1.1.1.1 2.2.2.2
```

---

# Result

After installation:

- FleetDM runs behind HTTPS
- MySQL is localhost-only
- Redis is localhost-only
- Caddy proxies securely
- Admin panel restricted by IP
- Firewall configured automatically

---

# Default Paths

|Path|Purpose|
|---|---|
|`/etc/fleet/fleet.yml`|Fleet configuration|
|`/var/lib/fleet`|Fleet data|
|`/etc/caddy/Caddyfile`|Caddy configuration|
|`/etc/systemd/system/fleet.service`|Fleet systemd service|

---

# Service Management

## FleetDM

```
systemctl status fleetsystemctl restart fleetjournalctl -u fleet -f
```

---

## Caddy

```
systemctl status caddyjournalctl -u caddy -f
```

---

## Redis

```
systemctl status redis-server
```

---

## MySQL

```
systemctl status mysql
```

---

# Verification

## Check Fleet Listening

```
lsof -i :8080
```

---

## Check HTTPS

```
curl -I https://your-domain.com
```

---

## Validate Redis Authentication

```
REDISCLI_AUTH=YOUR_PASSWORD redis-cli ping
```

Expected output:

```
PONG
```

---

# Operational Recommendations

## Strongly Recommended

- Put Fleet behind VPN access
- Restrict SSH via security groups
- Enable automatic security updates
- Use fail2ban
- Centralize logs
- Use external database backups
- Monitor Caddy certificates
- Rotate Redis/MySQL credentials periodically

---

# Future Improvements

Potential roadmap:

- Google SSO integration
- Cloudflare Access support
- Docker deployment mode
- NetBird/Tailscale integration
- Automated backup jobs
- CIS benchmark enforcement
- CrowdSec integration
- Audit logging enhancements
- Terraform deployment support

---

# Disclaimer

This script is designed for secure self-hosted FleetDM deployments and lab environments. Always review configurations before production deployment.
