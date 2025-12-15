#!/usr/bin/env bash

# Copyright (c) 2021-2025 minthcm
# Author: Piotr Smilgin (waveoffire98)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/minthcm/minthcm
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP_NAME="MintHCM"
MINT_REPO="https://github.com/minthcm/minthcm.git"
MINT_DIR="/var/www/MintHCM"
PHP_VERSION="8.2"

# Install base packages required for MintHCM and system management
msg_info "Installing base packages"
$STD apt-get install -y git curl cron
msg_ok "Base packages installed"


msg_info "Setting up PHP ${PHP_VERSION}"
PHP_APACHE="YES" PHP_VERSION="${PHP_VERSION}" PHP_MODULE="mysql,cli,redis" PHP_FPM="YES" setup_php

msg_ok "PHP ${PHP_VERSION} and required extensions installed"
setup_composer
msg_ok "Setup composer"
$STD a2enmod rewrite
$STD a2enmod headers
msg_ok "Apache2 with rewrite and headers modules configured"

# Download MintHCM-specific PHP configuration file
msg_info "Downloading PHP configuration for MintHCM"
PHP_MODS_DIR="/etc/php/${PHP_VERSION}/mods-available"
PHP_MINTHCM_INI="${PHP_MODS_DIR}/php-minthcm.ini"
mkdir -p "${PHP_MODS_DIR}"

curl -fsSL \
  "https://raw.githubusercontent.com/minthcm/minthcm/master/docker/config/php-minthcm.ini" \
  -o "${PHP_MINTHCM_INI}" || msg_error "Failed to download php-minthcm.ini"

# Create symlinks for CLI and Apache2 PHP configuration
mkdir -p "/etc/php/${PHP_VERSION}/cli/conf.d" "/etc/php/${PHP_VERSION}/apache2/conf.d"

if [[ ! -e "/etc/php/${PHP_VERSION}/cli/conf.d/20-minthcm.ini" ]]; then
  ln -s "${PHP_MINTHCM_INI}" "/etc/php/${PHP_VERSION}/cli/conf.d/20-minthcm.ini"
fi

if [[ ! -e "/etc/php/${PHP_VERSION}/apache2/conf.d/20-minthcm.ini" ]]; then
  ln -s "${PHP_MINTHCM_INI}" "/etc/php/${PHP_VERSION}/apache2/conf.d/20-minthcm.ini"
fi

msg_ok "PHP configuration for MintHCM applied"

# Download Apache VirtualHost configuration for MintHCM
msg_info "Downloading Apache VirtualHost configuration for MintHCM"
curl -fsSL \
  "https://raw.githubusercontent.com/minthcm/minthcm/master/docker/config/000-default.conf" \
  -o "/etc/apache2/sites-available/000-default.conf" \
  || msg_error "Failed to download 000-default.conf"
msg_ok "Apache VirtualHost configuration updated for MintHCM"

# Clone MintHCM repository into the target directory
msg_info "Cloning MintHCM repository"
if [[ -d "${MINT_DIR}" ]]; then
  msg_warn "Directory ${MINT_DIR} already exists, skipping clone"
else
  mkdir -p "$(dirname "${MINT_DIR}")"
  $STD git clone --depth=1 "${MINT_REPO}" "${MINT_DIR}" || msg_error "Failed to clone MintHCM repository"
fi
msg_ok "MintHCM repository available at ${MINT_DIR}"

# Set ownership and permissions for MintHCM directory
msg_info "Setting ownership and permissions for MintHCM directory"
git config --global --add safe.directory /var/www/MintHCM
chown -R www-data:www-data "${MINT_DIR}"
find "${MINT_DIR}" -type d -exec chmod 755 {} \;
find "${MINT_DIR}" -type f -exec chmod 644 {} \;
msg_ok "Ownership and permissions for MintHCM directory set"

# Restart Apache2 to apply all new configuration
msg_info "Restarting Apache2 with new configuration"
$STD systemctl restart apache2
msg_ok "Apache2 restarted"

read -r -p "${TAB3}Do you want MariaDB and Elasticsearch to be installed automatically in this LXC container? <Y/n> " prompt
if [[ -z "$prompt" || ${prompt,,} =~ ^(y|yes)$ ]]; then
msg_info "Setting up Elasticsearch"
setup_deb822_repo \
  "elasticsearch" \
  "https://artifacts.elastic.co/GPG-KEY-elasticsearch" \
  "https://artifacts.elastic.co/packages/7.x/apt" \
  "stable" \
  "main"
$STD apt install -y elasticsearch
echo "-Xms2g" >>/etc/elasticsearch/jvm.options
echo "-Xmx2g" >>/etc/elasticsearch/jvm.options
$STD /usr/share/elasticsearch/bin/elasticsearch-plugin install ingest-attachment -b
systemctl enable -q elasticsearch
systemctl restart -q elasticsearch
msg_ok "Setup Elasticsearch"


setup_mariadb
MARIADB_DB_NAME="minthcm" MARIADB_DB_USER="minthcm" MARIADB_DB_PASS="minthcm" MARIADB_DB_SQL_MODE="" setup_mariadb_db

mkdir /var/www/script
curl -fsSL \
  "https://raw.githubusercontent.com/minthcm/minthcm/master/docker/script/generate_config.php" \
  -o "/var/www/script/generate_config.php" \
  || msg_error "Failed to download generate_config.php"
chown -R www-data:www-data /var/www/script
msg_ok "generate_config.php script downloaded"
export DB_HOST=localhost
export DB_NAME=minthcm
export DB_PORT=3306
export DB_USER=minthcm
export DB_PASS=minthcm
export MINT_URL=localhost
export MINT_USER=admin
export MINT_PASS=minthcm
export ELASTICSEARCH_HOST=localhost

  php /var/www/script/generate_config.php

if [[ ! -f /var/www/MintHCM/configMint4 ]]; then
    msg_error "Error: Failed to generate configMint4 - please check the configuration\n"
    exit 1
  fi
msg_info "Starting MintHCM installation...\n"
  su -s /bin/bash -c 'php /var/www/MintHCM/MintCLI install < /var/www/MintHCM/configMint4' www-data

  if [[ $? -ne 0 ]]; then
    msg_error "Error: MintHCM installation failed - please check logs\n"
  else
    msg_ok "MintHCM installation completed!\n"
    #add cron and start service
    printf "*    *    *    *    *     cd /var/www/MintHCM/legacy; php -f cron.php > /dev/null 2>&1" > /var/spool/cron/crontabs/www-data
    service cron start
    rm /var/www/MintHCM/configMint4
  fi

fi




msg_ok "${APP_NAME} has been installed. Make sure to configure the database and other parameters according to the MintHCM documentation."

motd_ssh
customize
cleanup_lxc
