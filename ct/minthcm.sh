#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 minthcm
# Author: Piotr Smilgin (waveoffire98)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/minthcm/minthcm

APP="MintHCM"
var_tags="${var_tags:-hcm}"
var_disk="${var_disk:-20}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info "$APP"
  check_container_storage
  check_container_resources

  INSTALL_DIR="/var/www/MintHCM"

  if [[ ! -d "${INSTALL_DIR}" ]] || [[ ! -d "${INSTALL_DIR}/.git" ]]; then
    msg_error "No ${APP} installation found in ${INSTALL_DIR}!"
    exit
  fi

  msg_info "Stopping Apache2 service"
  systemctl stop apache2 >/dev/null 2>&1 || true
  msg_ok "Stopped Apache2 (if running)"

  cd "${INSTALL_DIR}" || {
    msg_error "Cannot enter ${INSTALL_DIR}"
    exit 1
  }

  CURRENT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  msg_info "Current ${APP} commit: ${CURRENT_COMMIT}"

  msg_info "Fetching latest code from origin/master"
  sudo -u www-data git fetch origin >/dev/null 2>&1 || {
    msg_error "git fetch origin failed"
    exit 1
  }

  NEW_REMOTE_COMMIT="$(git rev-parse --short origin/master 2>/dev/null || echo 'unknown')"

  if [[ "${CURRENT_COMMIT}" == "${NEW_REMOTE_COMMIT}" ]]; then
    msg_ok "No update required. ${APP} is already at ${CURRENT_COMMIT}"
    systemctl start apache2 >/dev/null 2>&1 || true
    exit
  fi

  msg_info "Updating ${APP} to origin/master (${NEW_REMOTE_COMMIT})"
  sudo -u www-data git reset --hard origin/master >/dev/null 2>&1 || {
    msg_error "git reset --hard origin/master failed"
    exit 1
  }

  echo "${NEW_REMOTE_COMMIT}" >/opt/${APP}_version.txt

  msg_info "Adjusting permissions for MintHCM directory"
  chown -R www-data:www-data "${INSTALL_DIR}"
  find "${INSTALL_DIR}" -type d -exec chmod 755 {} \;
  find "${INSTALL_DIR}" -type f -exec chmod 644 {} \;
  msg_ok "Permissions updated"

  msg_info "Starting Apache2 service"
  systemctl start apache2 >/dev/null 2>&1 || {
    msg_error "Failed to start Apache2"
    exit 1
  }
  msg_ok "Started Apache2"
  msg_ok "Updated ${APP} successfully to commit ${NEW_REMOTE_COMMIT}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL (after DB & installer are completed):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
