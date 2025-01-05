#!/bin/bash

echo "Enter password for MySQL root user:"
read -s root_password
echo "Enter password for Marzban database user:"
read -s marzban_password

echo "Adding current user to docker group..."
usermod -aG docker $(whoami)

echo "Creating volume for MySQL database..."
docker volume create mariadb_data

echo "Starting MySQL container..."
docker run -d --rm \
  --name mariadb_data \
  -v mariadb_data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=$root_password \
  -e MYSQL_ROOT_HOST=127.0.0.1 \
  -e MYSQL_DATABASE=marzban \
  -e MYSQL_PASSWORD=$marzban_password \
  -e MYSQL_USER=marzban \
  mariadb:lts \
  --bind-address=127.0.0.1 \
  --character_set_server=utf8mb4 \
  --collation_server=utf8mb4_unicode_ci \
  --innodb-log-file-size=67108864 \
  --host-cache-size=0 \
  --innodb-open-files=1024 \
  --innodb-buffer-pool-size=268435456 \
  --binlog_expire_logs_seconds=5184000

echo "Stopping container..."
docker stop mariadb_data

echo "Replacing contents in /opt/marzban/docker-compose.yml..."
cat > /opt/marzban/docker-compose.yml <<EOL
services:
  marzban:
    image: gozargah/marzban:latest
    restart: always
    env_file: .env
    network_mode: host
    volumes:
      - /var/lib/marzban:/var/lib/marzban
    depends_on:
      mariadb:
        condition: service_healthy

  mariadb:
    image: mariadb:lts
    env_file: .env
    network_mode: host
    restart: always
    command:
      - --bind-address=127.0.0.1
      - --character_set_server=utf8mb4
      - --collation_server=utf8mb4_unicode_ci
      - --host-cache-size=0
      - --innodb-open-files=1024
      - --innodb-buffer-pool-size=268435456
      - --binlog_expire_logs_seconds=5184000 # 60 days
    volumes:
      - mariadb_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 10s
      start_interval: 3s
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  mariadb_data:
    name: mariadb_data
    external: true
EOL

echo "Replacing contents in /opt/marzban/.env..."
sed -i "s|SQLALCHEMY_DATABASE_URL = \"sqlite:////var/lib/marzban/db.sqlite3\"|SQLALCHEMY_DATABASE_URL = \"mysql+pymysql://marzban:$marzban_password@127.0.0.1:3306/marzban\"|" /opt/marzban/.env

echo "Marzban restarting..."
marzban restart
