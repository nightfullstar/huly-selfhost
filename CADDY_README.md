# Huly Self-Host with Caddy

This Huly self-host setup has been configured to use Caddy as the reverse proxy instead of nginx. Caddy provides automatic HTTPS, easier configuration, and better WebSocket support out of the box.

## Benefits of Using Caddy

- **Automatic HTTPS**: Caddy automatically obtains and renews SSL certificates for domain names
- **Simpler Configuration**: JSON or Caddyfile format is more readable than nginx config
- **Built-in WebSocket Support**: No need for special upgrade headers configuration
- **Zero-Downtime Reloads**: Configuration changes can be applied without stopping the service

## Quick Start

1. Run the setup script:
   ```bash
   ./setup.sh
   ```

2. The script will automatically generate a `Caddyfile` based on your configuration.

## Configuration Files

- `Caddyfile` - Main Caddy configuration (auto-generated)
- `.template.caddy.conf` - Template for domain-based configurations
- `caddy.sh` - Script to manage Caddy configuration
- `huly.conf` - Environment variables for the setup

## SSL/HTTPS Configuration

### For Domain Names
When you configure a domain name (e.g., `huly.example.com`), Caddy will:
- Automatically obtain SSL certificates from Let's Encrypt
- Redirect HTTP to HTTPS
- Handle certificate renewals

### For Localhost/IP Addresses
When using localhost or IP addresses, Caddy will:
- Serve over HTTP only (port 80)
- Disable automatic HTTPS

## Managing the Configuration

### Regenerate Caddyfile
```bash
./caddy.sh --recreate
```

### Reload Configuration (without downtime)
```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### Restart Caddy Service
```bash
docker compose restart caddy
```

## Port Configuration

- **HTTP_PORT**: Port for HTTP traffic (default: 80)
- **HTTP_BIND**: IP to bind HTTP to (default: all interfaces)
- **HTTPS_PORT**: Port for HTTPS traffic (default: 443)  
- **HTTPS_BIND**: IP to bind HTTPS to (default: all interfaces)

## Migrating from nginx

If you're migrating from the nginx setup:

1. Stop the current services:
   ```bash
   docker compose down
   ```

2. Update your configuration:
   ```bash
   ./setup.sh
   ```

3. Start with Caddy:
   ```bash
   docker compose up -d
   ```

## Troubleshooting

### Check Caddy Logs
```bash
docker compose logs caddy
```

### Validate Caddyfile Syntax
```bash
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

### Test Configuration
```bash
docker compose exec caddy caddy fmt --overwrite /etc/caddy/Caddyfile
```

## Service Routes

The following routes are configured:

- `/` - Main Huly frontend (port 8080)
- `/_accounts/*` - Account service (port 3000)
- `/_collaborator/*` - Collaborator service with WebSocket support (port 3078)
- `/_transactor/*` - Transactor service with WebSocket support (port 3333)
- `/eyJ*` - JWT token handling (transactor)
- `/_rekoni/*` - Rekoni service (port 4004)
- `/_stats/*` - Stats service (port 4900)

## Advanced Configuration

You can manually edit the `Caddyfile` for advanced configurations. Some examples:

### Custom Headers
```caddyfile
header {
    X-Custom-Header "value"
    -Server
}
```

### Rate Limiting
```caddyfile
rate_limit {
    zone static_ip 100r/m
}
```

### Custom Error Pages
```caddyfile
handle_errors {
    respond "Custom error page" 500
}
```

Remember to reload the configuration after making changes:
```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```
