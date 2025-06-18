#!/bin/bash

echo "Huly Self-Host: Caddy to nginx Migration Script"
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

echo ""
echo "⚠️  Warning: This will switch from Caddy back to nginx."
echo "   You'll need to have nginx installed on your system and manually"
echo "   configure SSL certificates if using HTTPS."
echo ""

read -p "Continue with migration to nginx? (y/N): " CONFIRM
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

echo "Step 2: Backing up Caddy configuration..."
if [ -f "Caddyfile" ]; then
    cp Caddyfile Caddyfile.backup
    echo "Caddyfile backed up to Caddyfile.backup"
fi

echo "Step 3: Updating docker-compose.yml..."
# Replace caddy service with nginx service
sed -i.bak '/caddy:/,/restart: unless-stopped/c\
  nginx:\
    image: "nginx:1.21.3"\
    ports:\
      - "${HTTP_BIND}:${HTTP_PORT}:80"\
    volumes:\
      - ./.huly.nginx:/etc/nginx/conf.d/default.conf\
    restart: unless-stopped' compose.yml

# Remove caddy volumes
sed -i '/caddy_data:/d' compose.yml
sed -i '/caddy_config:/d' compose.yml

echo "Step 4: Updating configuration..."
if [ -f "huly.conf" ]; then
    # Update REVERSE_PROXY in config
    if grep -q "REVERSE_PROXY=" huly.conf; then
        sed -i 's/REVERSE_PROXY=.*/REVERSE_PROXY=nginx/' huly.conf
    else
        # Add REVERSE_PROXY if it doesn't exist
        sed -i '3i REVERSE_PROXY=nginx' huly.conf
    fi
    echo "Updated huly.conf to use nginx"
fi

echo "Step 5: Generating nginx configuration..."
./nginx.sh --recreate

echo "Step 6: Starting services with nginx..."
docker compose up -d

echo ""
echo "Migration complete!"
echo ""
echo "Your Caddy configuration has been backed up to Caddyfile.backup"
echo "The new nginx configuration is in nginx.conf and .huly.nginx"
echo ""
echo "Next steps for nginx setup:"
echo "1. Link the nginx config: sudo ln -s \$(pwd)/nginx.conf /etc/nginx/sites-enabled/huly.conf"
echo "2. Test nginx config: sudo nginx -t"
echo "3. Reload nginx: sudo nginx -s reload"
echo ""
echo "To manage nginx configuration:"
echo "  ./nginx.sh                    # Update configuration"
echo "  ./nginx.sh --recreate         # Recreate from template"
echo ""

if [[ -n "$SECURE" ]]; then
    echo "🔒 SSL Notice: You'll need to manually configure SSL certificates"
    echo "   for nginx. The generated nginx.conf includes SSL configuration"
    echo "   but you'll need to add your certificate paths."
fi
