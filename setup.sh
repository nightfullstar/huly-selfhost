#!/usr/bin/env bash

HULY_VERSION="v0.6.501"
DOCKER_NAME="huly"
CONFIG_FILE="huly.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Choose reverse proxy
while true; do
    if [[ -n "$REVERSE_PROXY" ]]; then
        prompt_type="current"
        prompt_value="${REVERSE_PROXY}"
    else
        prompt_type="default"
        prompt_value="caddy"
    fi
    echo ""
    echo "Choose your reverse proxy:"
    echo "1) Caddy (Recommended) - Automatic HTTPS, easier configuration"
    echo "2) nginx - Traditional option, requires system installation"
    echo ""
    read -p "Select reverse proxy [${prompt_type}: ${prompt_value}] (1-2 or caddy/nginx): " input
    
    case "${input}" in
        1|caddy)
            _REVERSE_PROXY="caddy"
            break;;
        2|nginx)
            _REVERSE_PROXY="nginx"
            break;;
        "")
            _REVERSE_PROXY="${REVERSE_PROXY:-caddy}"
            break;;
        *)
            echo "Invalid input. Please enter 1, 2, caddy, or nginx.";;
    esac
done

while true; do
    if [[ -n "$HOST_ADDRESS" ]]; then
        prompt_type="current"
        prompt_value="${HOST_ADDRESS}"
    else
        prompt_type="default"
        prompt_value="localhost"
    fi
    read -p "Enter the host address (domain name or IP) [${prompt_type}: ${prompt_value}]: " input
    _HOST_ADDRESS="${input:-${HOST_ADDRESS:-localhost}}"
    break
done

while true; do
    if [[ -n "$HTTP_PORT" ]]; then
        prompt_type="current"
        prompt_value="${HTTP_PORT}"
    else
        prompt_type="default"
        prompt_value="80"
    fi
    read -p "Enter the port for HTTP [${prompt_type}: ${prompt_value}]: " input
    _HTTP_PORT="${input:-${HTTP_PORT:-80}}"
    if [[ "$_HTTP_PORT" =~ ^[0-9]+$ && "$_HTTP_PORT" -ge 1 && "$_HTTP_PORT" -le 65535 ]]; then
        break
    else
        echo "Invalid port. Please enter a number between 1 and 65535."
    fi
done

echo "$_HOST_ADDRESS $HOST_ADDRESS $_HTTP_PORT $HTTP_PORT"

if [[ "$_HOST_ADDRESS" == "localhost" || "$_HOST_ADDRESS" == "127.0.0.1" || "$_HOST_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:?$ ]]; then
    _HOST_ADDRESS="${_HOST_ADDRESS%:}:${_HTTP_PORT}"
    SECURE=""
else
    while true; do
        if [[ -n "$SECURE" ]]; then
            prompt_type="current"
            prompt_value="Yes"
        else
            prompt_type="default"
            prompt_value="No"
        fi
        read -p "Will you serve Huly over SSL? (y/n) [${prompt_type}: ${prompt_value}]: " input
        case "${input}" in
            [Yy]* )
                _SECURE="true"; break;;
            [Nn]* )
                _SECURE=""; break;;
            "" )
                _SECURE="${SECURE:+true}"; break;;
            * )
                echo "Invalid input. Please enter Y or N.";;
        esac
    done
fi

SECRET=false
if [ "$1" == "--secret" ]; then
  SECRET=true
fi

if [ ! -f .huly.secret ] || [ "$SECRET" == true ]; then
  openssl rand -hex 32 > .huly.secret
  echo "Secret generated and stored in .huly.secret"
else
  echo -e "\033[33m.huly.secret already exists, not overwriting."
  echo "Run this script with --secret to generate a new secret."
fi

export REVERSE_PROXY=$_REVERSE_PROXY
export HOST_ADDRESS=$_HOST_ADDRESS
export SECURE=$_SECURE
export HTTP_PORT=$_HTTP_PORT
export HTTP_BIND=$HTTP_BIND
export HTTPS_PORT=${HTTPS_PORT:-443}
export HTTPS_BIND=${HTTPS_BIND:-}
export TITLE=${TITLE:-Huly}
export DEFAULT_LANGUAGE=${DEFAULT_LANGUAGE:-en}
export LAST_NAME_FIRST=${LAST_NAME_FIRST:-true}
export HULY_SECRET=$(cat .huly.secret)

envsubst < .template.huly.conf > $CONFIG_FILE

# Generate docker-compose.yml based on reverse proxy choice
if [ "$_REVERSE_PROXY" = "nginx" ]; then
    echo "Generating docker-compose.yml for nginx..."
    cat > compose.yml << 'EOF'
