#!/bin/bash
# 
# Copyright (C) 2018 Nik (https://github.com/Nik--)
# 
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
# 
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.
# 
# Author: Nik (https://github.com/Nik--)
# 
# Script Name:	onlinenet-certbot-hook.sh
# Dependencies: jq (https://github.com/stedolan/jq)
# Description: A script used as an auth hook for certbot DNS challenge.
#              It works only for domains provided by https://online.net
#              It's job is to automatically create a new domain TXT data
#              containing a specific token which is provided by certbot
#              upon authenticating for SSL certificates for a given domain.
#              It also supports wildcard certificates that are active on
#              multiple sub-domains, for example: *.example.org
# ==============================================================================
DEBUG=false
DELETE_ACME_ZONE_VERSION=true

if [ -z $(command -v jq) ]
then
	echo "jq library is missing. Please install it. More info on https://github.com/stedolan/jq"
	exit 1
fi

if [ -z "$ONLINE_NET_API_TOKEN" ] # Provided by user.
then
	echo 'Empty $ONLINE_NET_API_TOKEN provided. Please provide it prior to executing the script:'
	echo 'ONLINE_NET_API_TOKEN="yourOnlineNetAPITokenHere" ./onlinenet-certbot-hook.sh'
	exit 1
fi

if [ -z "$CERTBOT_DOMAIN" ] # Provided by certbot script.
then
	echo 'Empty $CERTBOT_DOMAIN provided. It is provided only if you are running certbot script with --manual-auth-hook argument'
	echo "Example on how the script should be ran when creating a certificate:"
	echo 'certbot certonly --agree-tos --manual --preferred-challenge=dns --manual-auth-hook=./onlinenet-certbot-hook.sh --email "email@example.org" --manual-public-ip-logging-ok -d "example.org" --server "https://acme-staging.api.letsencrypt.org/directory"'
	echo "If you wish to run this script without creating any certificates, feel free to do so by providing dummy variable values. It is a good way to test if this script works properly for you."
	exit 1
fi

if [ -z "$CERTBOT_VALIDATION" ] # Provided by certbot script.
then
	echo 'Empty $CERTBOT_VALIDATION provided'
	exit 1
fi

# $1 = Debug string.
function echo_debug()
{
	if $DEBUG;
	then
		echo "$1"
	fi
}

