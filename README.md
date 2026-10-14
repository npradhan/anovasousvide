# Anova Sous Vide Web

A small Python web app that controls an **Anova Precision Cooker (Bluetooth model)** from any browser on your network: phone, tablet or laptop.

It is a Python port of the [Aldaviva/SousVide](https://github.com/Aldaviva/SousVide) .NET library and its [protocol specification](https://github.com/Aldaviva/SousVide/wiki/Communication-Protocol), with a FastAPI web UI on top.

## How it fits together

```
 phone / laptop  ──HTTP (LAN)──▶  this server (Raspberry Pi, PC…)  ──Bluetooth LE──▶  Anova cooker
```

The Aldaviva library, and the Anova Precision Cooker 1.0 it targets, speak **only Bluetooth LE, not Wi‑Fi**. So:

- Run this server on a machine with Bluetooth that is **within about 10 m of the cooker**. A Raspberry Pi in the kitchen works well.
- Every other device on your LAN controls the cooker through the web page at `http://<server-ip>:8000`.

The SousVide library is C# (.NET) and can't be imported into Python directly, so `anova_web/cooker.py` re-implements its `AnovaPrecisionCooker` class with [bleak](https://github.com/hbldh/bleak). It keeps the library's behaviour:

| Library (`ISousVide`) | Python (`anova_web.cooker`) | Device command |
|---|---|---|
| `AnovaPrecisionCooker.Create(deviceId)` | `AnovaPrecisionCooker(BleakTransport(address))` + `connect()` | `read unit` |
| `ActualTemperature` | `state.actual_temp_c` | `read temp` |
| `DesiredTemperature` | `state.desired_temp_c` | `read set temp` |
| `IsRunning` | `state.is_running` | `status` |
| `SetDesiredTemperature(t)` | `set_desired_temperature(value, unit)` | `set temp N` |
| `Start()` / `Stop()` | `start()` / `stop()` | `start` / `stop` |
| `StartTimer(duration)` | `start_timer(minutes)` | `stop time`, `set timer N`, `start time` |
| `StopTimer()` | `stop_timer()` | `stop time` |
| `PropertyUpdateInterval` (1 s poll) | `property_update_interval` | |

It also behaves like the library in these ways:

- It talks to GATT service `0xffe0`, characteristic `0xffe1`, using ASCII commands that end in `\r`.
- It sends one request at a time, because the device's responses don't say which request they answer.
- It ignores `Invalid Command` responses.
- It polls every second and converts temperatures to and from the cooker's own unit.

It adds a few things the library doesn't have:

- It reconnects automatically after the connection drops.
- Every request has a timeout.
- It reassembles responses that arrive split across several Bluetooth messages.
- It shows the remaining timer time using `read timer`, a command other Anova clients use. If the cooker doesn't answer it, the app stops asking.
- A simulated cooker lets you try the app without hardware.

## Setup

Requires Python 3.10+ and a Bluetooth LE adapter. On Linux, BlueZ must be running (`sudo systemctl enable --now bluetooth`).

```sh
git clone https://github.com/npradhan/anovasousvide.git
cd anovasousvide
python3 -m venv .venv && . .venv/bin/activate
pip install -e .
```

### Prepare the cooker

1. Plug in the cooker.
2. Make sure no phone app is connected to it. BLE allows only one connection at a time.
3. If your OS asks for pairing, press the cooker's Bluetooth button and enter PIN `0000` (see [Bluetooth Pairing](https://github.com/Aldaviva/SousVide#bluetooth-pairing)). On Linux this is usually not needed; bleak connects directly.

Find the cooker (optional):

```sh
anova-web --scan
# 0C:B2:B7:xx:xx:xx  Anova
```

### Run

```sh
anova-web                               # connect to the first device named "Anova"
anova-web --address 0C:B2:B7:xx:xx:xx   # connect to a specific cooker
anova-web --mock                        # simulated cooker, no hardware needed
anova-web --port 8080 -v                # other port, and log all Bluetooth traffic
```

Then open `http://<server-ip>:8000` on any device on your LAN. (`python -m anova_web` works too.)

The page shows water and target temperature, with a °C/°F toggle. It has a start/stop button, a temperature input with ±0.5° buttons and presets, and a countdown timer that stops cooking when it runs out.

### Run on boot (Raspberry Pi / systemd)

```ini
# /etc/systemd/system/anova-web.service
[Unit]
Description=Anova sous vide web UI
After=bluetooth.target network-online.target

[Service]
ExecStart=/home/pi/anovasousvide/.venv/bin/anova-web
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl enable --now anova-web
```

## HTTP API

| Method | Path | Body | |
|---|---|---|---|
| GET | `/api/state` | | Current state (temps in °C and °F, running, timer, connection) |
| POST | `/api/start` | | Start cooking |
| POST | `/api/stop` | | Stop cooking |
| POST | `/api/temperature` | `{"value": 135, "unit": "f"}` | Set target temperature (5–99.9 °C) |
| POST | `/api/timer` | `{"minutes": 90}` | Start a countdown that stops cooking when it ends |
| DELETE | `/api/timer` | | Cancel the timer |

Errors return `422` for invalid input and `503` when the cooker can't be reached.

## Security

The server has **no authentication** and listens on all interfaces, so anyone on your LAN can control the cooker. Don't expose it to the internet. To restrict it, use `--host 127.0.0.1` or put it behind a reverse proxy with auth.

## Development

```sh
pip install -e '.[test]'
pytest
```

The tests use a fake Bluetooth transport that answers commands the way the real cooker does, plus the simulated cooker for the HTTP API.

## Credits

Protocol and reference implementation: [Aldaviva/SousVide](https://github.com/Aldaviva/SousVide) (Apache-2.0).
