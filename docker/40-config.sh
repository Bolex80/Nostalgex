#!/bin/sh
# Writes the tuner's runtime config from the environment. nginx serves it at
# /config.json (see docker/nginx.conf). Runs from the nginx image's entrypoint,
# as the unprivileged nginx user, before nginx starts.
#
#   NOSTALGEX_ENRICHMENT=on   (default) TMDB/OMDb metadata from the shared cache and
#                             the nostalgex.app relay. Only TMDB and IMDb ids are sent.
#   NOSTALGEX_ENRICHMENT=off  no Supabase or relay requests at all.
set -eu

raw="${NOSTALGEX_ENRICHMENT:-on}"
case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
  on|true|1|yes) enrichment=true ;;
  off|false|0|no) enrichment=false ;;
  *)
    # A typo should not quietly send requests someone tried to turn off.
    echo "$0: NOSTALGEX_ENRICHMENT must be on or off, got '$raw'. Treating it as off." >&2
    enrichment=false
    ;;
esac

version="${NOSTALGEX_TUNER_VERSION:-dev}"
case "$version" in
  *[!A-Za-z0-9._-]*) version=dev ;;
esac

mkdir -p /tmp/nostalgex
printf '{"tunerVersion":"%s","musicLookups":false,"enrichment":%s}\n' "$version" "$enrichment" \
  > /tmp/nostalgex/config.json

if [ "$enrichment" = true ]; then
  echo "$0: Nostalgex tuner $version, metadata enrichment on (NOSTALGEX_ENRICHMENT=off turns it off)"
else
  echo "$0: Nostalgex tuner $version, metadata enrichment off"
fi
