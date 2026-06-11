#!/bin/sh
# DS18B20 + DHT11 test yayınları (broker Pi'de)
BROKER="${MQTT_BROKER:-172.20.10.5}"
TOPIC="${MQTT_TOPIC:-tarim_sulama/7/telemetry}"

mosquitto_pub -h "$BROKER" -p 1883 -t "$TOPIC" -m '{"sensor":"ds18b20","sicaklik":24.1}'
sleep 1
mosquitto_pub -h "$BROKER" -p 1883 -t "$TOPIC" -m '{"sensor":"dht11","sicaklik":25.5,"nem":60.2}'
sleep 1
mosquitto_pub -h "$BROKER" -p 1883 -t "$TOPIC" -m '{"sensor":"ds18b20","sicaklik":24.3}'
sleep 1
mosquitto_pub -h "$BROKER" -p 1883 -t "$TOPIC" -m '{"sensor":"dht11","sicaklik":25.8,"nem":59.1}'
echo "4 test mesajı gönderildi → $TOPIC @ $BROKER"