name: ${DOCKER_NAME}
version: "3"
services:
  nginx:
    image: "nginx:1.21.3"
    ports:
      - "${HTTP_BIND}:${HTTP_PORT}:80"
    volumes:
      - ./.huly.nginx:/etc/nginx/conf.d/default.conf
    restart: unless-stopped

  mongodb:
    image: "mongo:7-jammy"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - db:/data/db
    restart: unless-stopped

  minio:
    image: "minio/minio"
    command: server /data --address ":9000" --console-address ":9001"
    volumes:
      - files:/data
    restart: unless-stopped

  elastic:
    image: "elasticsearch:7.14.2"
    command: |
      /bin/sh -c "./bin/elasticsearch-plugin list | grep -q ingest-attachment || yes | ./bin/elasticsearch-plugin install --silent ingest-attachment;
      /usr/local/bin/docker-entrypoint.sh eswrapper"
    volumes:
      - elastic:/usr/share/elasticsearch/data
    environment:
      - ELASTICSEARCH_PORT_NUMBER=9200
      - BITNAMI_DEBUG=true
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms1024m -Xmx1024m
      - http.cors.enabled=true
      - http.cors.allow-origin=http://localhost:8082
    healthcheck:
      interval: 20s
      retries: 10
      test: curl -s http://localhost:9200/_cluster/health | grep -vq '"status":"red"'
    restart: unless-stopped

  rekoni:
    image: hardcoreeng/rekoni-service:${HULY_VERSION}
    environment:
      - SECRET=${SECRET}
    deploy:
      resources:
        limits:
          memory: 500M
    restart: unless-stopped

  transactor:
    image: hardcoreeng/transactor:${HULY_VERSION}
    environment:
      - SERVER_PORT=3333
      - SERVER_SECRET=${SECRET}
      - SERVER_CURSOR_MAXTIMEMS=30000
      - DB_URL=mongodb://mongodb:27017
      - MONGO_URL=mongodb://mongodb:27017
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - FRONT_URL=http://localhost:8087
      - ACCOUNTS_URL=http://account:3000
      - FULLTEXT_URL=http://fulltext:4700
      - STATS_URL=http://stats:4900
      - LAST_NAME_FIRST=${LAST_NAME_FIRST:-true}
    restart: unless-stopped

  collaborator:
    image: hardcoreeng/collaborator:${HULY_VERSION}
    environment:
      - COLLABORATOR_PORT=3078
      - SECRET=${SECRET}
      - ACCOUNTS_URL=http://account:3000
      - DB_URL=mongodb://mongodb:27017
      - STATS_URL=http://stats:4900
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
    restart: unless-stopped

  account:
    image: hardcoreeng/account:${HULY_VERSION}
    environment:
      - SERVER_PORT=3000
      - SERVER_SECRET=${SECRET}
      - DB_URL=mongodb://mongodb:27017
      - MONGO_URL=mongodb://mongodb:27017
      - TRANSACTOR_URL=ws://transactor:3333;ws${SECURE:+s}://${HOST_ADDRESS}/_transactor
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - FRONT_URL=http://front:8080
      - STATS_URL=http://stats:4900
      - MODEL_ENABLED=*
      - ACCOUNTS_URL=http://localhost:3000
      - ACCOUNT_PORT=3000
    restart: unless-stopped

  workspace:
    image: hardcoreeng/workspace:${HULY_VERSION}
    environment:
      - SERVER_SECRET=${SECRET}
      - DB_URL=mongodb://mongodb:27017
      - MONGO_URL=mongodb://mongodb:27017
      - TRANSACTOR_URL=ws://transactor:3333;ws${SECURE:+s}://${HOST_ADDRESS}/_transactor
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - MODEL_ENABLED=*
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
    restart: unless-stopped

  front:
    image: hardcoreeng/front:${HULY_VERSION}
    environment:
      - SERVER_PORT=8080
      - SERVER_SECRET=${SECRET}
      - LOVE_ENDPOINT=http${SECURE:+s}://${HOST_ADDRESS}/_love
      - ACCOUNTS_URL=http${SECURE:+s}://${HOST_ADDRESS}/_accounts
      - REKONI_URL=http${SECURE:+s}://${HOST_ADDRESS}/_rekoni
      - CALENDAR_URL=http${SECURE:+s}://${HOST_ADDRESS}/_calendar
      - GMAIL_URL=http${SECURE:+s}://${HOST_ADDRESS}/_gmail
      - TELEGRAM_URL=http${SECURE:+s}://${HOST_ADDRESS}/_telegram
      - STATS_URL=http${SECURE:+s}://${HOST_ADDRESS}/_stats
      - UPLOAD_URL=/files
      - ELASTIC_URL=http://elastic:9200
      - COLLABORATOR_URL=ws${SECURE:+s}://${HOST_ADDRESS}/_collaborator
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - DB_URL=mongodb://mongodb:27017
      - MONGO_URL=mongodb://mongodb:27017
      - TITLE=${TITLE:-Huly Self Host}
      - DEFAULT_LANGUAGE=${DEFAULT_LANGUAGE:-en}
      - LAST_NAME_FIRST=${LAST_NAME_FIRST:-true}
      - DESKTOP_UPDATES_CHANNEL=selfhost
    restart: unless-stopped

  fulltext:
    image: hardcoreeng/fulltext:${HULY_VERSION}
    environment:
      - SERVER_SECRET=${SECRET}
      - DB_URL=mongodb://mongodb:27017
      - FULLTEXT_DB_URL=http://elastic:9200
      - ELASTIC_INDEX_NAME=huly_storage_index
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - REKONI_URL=http://rekoni:4004
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
    restart: unless-stopped

  stats:
    image: hardcoreeng/stats:${HULY_VERSION}
    environment:
      - PORT=4900
      - SERVER_SECRET=${SECRET}
    restart: unless-stopped
