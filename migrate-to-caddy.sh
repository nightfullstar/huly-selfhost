#!/bin/bash

echo "Huly Self-Host: ngecho "Step 4: Uecho "Step 6: Starting services with Caddy..."dating configuration..."
if [ -f "huly.conf" ]; then
    # Update REVERSE_PROXY in config
    if grep -q "REVERSE_PROXY=" huly.conf; then
        sed -i 's/REVERSE_PROXY=.*/REVERSE_PROXY=caddy/' huly.conf
    else
        # Add REVERSE_PROXY if it doesn't exist
        sed -i '3i REVERSE_PROXY=caddy' huly.conf
    fi
    echo "Updated huly.conf to use Caddy"
fi

echo "Step 5: Generating Caddyfile..."nx to Caddy Migration Script"
echo "=============================================="

# Check if huly.conf exists
if [ ! -f "huly.conf" ]; then
    echo "Error: huly.conf not found. Please run ./setup.sh first."
    exit 1
fi

source "huly.conf"

echo "Current configuration:"
echo "Host Address: $HOST_ADDRESS"
echo "HTTP Port: $HTTP_PORT"
echo "HTTP Bind: ${HTTP_BIND:-all interfaces}"

read -p "This will migrate from nginx to Caddy. Continue? (y/N): " CONFIRM
case "${CONFIRM}" in
    [Yy]* )
        ;;
    * )
        echo "Migration cancelled."
        exit 0
        ;;
esac

echo "Step 1: Stopping current services..."
docker compose down

echo "Step 2: Backing up nginx configuration..."
if [ -f "nginx.conf" ]; then
    cp nginx.conf nginx.conf.backup
    echo "nginx.conf backed up to nginx.conf.backup"
fi

echo "Step 3: Generating Caddyfile..."
./caddy.sh --recreate

echo "Step 4: Starting services with Caddy..."
docker compose up -d

echo ""
echo "Migration complete!"
echo ""
echo "Your nginx configuration has been backed up to nginx.conf.backup"
echo "The new Caddy configuration is in the Caddyfile"
echo ""
echo "To manage Caddy configuration:"
echo "  ./caddy.sh                    # Update configuration"
echo "  ./caddy.sh --recreate         # Recreate from template"
echo ""
echo "If you're using nginx outside of Docker, remember to:"
echo "1. Remove the nginx symlink: sudo rm /etc/nginx/sites-enabled/huly.conf"
echo "2. Reload nginx: sudo nginx -s reload"
echo ""
echo "Your Huly instance should now be running with Caddy!"

if [[ "$HOST_ADDRESS" != "localhost"* && "$HOST_ADDRESS" != "127.0.0.1"* && ! "$HOST_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
    echo ""
    echo "🔒 SSL Notice: Since you're using a domain name ($HOST_ADDRESS),"
    echo "   Caddy will automatically obtain SSL certificates from Let's Encrypt."
    echo "   This may take a few moments on first startup."
fi
