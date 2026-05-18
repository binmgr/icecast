#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202605180000-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  GPL-2.0 or LICENSE.md
# @@ReadME           :  entrypoint.sh --help | README.md
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, May 15, 2026 00:00 EDT
# @@File             :  entrypoint.sh
# @@Description      :  Generate icecast.xml from env vars and exec icecast
# @@Changelog        :  New file
# @@TODO             :
# @@Other            :  Called by: tini -> entrypoint.sh -> icecast
# @@Resource         :  https://icecast.org/docs/icecast-trunk/config_file/
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202605180000-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -

set -euo pipefail

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Defaults — env vars override all of these at runtime
# - - - - - - - - - - - - - - - - - - - - - - - - -
ICECAST_HOSTNAME="${ICECAST_HOSTNAME:-localhost}"
ICECAST_LOCATION="${ICECAST_LOCATION:-Earth}"
ICECAST_MAX_CLIENTS="${ICECAST_MAX_CLIENTS:-100}"
ICECAST_MAX_SOURCES="${ICECAST_MAX_SOURCES:-2}"

# Passwords — STREAM_PASSWORD is the legacy fallback used by ices/libretime
ICECAST_SOURCE_PASSWORD="${ICECAST_SOURCE_PASSWORD:-${STREAM_PASSWORD:-changeme}}"
ICECAST_RELAY_PASSWORD="${ICECAST_RELAY_PASSWORD:-${STREAM_PASSWORD:-changeme}}"
ICECAST_ADMIN_USERNAME="${ICECAST_ADMIN_USERNAME:-admin}"
ICECAST_ADMIN_PASSWORD="${ICECAST_ADMIN_PASSWORD:-changeme}"
ICECAST_ADMIN_EMAIL="${ICECAST_ADMIN_EMAIL:-${ICECAST_ADMIN_USERNAME}@${ICECAST_HOSTNAME}}"

# Listener
STREAM_PORT="${STREAM_PORT:-8000}"

# - - - - - - - - - - - - - - - - - - - - - - - - -
# XML-escape a value: & < > "
# - - - - - - - - - - - - - - - - - - - - - - - - -
__xml_escape() {
    printf '%s' "$1" \
        | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Runtime directories
# - - - - - - - - - - - - - - - - - - - - - - - - -
mkdir -p \
    /etc/icecast \
    /run/icecast \
    /var/log/icecast \
    /usr/share/icecast/web \
    /usr/share/icecast/admin

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Generate /etc/icecast/icecast.xml
# - - - - - - - - - - - - - - - - - - - - - - - - -
cat > /etc/icecast/icecast.xml <<XMLEOF
<icecast>
    <location>$(__xml_escape "${ICECAST_LOCATION}")</location>
    <admin>$(__xml_escape "${ICECAST_ADMIN_EMAIL}")</admin>

    <limits>
        <clients>$(__xml_escape "${ICECAST_MAX_CLIENTS}")</clients>
        <sources>$(__xml_escape "${ICECAST_MAX_SOURCES}")</sources>
        <queue-size>524288</queue-size>
        <client-timeout>30</client-timeout>
        <header-timeout>15</header-timeout>
        <source-timeout>10</source-timeout>
        <burst-on-connect>1</burst-on-connect>
        <burst-size>65535</burst-size>
    </limits>

    <authentication>
        <source-password>$(__xml_escape "${ICECAST_SOURCE_PASSWORD}")</source-password>
        <relay-password>$(__xml_escape "${ICECAST_RELAY_PASSWORD}")</relay-password>
        <admin-user>$(__xml_escape "${ICECAST_ADMIN_USERNAME}")</admin-user>
        <admin-password>$(__xml_escape "${ICECAST_ADMIN_PASSWORD}")</admin-password>
    </authentication>

    <hostname>$(__xml_escape "${ICECAST_HOSTNAME}")</hostname>

    <listen-socket>
        <port>$(__xml_escape "${STREAM_PORT}")</port>
    </listen-socket>

    <fileserve>1</fileserve>

    <paths>
        <basedir>/usr/share/icecast</basedir>
        <logdir>/var/log/icecast</logdir>
        <webroot>/usr/share/icecast/web</webroot>
        <adminroot>/usr/share/icecast/admin</adminroot>
        <pidfile>/run/icecast/icecast.pid</pidfile>
    </paths>

    <logging>
        <accesslog>-</accesslog>
        <errorlog>-</errorlog>
        <loglevel>3</loglevel>
        <logsize>10000</logsize>
    </logging>

    <security>
        <chroot>0</chroot>
    </security>
</icecast>
XMLEOF

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Exec icecast — replaces this shell so tini receives signals directly
# - - - - - - - - - - - - - - - - - - - - - - - - -
exec /usr/local/bin/icecast -c /etc/icecast/icecast.xml

# ex: ts=2 sw=2 et filetype=sh
