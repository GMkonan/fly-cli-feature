#!/usr/bin/env bash

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

FLYCTL_VERSION=${VERSION:-"latest"}

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

apt_get_update()
{
    echo "Running apt-get update..."
    apt-get update -y
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
            apt_get_update
        fi
        apt-get -y install --no-install-recommends "$@"
    fi
}

export DEBIAN_FRONTEND=noninteractive

# Figure out correct version of a three part version number is not passed
find_version_from_git_tags() {
    local variable_name=$1
    local requested_version=${!variable_name}
    if [ "${requested_version}" = "none" ]; then return; fi
    local repository=$2
    local prefix=${3:-"tags/v"}
    local separator=${4:-"."}
    local last_part_optional=${5:-"false"}
    if [ "$(echo "${requested_version}" | grep -o "." | wc -l)" != "2" ]; then
        local escaped_separator=${separator//./\\.}
        local last_part
        if [ "${last_part_optional}" = "true" ]; then
            last_part="(${escaped_separator}[0-9]+)?"
        else
            last_part="${escaped_separator}[0-9]+"
        fi
        local regex="${prefix}\\K[0-9]+${escaped_separator}[0-9]+${last_part}$"
        local version_list="$(git ls-remote --tags ${repository} | grep -oP "${regex}" | tr -d ' ' | tr "${separator}" "." | sort -rV)"
        if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ] || [ "${requested_version}" = "lts" ]; then
            LATEST_VERSION="$(curl -s https://api.github.com/repos/superfly/flyctl/releases/latest | jq -r '.tag_name')"
            declare -g ${variable_name}="${LATEST_VERSION#"v"}"
            echo "${LATEST_VERSION}"
        else
            set +e
            declare -g ${variable_name}="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
            set -e
        fi
    fi
    if [ -z "${!variable_name}" ] || ! echo "${version_list}" | grep "^${!variable_name//./\\.}$" > /dev/null 2>&1; then
        echo -e "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
        exit 1
    fi
    echo "${variable_name}=${!variable_name}"
}

# Install dependencies
check_packages curl git tar ca-certificates jq

architecture="$(uname -m)"
case $architecture in
    x86_64) architecture="x86_64";;
    aarch64 | armv8* | arm64) architecture="arm64";;
    *) echo "(!) Architecture $architecture unsupported"; exit 1 ;;
esac

# Use a temporary locaiton for flyctl archive
export TMP_DIR="/tmp/tmp-flyctl"
mkdir -p ${TMP_DIR}
chmod 700 ${TMP_DIR}

# Install flyctl
echo "(*) Installing flyctl..."
find_version_from_git_tags FLYCTL_VERSION https://github.com/superfly/flyctl

FLYCTL_VERSION="${FLYCTL_VERSION#"v"}"
curl -sSL -o ${TMP_DIR}/flyctl.tar.gz "https://github.com/superfly/flyctl/releases/download/v${FLYCTL_VERSION}/flyctl_${FLYCTL_VERSION}_Linux_${architecture}.tar.gz"
tar -xzf "${TMP_DIR}/flyctl.tar.gz" -C "${TMP_DIR}" flyctl
mv ${TMP_DIR}/flyctl /usr/local/bin/flyctl
chmod 0755 /usr/local/bin/flyctl

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"