volumes:
  db:
  elastic:
  files:
EOF
else
    echo "Generating docker-compose.yml for Caddy..."
    cat > compose.yml << 'EOF'
name: ${DOCKER_NAME}
version: "3"
services:
  caddy:
    image: "caddy:2-alpine"
    ports:
      - "${HTTP_BIND}:${HTTP_PORT}:80"
      - "${HTTPS_BIND:-}:${HTTPS_PORT:-443}:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped

  mongodb:
    image: "mongo:7-jammy"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - db:/data/db
    restart: unless-stopped

  minio:
    image: "minio/minio"
    command: server /data --address ":9000" --console-address ":9001"
    volumes:
      - files:/data
    restart: unless-stopped

  elastic:
    image: "elasticsearch:7.14.2"
    command: |
      /bin/sh -c "./bin/elasticsearch-plugin list | grep -q ingest-attachment || yes | ./bin/elasticsearch-plugin install --silent ingest-attachment;
      /usr/local/bin/docker-entrypoint.sh eswrapper"
    volumes:
      - elastic:/usr/share/elasticsearch/data
    environment:
      - ELASTICSEARCH_PORT_NUMBER=9200
      - BITNAMI_DEBUG=true
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms1024m -Xmx1024m
      - http.cors.enabled=true
      - http.cors.allow-origin=http://localhost:8082
    healthcheck:
      interval: 20s
      retries: 10
      test: curl -s http://localhost:9200/_cluster/health | grep -vq '"status":"red"'
    restart: unless-stopped

  rekoni:
    image: hardcoreeng/rekoni-service:${HULY_VERSION}
    environment:
      - SECRET=${SECRET}
    deploy:
      resources:
        limits:
          memory: 500M
    restart: unless-stopped

  transactor:
    image: hardcoreeng/transactor:${HULY_VERSION}
    environment:
      - SERVER_PORT=3333
      - SERVER_SECRET=${SECRET}
      - SERVER_CURSOR_MAXTIMEMS=30000
      - DB_URL=mongodb://mongodb:27017
      - MONGO_URL=mongodb://mongodb:27017
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - FRONT_URL=http://localhost:8087
      - ACCOUNTS_URL=http://account:3000
      - FULLTEXT_URL=http://fulltext:4700
      - STATS_URL=http://stats:4900
      - LAST_NAME_FIRST=${LAST_NAME_FIRST:-true}
    restart: unless-stopped

  collaborator:
    image: hardcoreeng/collaborator:${HULY_VERSION}
    environment:
      - COLLABORATOR_PORT=3078
      - SECRET=${SECRET}
      - ACCOUNTS_URL=http://account:3000
      - DB_URL=mongodb://mongodb:27017
      - STATS_URL=http://stats:4900
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
    restart: unless-stopped

  account:
    image: hardcoreeng/account:${HULY_VERSION}
    environment:
      - SERVER_PORT=3000
      - SERVER_SECRET=${SECRET}
      - DB_URL=mongodb://mongodb:27017
      - MONGO_URL=mongodb://mongodb:27017
      - TRANSACTOR_URL=ws://transactor:3333;ws${SECURE:+s}://${HOST_ADDRESS}/_transactor
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - FRONT_URL=http://front:8080
      - STATS_URL=http://stats:4900
      - MODEL_ENABLED=*
      - ACCOUNTS_URL=http://localhost:3000
      - ACCOUNT_PORT=3000
    restart: unless-stopped

  workspace:
    image: hardcoreeng/workspace:${HULY_VERSION}
    environment:
      - SERVER_SECRET=${SECRET}
      - DB_URL=mongodb://mongodb:27017
      - MONGO_URL=mongodb://mongodb:27017
      - TRANSACTOR_URL=ws://transactor:3333;ws${SECURE:+s}://${HOST_ADDRESS}/_transactor
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - MODEL_ENABLED=*
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
    restart: unless-stopped

  front:
    image: hardcoreeng/front:${HULY_VERSION}
    environment:
      - SERVER_PORT=8080
      - SERVER_SECRET=${SECRET}
      - LOVE_ENDPOINT=http${SECURE:+s}://${HOST_ADDRESS}/_love
      - ACCOUNTS_URL=http${SECURE:+s}://${HOST_ADDRESS}/_accounts
      - REKONI_URL=http${SECURE:+s}://${HOST_ADDRESS}/_rekoni
      - CALENDAR_URL=http${SECURE:+s}://${HOST_ADDRESS}/_calendar
      - GMAIL_URL=http${SECURE:+s}://${HOST_ADDRESS}/_gmail
      - TELEGRAM_URL=http${SECURE:+s}://${HOST_ADDRESS}/_telegram
      - STATS_URL=http${SECURE:+s}://${HOST_ADDRESS}/_stats
      - UPLOAD_URL=/files
      - ELASTIC_URL=http://elastic:9200
      - COLLABORATOR_URL=ws${SECURE:+s}://${HOST_ADDRESS}/_collaborator
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - DB_URL=mongodb://mongodb:27017
      - MONGO_URL=mongodb://mongodb:27017
      - TITLE=${TITLE:-Huly Self Host}
      - DEFAULT_LANGUAGE=${DEFAULT_LANGUAGE:-en}
      - LAST_NAME_FIRST=${LAST_NAME_FIRST:-true}
      - DESKTOP_UPDATES_CHANNEL=selfhost
    restart: unless-stopped

  fulltext:
    image: hardcoreeng/fulltext:${HULY_VERSION}
    environment:
      - SERVER_SECRET=${SECRET}
      - DB_URL=mongodb://mongodb:27017
      - FULLTEXT_DB_URL=http://elastic:9200
      - ELASTIC_INDEX_NAME=huly_storage_index
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - REKONI_URL=http://rekoni:4004
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
    restart: unless-stopped

  stats:
    image: hardcoreeng/stats:${HULY_VERSION}
    environment:
      - PORT=4900
      - SERVER_SECRET=${SECRET}
    restart: unless-stopped
