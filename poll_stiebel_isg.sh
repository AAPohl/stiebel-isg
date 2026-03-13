#!/bin/sh

MQTT_HOST="${MQTT_HOST:?MQTT_HOST is not set}"
MQTT_PORT="${MQTT_PORT:?MQTT_PORT is not set}"
MQTT_TOPIC="${MQTT_TOPIC:?MQTT_TOPIC is not set}"
MQTT_USERNAME="${MQTT_USERNAME:?MQTT_USERNAME is not set}"
MQTT_PASSWORD="${MQTT_PASSWORD:?MQTT_PASSWORD is not set}"

while true
do
  echo "Value: 42"
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -m "42" || echo "MQTT publish failed"
  sleep 30
done
