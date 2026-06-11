# Raspberry Pi MQTT hub dinleyici

Mosquitto broker zaten yayını kabul eder; bu script **+/+/telemetry** ve **+/+/command** kalıba abone olup gelen mesajları konsola yazdırır. İstenirse `MQTT_HUB_LOG` ile tek satır JSON dosyasına ekler.

## Başka ekiplerden bağlantı

- **Host:** Pi’nin yerel IP’si (örn. `172.20.10.5`)
- **Port:** `1883`
- **Topic örneği:** `tarim_sulama/<takim_no>/telemetry`

## Yerel yükleme (Mac → Pi)

Projede bu klasöre çık (`simulation_IOT/raspi`):

```bash
scp mqtt_hub_listener.py requirements.txt kutay@<PI_IP>:~/
ssh kutay@<PI_IP>
python3 -m venv ~/mqtt_hub_env   # yoksa bir kez oluşturun
~/mqtt_hub_env/bin/pip install -r ~/requirements.txt
```

Çalıştır:

```bash
export MQTT_HUB_LOG="$HOME/mqtt_hub_messages.jsonl"
~/mqtt_hub_env/bin/python ~/mqtt_hub_listener.py
```

Durdurmak için `Ctrl+C`.

## Ortam değişkenleri (isteğe bağlı)

| Değişken | Varsayılan | Açıklama |
|-----------|-------------|----------|
| `MQTT_BROKER` | `127.0.0.1` | Yerelde Mosquitto |
| `MQTT_PORT` | `1883` | |
| `MQTT_SUB_TOPICS` | `+/+/telemetry,+/+/command` | Virgülle birden fazla pattern |
| `MQTT_HUB_LOG` | (boş) | JSON Lines çıktı dosyası |
| `MQTT_HUB_CLIENT_ID` | `pi_hub_<pid>` | Benzersiz MQTT client id (çakışmayı önler) |

### `[hub] Bağlı` satırı sürekli tekrar ediyorsa

Genelde **aynı `client_id` ile birden fazla istemci** broker’da birbirini düşürür, istemci yeniden bağlanır. Kaç süreç olduğuna bakın: `pgrep -af mqtt_hub_listener`. Sabit bir isim gerekiyorsa: `export MQTT_HUB_CLIENT_ID=hub_ornek_1`.

Broker tarafı için: `sudo journalctl -u mosquitto -n 80 --no-pager`.
