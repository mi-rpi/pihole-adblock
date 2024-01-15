#!/usr/bin/env bash
#
# This file will install:
# pihole-updatelists
#
# Usage:
# $ sudo bash adblock.sh
#
# https://github.com/pimanDE/settings2pi/blob/master/Dateien/pihole/listen-ger%C3%A4te-gruppen-hinzuf%C3%BCgen.sh
#
# 2024-01-16

#################### [ SETTING VARS ] ####################

SUNAME=$(pinky | tail -1 | awk '{ print $1 }')
ASSETS_DIR="/home/${SUNAME}/assets"

# Color
# RRed="\033[0;31m"     # Red Regular
# RGreen="\033[0;32m"   # Green Regular
HRed="\033[0;91m"     # Red High Intensity
HGreen="\033[0;92m"   # Green High Intensity
HYellow="\033[0;93m"  # Yellow High Intensity
# HPurple="\033[0;95m"  # Purple High Intensity
HCyan="\033[0;96m"    # Cyan High Intensity
NColor="\033[0m"      # No color

Info="[${HYellow}i${NColor}]"
Cross="[${HRed}✗${NColor}]"
Tick="[${HGreen}✓${NColor}]"


#################### [ Do not touch code below ] ####################

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${Cross} ${HRed}Failed. Please run as root:${NColor}"
    echo "$ sudo bash adblock.sh"
    exit 1
fi

echo -e "${Info} ${HCyan}Installing pihole-updatelists${NColor}"
apt install sqlite3 php-cli php-sqlite3 php-intl php-curl -y
wget -O - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash

echo -e "${Info} ${HCyan}Downloading and extracting pihole-adblock-master.zip${NColor}"
# Download and extract the repository
wget --show-progress --content-disposition "https://codeload.github.com/mi-rpi/pihole-adblock/zip/refs/heads/master"
unzip "pihole-adblock-master.zip"
rm -rf "pihole-adblock-master.zip" "${ASSETS_DIR}"
mv "pihole-adblock-master" "assets"
rm "${ASSETS_DIR}/adblock.sh"

echo -e "${Info} ${HCyan}Configuring /etc/pihole-updatelists.conf${NColor}"
# Set directories and populate URL arrays
ADLISTS_DIR="${ASSETS_DIR}/adlists"
WHITELIST_DIR="${ASSETS_DIR}/whitelist"
REGEX_WHITELIST_DIR="${ASSETS_DIR}/whitelist_regex"
BLACKLIST_DIR="${ASSETS_DIR}/blacklist"
REGEX_BLACKLIST_DIR="${ASSETS_DIR}/blacklist_regex"

# Store URLs directly in arrays
ADLISTS_URL=("$ADLISTS_DIR"/*)
WHITELIST_URL=("$WHITELIST_DIR"/*)
REGEX_WHITELIST_URL=("$REGEX_WHITELIST_DIR"/*)
BLACKLIST_URL=("$BLACKLIST_DIR"/*)
REGEX_BLACKLIST_URL=("$REGEX_BLACKLIST_DIR"/*)

cat << EOF | tee /etc/pihole-updatelists.conf
; Pi-hole's Lists Updater by Jack'lul
; https://github.com/jacklul/pihole-updatelists
; For a full list of available variables please see the readme.

; Remote list URL containing list of adlists to import
; URLs to single adlists are not supported here!
ADLISTS_URL="${ADLISTS_URL[@]}"

; Remote list URL containing exact domains to whitelist
WHITELIST_URL="https://raw.githubusercontent.com/EnergizedProtection/unblock/master/basic/formats/domains.txt https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt ${WHITELIST_URL[@]}"

; Remote list URL containing regex rules for whitelisting
REGEX_WHITELIST_URL="${REGEX_WHITELIST_URL[@]}"

; Remote list URL containing exact domains to blacklist
; This is specifically for handcrafted lists only, do not use regular blocklists here!
BLACKLIST_URL="${BLACKLIST_URL[@]}"

; Remote list URL containing regex rules for blacklisting
REGEX_BLACKLIST_URL="${REGEX_BLACKLIST_URL[@]}"
EOF

echo -e "${Info} ${HCyan}Resetting database /etc/pihole/gravity.db${NColor}"
sqlite3 /etc/pihole/gravity.db <<EOF
BEGIN;

-- Wipe all adlists and domains
DELETE FROM adlist;
DELETE FROM adlist_by_group;
DELETE FROM domainlist;
DELETE FROM domainlist_by_group;
DELETE FROM 'group' WHERE name != 'Default' OR id != 0;

-- Commit the transaction
COMMIT;
EOF

echo -e "${Info} ${HCyan}Inserting parental control domain list to /etc/pihole/gravity.db${NColor}"
# Define variables for the new 'group' record
group_enabled=1
group_name='Kindersicherung'
group_description='Totale Internetsperren'

# Define variables for the new 'domainlist' record
domainlist_type=3  # regex blacklist: 3
domainlist_domain='.*'
domainlist_enabled=1
domainlist_comment='Managed by admin'

# Execute SQL queries in a single transaction
sqlite3 /etc/pihole/gravity.db <<EOF
BEGIN;

-- Insert or update the 'group' record
INSERT INTO 'group' (enabled, name, description)
VALUES ($group_enabled, '$group_name', '$group_description')
ON CONFLICT(name) DO UPDATE
SET name = excluded.name, description = excluded.description;

-- Insert or update the 'domainlist' record
INSERT INTO 'domainlist' (type, domain, enabled, comment)
VALUES ($domainlist_type, '$domainlist_domain', $domainlist_enabled, '$domainlist_comment')
ON CONFLICT(type, domain) DO UPDATE
SET type = excluded.type, domain = excluded.domain, comment = excluded.comment;

-- Delete all records with the same 'domainlist_id' from 'domainlist_by_group'
DELETE FROM 'domainlist_by_group' WHERE domainlist_id = (SELECT id FROM 'domainlist' WHERE domain = '$domainlist_domain' AND type = $domainlist_type);

-- Insert into 'domainlist_by_group'
INSERT INTO 'domainlist_by_group' (domainlist_id, group_id)
VALUES ((SELECT id FROM 'domainlist' WHERE domain = '$domainlist_domain' AND type = $domainlist_type), (SELECT id FROM 'group' WHERE name = '$group_name'))
ON CONFLICT(domainlist_id, group_id) DO UPDATE
SET domainlist_id = excluded.domainlist_id, group_id = excluded.group_id;

COMMIT;
EOF

echo -e "${Info} ${HCyan}Refreshing database${NColor}"
pihole-updatelists

echo -e "${Tick} ${HGreen}Done!${NColor}"
