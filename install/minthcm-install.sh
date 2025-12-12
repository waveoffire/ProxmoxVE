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
$STD apt-get install -y software-properties-common git curl cron sudo
msg_ok "Base packages installed"

# Install and configure Apache2 web server with required modules (if not already installed)
msg_info "Checking for Apache2 and configuring it"
if ! dpkg -s apache2 >/dev/null 2>&1; then
  $STD apt-get install -y apache2
  msg_ok "Apache2 installed"
else
  msg_ok "Apache2 already installed"
fi

$STD a2enmod rewrite
$STD a2enmod headers
msg_ok "Apache2 with rewrite and headers modules configured"

# Use tools.func helper to install PHP and required extensions
# setup_php will handle repository configuration and PHP installation
msg_info "Setting up PHP ${PHP_VERSION} via tools.func"
PHP_APACHE="YES"
PHP_FPM="NO"
# Default modules from setup_php already include many common extensions.
# Here we explicitly add extra modules needed by MintHCM (imap, mysql).
PHP_MODULE="imap,mysql"
export PHP_VERSION PHP_APACHE PHP_FPM PHP_MODULE
setup_php
msg_ok "PHP ${PHP_VERSION} and required extensions installed via setup_php"

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

# Download generate_config.php helper script used by MintHCM
msg_info "Downloading generate_config.php script"
mkdir -p /var/www/script
curl -fsSL \
  "https://raw.githubusercontent.com/minthcm/minthcm/master/docker/script/generate_config.php" \
  -o "/var/www/script/generate_config.php" \
  || msg_error "Failed to download generate_config.php"
chown -R www-data:www-data /var/www/script
msg_ok "generate_config.php script downloaded"

# Set ownership and permissions for MintHCM directory
msg_info "Setting ownership and permissions for MintHCM directory"
chown -R www-data:www-data "${MINT_DIR}"
find "${MINT_DIR}" -type d -exec chmod 755 {} \;
find "${MINT_DIR}" -type f -exec chmod 644 {} \;
msg_ok "Ownership and permissions for MintHCM directory set"

# Restart Apache2 to apply all new configuration
msg_info "Restarting Apache2 with new configuration"
$STD systemctl restart apache2
msg_ok "Apache2 restarted"

# Optionally record simple version info using current Git commit (HEAD)
if command -v git >/dev/null 2>&1 && [[ -d "${MINT_DIR}/.git" ]]; then
  MINT_VERSION="$(git -C "${MINT_DIR}" rev-parse --short HEAD || echo 'unknown')"
else
  MINT_VERSION="unknown"
fi

# APPLICATION variable is provided by the community-scripts wrapper
if [[ -n "${APPLICATION}" ]]; then
  echo "${MINT_VERSION}" >"/opt/${APPLICATION}_version.txt"
fi

msg_ok "${APP_NAME} has been installed. Make sure to configure the database and other parameters according to the MintHCM documentation."

motd_ssh
customize
cleanup_lxc
