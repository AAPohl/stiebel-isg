#!/bin/sh

MQTT_HOST="${MQTT_HOST:?MQTT_HOST is not set}"
MQTT_PORT="${MQTT_PORT:?MQTT_PORT is not set}"
MQTT_REQUESTS="${MQTT_REQUESTS:?MQTT_REQUESTS is not set}"
MQTT_USERNAME="${MQTT_USERNAME:?MQTT_USERNAME is not set}"
MQTT_PASSWORD="${MQTT_PASSWORD:?MQTT_PASSWORD is not set}"
ISG_URL="${ISG_URL:?ISG_URL is not set}"
POLL_INTERVAL="${POLL_INTERVAL:?POLL_INTERVAL is not set}"
CURL_TIMEOUT="${CURL_TIMEOUT:?CURL_TIMEOUT is not set}"

sleep_until_next_poll() {
  loop_started="$1"
  now="$(date +%s)"
  elapsed=$((now - loop_started))
  sleep_for=$((POLL_INTERVAL - elapsed))
  if [ "$sleep_for" -gt 0 ]; then
    sleep "$sleep_for"
  fi
}

read_isg_values() {
  keys="$1"

  if ! html="$(curl -fsS --max-time "$CURL_TIMEOUT" "$ISG_URL" 2>/dev/null)"; then
    printf 'ERROR: curl request failed for %s\n' "$ISG_URL" >&2
    return 1
  fi

  if [ -z "$html" ]; then
    printf 'ERROR: empty curl response from %s\n' "$ISG_URL" >&2
    return 1
  fi

  printf '%s\n' "$keys" | tr ';' '\n' | while IFS= read -r key
  do
    [ -z "$key" ] && continue

    value="$(printf '%s\n' "$html" | grep -A1 "$key" | tail -n1 | sed -nE 's/.*>(-?[0-9]+([.,][0-9]+)?)([[:space:]]*[[:alpha:]%°/]+)?<.*/\1/p')"

    if [ -z "$value" ]; then
      printf 'ERROR: no value found for key %s\n' "$key" >&2
      value="0"
    fi

    printf '%s=%s\n' "$key" "$value"
  done
}

printf 'Configured requests:\n'
printf '%s\n' "$MQTT_REQUESTS" | tr ';' '\n' | while IFS= read -r pair
do
  [ -z "$pair" ] && continue
  isg_key="${pair%%=*}"
  mqtt_topic="${pair#*=}"

  if [ -z "$isg_key" ] || [ -z "$mqtt_topic" ] || [ "$isg_key" = "$mqtt_topic" ]; then
    printf 'ERROR: Skipping invalid request: %s\n' "$pair" >&2
    continue
  fi

  printf '  %s -> %s\n' "$isg_key" "$mqtt_topic"
done

while true
do
  loop_started="$(date +%s)"

  key_list="$(
    printf '%s\n' "$MQTT_REQUESTS" | tr ';' '\n' | awk -F= 'NF==2 && $1!="" && $2!="" && $1!=$2 { print $1 }' | paste -sd';' -
  )"

  if [ -z "$key_list" ]; then
    printf 'ERROR: No valid requests in MQTT_REQUESTS\n' >&2
    sleep_until_next_poll "$loop_started"
    continue
  fi

  values_list="$(read_isg_values "$key_list")" || {
    sleep_until_next_poll "$loop_started"
    continue
  }

  printf '%s\n' "$MQTT_REQUESTS" | tr ';' '\n' | while IFS= read -r pair
  do
    [ -z "$pair" ] && continue
    isg_key="${pair%%=*}"
    mqtt_topic="${pair#*=}"

    if [ -z "$isg_key" ] || [ -z "$mqtt_topic" ] || [ "$isg_key" = "$mqtt_topic" ]; then
      printf 'ERROR: Skipping invalid request: %s\n' "$pair" >&2
      continue
    fi

    value="$(printf '%s\n' "$values_list" | awk -F= -v k="$isg_key" '$1==k { print $2; exit }')"
    [ -z "$value" ] && value="0"

    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$mqtt_topic" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -m "$value" || printf 'ERROR: MQTT publish failed for topic %s\n' "$mqtt_topic" >&2
  done

  sleep_until_next_poll "$loop_started"
done