volumes:
  db:
  elastic:
  files:
  caddy_data:
  caddy_config:
EOF
fi

echo -e "\n\033[1;34mConfiguration Summary:\033[0m"
echo -e "Reverse Proxy: \033[1;32m$_REVERSE_PROXY\033[0m"
echo -e "Host Address: \033[1;32m$_HOST_ADDRESS\033[0m"
echo -e "HTTP Port: \033[1;32m$_HTTP_PORT\033[0m"
if [[ -n "$SECURE" ]]; then
    echo -e "SSL Enabled: \033[1;32mYes\033[0m"
else
    echo -e "SSL Enabled: \033[1;31mNo\033[0m"
fi

read -p "Do you want to run 'docker compose up -d' now to start Huly? (Y/n): " RUN_DOCKER
case "${RUN_DOCKER:-Y}" in
    [Yy]* )
         echo -e "\033[1;32mRunning 'docker compose up -d' now...\033[0m"
         docker compose up -d
         ;;
    [Nn]* )
        echo "You can run 'docker compose up -d' later to start Huly."
        ;;
esac

echo -e "\033[1;32mSetup is complete!\n Generating ${_REVERSE_PROXY} configuration...\033[0m"
if [ "$_REVERSE_PROXY" = "nginx" ]; then
    ./nginx.sh
    echo ""
    echo "📋 Next steps for nginx:"
    echo "1. Link the nginx config: sudo ln -s \$(pwd)/nginx.conf /etc/nginx/sites-enabled/huly.conf"
    echo "2. Test nginx config: sudo nginx -t"
    echo "3. Reload nginx: sudo nginx -s reload"
    echo ""
    echo "To manage nginx configuration:"
    echo "  ./nginx.sh                    # Update configuration"
    echo "  ./nginx.sh --recreate         # Recreate from template"
else
    ./caddy.sh
    echo ""
    echo "✅ Caddy configuration complete!"
    echo "Caddy will automatically handle SSL certificates for domain names."
    echo ""
    echo "To manage Caddy configuration:"
    echo "  ./caddy.sh                    # Update configuration"
    echo "  ./caddy.sh --recreate         # Recreate from template"
    echo "  docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile"
fi

echo ""
if [ "$_REVERSE_PROXY" = "nginx" ]; then
    echo "📖 For more nginx information, see the README.md"
else
    echo "📖 For more Caddy information, see CADDY_README.md"
fi
echo "🔄 To switch reverse proxy later:"
echo "  ./migrate-to-caddy.sh         # Switch to Caddy"
echo "  ./migrate-to-nginx.sh         # Switch to nginx"
