#!/bin/bash

if [ -f "huly.conf" ]; then
    source "huly.conf"
fi

# Check for --recreate flag
RECREATE=false
if [ "$1" == "--recreate" ]; then
    RECREATE=true
fi

# Handle Caddyfile recreation or updating
if [ "$RECREATE" == true ]; then
    echo "Recreating Caddyfile from template..."
    if [[ "$HOST_ADDRESS" == "localhost"* || "$HOST_ADDRESS" == "127.0.0.1"* || "$HOST_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
        # Use the basic Caddyfile for localhost/IP addresses
        cp Caddyfile.basic Caddyfile 2>/dev/null || cat > Caddyfile << 'EOF'
{
    # Global options
    auto_https off
}

:80 {
    # Handle WebSocket upgrades and proxy headers
    header {
        # Remove Server header for security
        -Server
    }

    # Main frontend
    handle {
        reverse_proxy front:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    # Accounts service
    handle /_accounts/* {
        uri strip_prefix /_accounts
        reverse_proxy account:3000 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    # Collaborator service (WebSocket support)
    handle /_collaborator/* {
        uri strip_prefix /_collaborator
        reverse_proxy collaborator:3078 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
        }
    }

    # Transactor service (WebSocket support)
    handle /_transactor/* {
        uri strip_prefix /_transactor
        reverse_proxy transactor:3333 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
        }
    }

    # Handle JWT tokens (eyJ prefix)
    handle /eyJ* {
        reverse_proxy transactor:3333 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
        }
    }

    # Rekoni service
    handle /_rekoni/* {
        uri strip_prefix /_rekoni
        reverse_proxy rekoni:4004 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    # Stats service
    handle /_stats/* {
        uri strip_prefix /_stats
        reverse_proxy stats:4900 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    # File upload size limit
    request_body {
        max_size 100MB
    }
}
EOF
    else
        # Use the template for domain names (with automatic HTTPS)
        envsubst < .template.caddy.conf > Caddyfile
    fi
    echo "Caddyfile has been recreated."
else
    if [ ! -f "Caddyfile" ]; then
        echo "Caddyfile not found, creating from template."
        if [[ "$HOST_ADDRESS" == "localhost"* || "$HOST_ADDRESS" == "127.0.0.1"* || "$HOST_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
            # Use the basic Caddyfile for localhost/IP addresses
            cp Caddyfile.basic Caddyfile 2>/dev/null || cat > Caddyfile << 'EOF'
{
    # Global options
    auto_https off
}

:80 {
    # Handle WebSocket upgrades and proxy headers
    header {
        # Remove Server header for security
        -Server
    }

    # Main frontend
    handle {
        reverse_proxy front:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    # Accounts service
    handle /_accounts/* {
        uri strip_prefix /_accounts
        reverse_proxy account:3000 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    # Collaborator service (WebSocket support)
    handle /_collaborator/* {
        uri strip_prefix /_collaborator
        reverse_proxy collaborator:3078 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
        }
    }

    # Transactor service (WebSocket support)
    handle /_transactor/* {
        uri strip_prefix /_transactor
        reverse_proxy transactor:3333 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
        }
    }

    # Handle JWT tokens (eyJ prefix)
    handle /eyJ* {
        reverse_proxy transactor:3333 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
        }
    }

    # Rekoni service
    handle /_rekoni/* {
        uri strip_prefix /_rekoni
        reverse_proxy rekoni:4004 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    # Stats service
    handle /_stats/* {
        uri strip_prefix /_stats
        reverse_proxy stats:4900 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    # File upload size limit
    request_body {
        max_size 100MB
    }
}
EOF
        else
            # Use the template for domain names (with automatic HTTPS)
            envsubst < .template.caddy.conf > Caddyfile
        fi
    else
        echo "Caddyfile already exists. Updating host address if using template."
        echo "Run with --recreate to fully overwrite Caddyfile."
        
        # If using template and host changed, regenerate
        if [[ ! "$HOST_ADDRESS" == "localhost"* && ! "$HOST_ADDRESS" == "127.0.0.1"* && ! "$HOST_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
            envsubst < .template.caddy.conf > Caddyfile
            echo "Updated Caddyfile with new host address: $HOST_ADDRESS"
        fi
    fi
fi

echo "Caddyfile configuration:"
echo "Host Address: ${HOST_ADDRESS:-:80}"
if [[ "$HOST_ADDRESS" == "localhost"* || "$HOST_ADDRESS" == "127.0.0.1"* || "$HOST_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
    echo "SSL: Disabled (localhost/IP address detected)"
else
    echo "SSL: Automatic HTTPS enabled for domain"
fi

read -p "Do you want to reload Caddy configuration now? (Y/n): " RELOAD_CADDY
case "${RELOAD_CADDY:-Y}" in  
    [Yy]* )  
        echo -e "\033[1;32mReloading Caddy configuration...\033[0m"
        docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || \
        docker compose restart caddy
        ;;
    [Nn]* )
        echo "You can reload Caddy configuration later with:"
        echo "docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile"
        echo "or restart the caddy service with:"
        echo "docker compose restart caddy"
        ;;
esac