# $1 = URL
function curl_get()
{
	result=$(curl -s -X GET \
	-H "Authorization: Bearer $ONLINE_NET_API_TOKEN" \
	-H "X-Pretty-JSON: 1" \
	https://api.online.net$1)

	checkForError "$result"
	echo "$result"
}

# $1 = URL, $2 = Data
function curl_post()
{
	result=$(curl -s -X POST \
	-H "Authorization: Bearer $ONLINE_NET_API_TOKEN" \
	-H "X-Pretty-JSON: 1" \
	--data $2 \
	https://api.online.net$1)

	checkForError "$result"
	echo "$result"
}

# $1 = URL
function curl_delete()
{
	result=$(curl -s -X DELETE \
	-H "Authorization: Bearer $ONLINE_NET_API_TOKEN" \
	-H "X-Pretty-JSON: 1" \
	https://api.online.net$1)

	checkForError "$result"
	echo "$result"
}

# $1 = URL
function curl_patch()
{
	result=$(curl -s -X PATCH \
	-H "Authorization: Bearer $ONLINE_NET_API_TOKEN" \
	-H "X-Pretty-JSON: 1" \
	https://api.online.net$1)

	checkForError "$result"
	echo "$result"
}

function check_exists()
{
	if [ -z "$1" ]
	then
		echo "Missing parameter. Please run this script in debug mode to find which parameter is missing."
		exit 1
	fi
}

function checkForError()
{
	if [ -n "$1" ]
	then
		jqType=$(echo "$1" | jq type)
		if [ $jqType = '"object"' ]
		then
			error=$(echo "$1" | jq '.error?')
			code=$(echo "$1" | jq '.code?')
			if [ -n "$error" ] && [[ "$error" != "null" ]] && [ -n "$code" ] && [[ "$code" != "null" ]]
			then
				if [ "$code" == "9" ]; # Permission Denied
				then
					echo "Permission Denied! This error code usually appears when we try to edit an active DNS zone version, but we can only edit inactive ones."
				fi

				echo "There was an ERROR while getting parameters from API: $error code $code"
				exit 1
			fi
		fi
	fi
}

DOMAIN=$(echo "$CERTBOT_DOMAIN" | rev | cut -d'.' -f -2 | rev)
SUB_DOMAIN=$(echo "$CERTBOT_DOMAIN" | rev | cut -d'.' -f 3- | rev)
HOST='_acme-challenge'

if [ ! -z "$SUB_DOMAIN" ]
then
	HOST="${HOST}.${SUB_DOMAIN}"
fi

echo "Starting certificate validation on domain: $DOMAIN and sub-domain: $SUB_DOMAIN"

# Get the data of all current domains.
domain_data=$(curl_get "/api/v1/domain/")
echo_debug "Domain Data: $domain_data"

# Get the ID of the domain we are interested in editing.
domain_id=$(echo "$domain_data" | jq -c '.[] | select( .name | contains("'${DOMAIN}'"))' | jq -r ".id")
echo_debug "Domain ID: $domain_id"
check_exists "$domain_id"

ref_domain_versions=$(echo "$domain_data" | jq -c '.[] | select( .name | contains("'${DOMAIN}'"))' | jq -r '.versions' | jq -r '.["$ref"]')
echo_debug "Ref Domain Versions: $ref_domain_versions"
check_exists "$ref_domain_versions"

# Get the DNS zone versions of this domain.
domain_versions=$(curl_get "$ref_domain_versions")
echo_debug "Domain Versions: $domain_versions"

# Find the active DNS zone version of all the versions.
domain_active_version=$(echo "$domain_versions" | jq -c '.[] | select( .active == true)')
echo_debug "Domain Active Version: $domain_active_version"
check_exists "$domain_active_version"

# Get the UUID and Name of the active DNS zone version so we can progress further.
version_uuid=$(echo "$domain_active_version" | jq -r ".uuid_ref")
version_name=$(echo "$domain_active_version" | jq -r ".name")
ref_zone_data=$(echo "$domain_active_version" | jq -r ".zone" | jq -r '.["$ref"]')
echo_debug "Active Version UUID: $version_uuid"
check_exists "$version_uuid"
echo_debug "Active Version Name: $version_name"
check_exists "$version_name"
echo_debug "Ref Zone Data: $ref_zone_data"
check_exists "$ref_zone_data"

# Get the data of all domains (like domain names, types, ttl, etc)
zone_data=$(curl_get "$ref_zone_data")
echo_debug "Zone Data: $zone_data"

# Now it is time to create a new DNS zone version where we are going to add the acme-challenge domain name.
# This is done because we cannot edit the currently active DNS zone.
echo "Creating new DNS zone version..."
version_create_result=$(curl_post "$ref_domain_versions" "name=deleteme_acme_challenge_of_$version_name")
echo_debug "Version create result: $version_create_result"

# Get the UUID and Name of the newly created DNS zone version which will contain the acme-challenge.
acme_version_uuid=$(echo "$version_create_result" | jq -r ".uuid_ref")
acme_version_name=$(echo "$version_create_result" | jq -r ".name")
ref_acme_zone_data=$(echo "$version_create_result" | jq -r ".zone" | jq -r '.["$ref"]')
echo_debug "Acme Version UUID: $acme_version_uuid"
check_exists "$acme_version_uuid"
echo_debug "Acme Version Name: $acme_version_name"
check_exists "$acme_version_name"
echo_debug "Ref Acme Zone Data: $ref_acme_zone_data"
check_exists "$ref_acme_zone_data"
echo "Created a new version with name: $acme_version_name and uuid: $acme_version_uuid"

# Now create the acme-challenge sub-domain which will contain a TXT data with the token provided by the certbot.
# Letsencrypt is going to check the data of this sub-domain and verify that its token is there.
echo "Creating the acme-challenge sub-domain with name: $HOST"
subdomain_create_result=$(curl_post "$ref_acme_zone_data" "name=$HOST&type=TXT&priority=1&ttl=600&data=$CERTBOT_VALIDATION")
echo_debug "Sub-domain create result: $subdomain_create_result"

# Get the name and data of the newly created sub-domain and confirm they match.
subdomain_create_name=$(echo "$subdomain_create_result" | jq -r '.name')
subdomain_create_data=$(echo "$subdomain_create_result" | jq -r '.data')
echo_debug "Sub-domain create name: $subdomain_create_name"
check_exists "$subdomain_create_name"
check_exists "$subdomain_create_data"
echo "Created the acme-challenge sub-domain: $subdomain_create_name with data: $subdomain_create_data"
if [[ "$subdomain_create_name" != "$HOST" ]] || [[ "$subdomain_create_data" != "$CERTBOT_VALIDATION" ]]
then
	echo "It appears that the newly created acme-challenge sub-domain name or data is not matching the specified oned."
	echo "Expected name: [$HOST] but found: [$subdomain_create_name]"
	echo "Expected data: [$CERTBOT_VALIDATION] but found: [$subdomain_create_data]"
	exit 1
fi

# Now the tricky part. We need to copy all the dns zone records of the active one onto the acme-challenge one.
echo "Copying current active DNS zone entries into the newly created acme-challenge DNS zone..."
zone_data_length=$(echo "${zone_data}" | jq '. | length')
for (( i=0; i<$zone_data_length; i++ ))
do
	name=$(echo "${zone_data}" | jq --argjson i $i -r '.[$i].name');
	type=$(echo "${zone_data}" | jq --argjson i $i -r '.[$i].type');
	priority=$(echo "${zone_data}" | jq --argjson i $i -r '.[$i].priority');
	ttl=$(echo "${zone_data}" | jq --argjson i $i -r '.[$i].ttl');
	data=$(echo "${zone_data}" | jq --argjson i $i -r '.[$i].data');

	if [ "$priority" = "null" ]
	then
		priority=""
	fi

	echo_debug "Copying domain entry: name [$name] type [$type] priority [$priority] ttl [$ttl] data [$data]"
	subdomain_copy_result=$(curl_post "$ref_acme_zone_data" "name=$name&type=$type&priority=$priority&ttl=$ttl&data=$data")
	echo_debug "Sub-domain copy result: $subdomain_copy_result"
done

# After we've copied everything into the acme-challenge dns zone, its time to activate it (effectively disabling the previous one)
echo "Activating the acme-challenge DNS zone..."
echo "WARNING: If anything from this point onwards fails, you have to manually activate your old DNS zone."
acme_version_enable_result=$(curl_patch "$ref_domain_versions/$acme_version_uuid/enable")
echo_debug "Acme-challenge DNS zone version enable result: $acme_version_enable_result"

# A successful enable should return nothing.
if [ -z "$acme_version_enable_result" ]
then
	echo "Acme-challenge DNS zone has been enabled."
else
	echo "There was an unexpected result when enabling the acme-challenge DNS zone:"
	echo "$acme_version_enable_result"
	# Don't exit so we can attempt to re-enable the old active zone.
fi

# Wait some time so letsencrypt can verify the token.
# If you get Failed authorization procedure. example.org (dns-01): urn:acme:error:dns :: DNS problem: NXDOMAIN looking up TXT for _acme-challenge.example.org
# try to increase this time even more.
echo 'Waiting 1 minute... (so letsencrypt can verify the acme-challenge)'
sleep 60

# After hopefully letsencrypt has verified its token, its time for us to re-activate our previous active DNS zone.
echo "Re-activating your old active DNS zone: $version_name"
echo "WARNING: If re-activating fails, you have to manually activate your DNS zone!"
version_enable_result=$(curl_patch "$ref_domain_versions/$version_uuid/enable")
echo_debug "Re-activate old active DNS zone version result: $version_enable_result"

# A successful enable should return nothing.
if [ -z "$version_enable_result" ]
then
	echo "Re-activated your old DNS zone. It is highly suggested to manually check the DNS zone records to confirm everything is back to how it was."
else
	echo "There was an unexpected result when re-enabling your old active DNS zone:"
	echo "$version_enable_result"
	echo ""
	echo "Head to https://console.online.net and login to manually re-activate your DNS zone!!!"
	exit 1
fi

# Up to this point, we should've verified the token, therefore the acme-challenge dns zone version is no longer needed. Delete it.
if $DELETE_ACME_ZONE_VERSION;
then
	echo "Acme-challenge DNS zone version is set to be automatically deleted. Deleting..."
	acme_version_delete_result=$(curl_delete "$ref_domain_versions/$acme_version_uuid")

	echo_debug "Acme DNS zone version delete result: $acme_version_delete_result"

	if [ -z "$acme_version_delete_result" ]
	then
		echo "Deleted the acme-challenge DNS zone version: $acme_version_name"
	else
		echo "Acme-challenge DNS zone deletion has returned unexpected result: $acme_version_delete_result"
	fi
else
	echo "Acme-challenge DNS zone version is not set to be automatically deleted. You have to manually delete DNS zone version: $acme_version_name"
fi

echo "The script has finished executing. It is suggested to head to https://console.online.net and login to confirm that everything is back to how it was."
