#!/bin/sh

MQTT_HOST="${MQTT_HOST:?MQTT_HOST is not set}"
MQTT_PORT="${MQTT_PORT:?MQTT_PORT is not set}"
MQTT_REQUESTS="${MQTT_REQUESTS:?MQTT_REQUESTS is not set}"
MQTT_USERNAME="${MQTT_USERNAME:?MQTT_USERNAME is not set}"
MQTT_PASSWORD="${MQTT_PASSWORD:?MQTT_PASSWORD is not set}"
ISG_URL="${ISG_URL:?ISG_URL is not set}"

read_isg_values() {
  topics="$1"
  printf '%s\n' "$topics" | tr ';' '\n' | while IFS= read -r topic
  do
    [ -z "$topic" ] && continue

    if ! response="$(curl -fsS --max-time 10 --get --data-urlencode "topic=$topic" "$ISG_URL" 2>/dev/null)"; then
      printf 'ERROR: curl request failed for topic %s\n' "$topic" >&2
      value="0"
    elif [ -z "$response" ]; then
      printf 'ERROR: empty curl response for topic %s\n' "$topic" >&2
      value="0"
    else
      value="${#response}"
    fi

    printf '%s=%s\n' "$topic" "$value"
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
  topic_list="$(
    printf '%s\n' "$MQTT_REQUESTS" | tr ';' '\n' | awk -F= 'NF==2 && $1!="" && $2!="" && $1!=$2 { print $2 }' | paste -sd';' -
  )"

  if [ -z "$topic_list" ]; then
    printf 'ERROR: No valid requests in MQTT_REQUESTS\n' >&2
    sleep 30
    continue
  fi

  values_list="$(read_isg_values "$topic_list")"

  printf '%s\n' "$MQTT_REQUESTS" | tr ';' '\n' | while IFS= read -r pair
  do
    [ -z "$pair" ] && continue
    isg_key="${pair%%=*}"
    mqtt_topic="${pair#*=}"

    if [ -z "$isg_key" ] || [ -z "$mqtt_topic" ] || [ "$isg_key" = "$mqtt_topic" ]; then
      printf 'ERROR: Skipping invalid request: %s\n' "$pair" >&2
      continue
    fi

    value="$(printf '%s\n' "$values_list" | awk -F= -v t="$mqtt_topic" '$1==t { print $2; exit }')"
    [ -z "$value" ] && value="0"

    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$mqtt_topic" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -m "$value" || printf 'ERROR: MQTT publish failed for topic %s\n' "$mqtt_topic" >&2
  done
  sleep 30
done

