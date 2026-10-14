"""Python port of the Aldaviva/SousVide ``AnovaPrecisionCooker`` client.

The Anova Precision Cooker (Bluetooth model) exposes a single GATT
characteristic. Requests are ASCII strings terminated with ``\\r`` written to
that characteristic, and responses arrive as notifications on it. Responses
carry no request ID, so requests must be strictly serialized. The device never
pushes unsolicited updates, so state has to be polled.

See https://github.com/Aldaviva/SousVide/wiki/Communication-Protocol
"""

from __future__ import annotations

import abc
import asyncio
import logging
import time
from dataclasses import asdict, dataclass
from typing import Callable, Optional

log = logging.getLogger(__name__)

DEVICE_NAME = "Anova"
SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb"
CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb"
RESPONSE_INVALID_COMMAND = "Invalid Command"

# The device accepts set points in this range (Celsius).
MIN_TEMP_C = 5.0
MAX_TEMP_C = 99.9
MAX_TIMER_MINUTES = 6000


def c_to_f(c: float) -> float:
    return c * 9 / 5 + 32


def f_to_c(f: float) -> float:
    return (f - 32) * 5 / 9


def to_celsius(value: float, unit: str) -> float:
    return value if unit == "c" else f_to_c(value)


def from_celsius(value_c: float, unit: str) -> float:
    return value_c if unit == "c" else c_to_f(value_c)


class CookerError(Exception):
    """Raised when the cooker cannot be reached or a request fails."""


@dataclass
class CookerState:
    connected: bool = False
    device_id: Optional[str] = None
    device_unit: str = "f"
    is_running: bool = False
    actual_temp_c: Optional[float] = None
    desired_temp_c: Optional[float] = None
    timer_minutes: Optional[int] = None
    timer_running: bool = False
    last_update: Optional[float] = None
    error: Optional[str] = None
    mock: bool = False

    def to_dict(self) -> dict:
        d = asdict(self)
        for key in ("actual_temp", "desired_temp"):
            c = d[f"{key}_c"]
            d[f"{key}_f"] = None if c is None else round(c_to_f(c), 1)
            d[f"{key}_c"] = None if c is None else round(c, 1)
        return d


class SousVide(abc.ABC):
    """Common interface, mirroring ``ISousVide`` from the .NET library."""

    def __init__(self) -> None:
        self.state = CookerState()
        self.property_update_interval = 1.0

    @abc.abstractmethod
    async def connect(self) -> None: ...

    @abc.abstractmethod
    async def close(self) -> None: ...

    @abc.abstractmethod
    async def update_properties(self) -> None: ...

    @abc.abstractmethod
    async def start(self) -> None: ...

    @abc.abstractmethod
    async def stop(self) -> None: ...

    @abc.abstractmethod
    async def set_desired_temperature(self, value: float, unit: str = "c") -> None: ...

    @abc.abstractmethod
    async def start_timer(self, minutes: int) -> None: ...

    @abc.abstractmethod
    async def stop_timer(self) -> None: ...

    async def run(self, stop_event: asyncio.Event) -> None:
        """Keep the cooker connected and its state fresh until ``stop_event`` is set."""
        backoff = 1.0
        failures = 0
        while not stop_event.is_set():
            try:
                if not self.state.connected:
                    await self.connect()
                    backoff = 1.0
                await self.update_properties()
                self.state.error = None
                failures = 0
                delay = self.property_update_interval
            except Exception as e:  # keep the loop alive no matter what
                log.warning("Cooker poll failed: %s", e)
                self.state.error = str(e)
                failures += 1
                if self.state.connected and failures >= 3:
                    # The link looks dead even though it was never reported as dropped.
                    try:
                        await self.close()
                    except Exception:
                        self.state.connected = False
                if not self.state.connected:
                    delay = backoff
                    backoff = min(backoff * 2, 30.0)
                else:
                    delay = self.property_update_interval
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=delay)
            except asyncio.TimeoutError:
                pass
        await self.close()


def _validate_temperature(value: float, unit: str) -> float:
    unit = unit.lower()
    if unit not in ("c", "f"):
        raise ValueError("unit must be 'c' or 'f'")
    value_c = to_celsius(float(value), unit)
    if not MIN_TEMP_C <= value_c <= MAX_TEMP_C:
        raise ValueError(
            f"temperature must be between {MIN_TEMP_C}°C and {MAX_TEMP_C}°C "
            f"({c_to_f(MIN_TEMP_C):.1f}°F and {c_to_f(MAX_TEMP_C):.1f}°F)"
        )
    return value_c


def _validate_timer(minutes: int) -> int:
    minutes = int(minutes)
    if minutes < 1:
        raise ValueError("Timer must be at least 1 minute")
    if minutes > MAX_TIMER_MINUTES:
        raise ValueError(f"Timer must be at most {MAX_TIMER_MINUTES} minutes")
    return minutes


class Transport(abc.ABC):
    """Byte pipe to the cooker's characteristic. Abstracted so it can be faked in tests."""

    on_data: Callable[[bytes], None]
    on_disconnect: Callable[[], None]

    @property
    @abc.abstractmethod
    def device_id(self) -> str: ...

    @abc.abstractmethod
    async def connect(self) -> None: ...

    @abc.abstractmethod
    async def write(self, data: bytes) -> None: ...

    @abc.abstractmethod
    async def disconnect(self) -> None: ...


class BleakTransport(Transport):
    """Bluetooth LE transport using bleak (Linux/BlueZ, macOS, Windows)."""

    def __init__(self, address: Optional[str] = None, scan_timeout: float = 10.0) -> None:
        self.address = address
        self.scan_timeout = scan_timeout
        self._client = None
        self._device_id = address or ""

    @property
    def device_id(self) -> str:
        return self._device_id

    async def connect(self) -> None:
        from bleak import BleakClient, BleakScanner

        if self.address:
            device = await BleakScanner.find_device_by_address(self.address, timeout=self.scan_timeout)
        else:
            device = await BleakScanner.find_device_by_name(DEVICE_NAME, timeout=self.scan_timeout)
        if device is None:
            target = self.address or f"a device named '{DEVICE_NAME}'"
            raise CookerError(
                f"Could not find {target} over Bluetooth. Make sure the cooker is plugged in, "
                "in range, and not connected to another phone/app."
            )
        self._device_id = device.address

        client = BleakClient(device, disconnected_callback=lambda _c: self.on_disconnect())
        await client.connect()
        if client.services.get_service(SERVICE_UUID) is None:
            await client.disconnect()
            raise CookerError(f"Device {device.address} does not expose service {SERVICE_UUID}")
        await client.start_notify(CHARACTERISTIC_UUID, lambda _ch, data: self.on_data(bytes(data)))
        self._client = client

    async def write(self, data: bytes) -> None:
        if self._client is None or not self._client.is_connected:
            raise CookerError("Not connected")
        await self._client.write_gatt_char(CHARACTERISTIC_UUID, data, response=False)

    async def disconnect(self) -> None:
        client, self._client = self._client, None
        if client is not None:
            try:
                await client.stop_notify(CHARACTERISTIC_UUID)
            except Exception:
                pass
            await client.disconnect()


async def scan(timeout: float = 5.0) -> list[dict]:
    """Return nearby BLE devices named ``Anova``."""
    from bleak import BleakScanner

    devices = await BleakScanner.discover(timeout=timeout)
    return [{"address": d.address, "name": d.name} for d in devices if d.name == DEVICE_NAME]


class AnovaPrecisionCooker(SousVide):
    """Anova Precision Cooker driven over a :class:`Transport`."""

    # If a notification arrives without a trailing CR, treat it as complete after this delay.
    FRAGMENT_FLUSH_SECONDS = 0.15

    def __init__(self, transport: Transport, response_timeout: float = 5.0) -> None:
        super().__init__()
        self.transport = transport
        self.response_timeout = response_timeout
        self._lock = asyncio.Lock()
        self._pending: Optional[asyncio.Future[str]] = None
        self._buffer = ""
        self._flush_handle: Optional[asyncio.TimerHandle] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._timer_supported = True
        transport.on_data = self._on_data
        transport.on_disconnect = self._on_disconnect

    # ---- connection -------------------------------------------------------

    async def connect(self) -> None:
        self._loop = asyncio.get_running_loop()
        self._buffer = ""
        await self.transport.connect()
        self.state.connected = True
        self.state.device_id = self.transport.device_id
        try:
            unit = await self.request("read unit")
            self.state.device_unit = "c" if unit.strip().lower() == "c" else "f"
            await self.update_properties()
        except Exception:
            await self.close()
            raise
        log.info("Connected to Anova %s (unit %s)", self.state.device_id, self.state.device_unit)

    async def close(self) -> None:
        self.state.connected = False
        self._fail_pending(CookerError("Disconnected"))
        await self.transport.disconnect()

    def _on_disconnect(self) -> None:
        log.warning("Cooker disconnected")
        self.state.connected = False
        if self._loop is not None:
            self._loop.call_soon_threadsafe(self._fail_pending, CookerError("Disconnected"))

    def _fail_pending(self, exc: Exception) -> None:
        if self._pending is not None and not self._pending.done():
            self._pending.set_exception(exc)

    # ---- request / response ----------------------------------------------

    def _on_data(self, data: bytes) -> None:
        # bleak may call this from another thread on some backends.
        if self._loop is None:
            return
        self._loop.call_soon_threadsafe(self._handle_chunk, data.decode("ascii", errors="replace"))

    def _handle_chunk(self, text: str) -> None:
        self._buffer += text
        if self._flush_handle is not None:
            self._flush_handle.cancel()
            self._flush_handle = None
        while "\r" in self._buffer or "\n" in self._buffer:
            idx = min(i for i in (self._buffer.find("\r"), self._buffer.find("\n")) if i >= 0)
            message, self._buffer = self._buffer[:idx], self._buffer[idx + 1:]
            self._handle_message(message)
        if self._buffer.strip():
            assert self._loop is not None
            self._flush_handle = self._loop.call_later(self.FRAGMENT_FLUSH_SECONDS, self._flush)

    def _flush(self) -> None:
        self._flush_handle = None
        message, self._buffer = self._buffer, ""
        self._handle_message(message)

    def _handle_message(self, message: str) -> None:
        message = message.strip()
        if not message:
            return
        log.debug("ble-rx %s", message)
        if message == RESPONSE_INVALID_COMMAND:
            # Same as the .NET library: ignore it and keep waiting.
            return
        if self._pending is not None and not self._pending.done():
            self._pending.set_result(message)

    async def request(self, command: str, expect_response: bool = True) -> str:
        """Send one command and (optionally) wait for its response."""
        async with self._lock:
            if not self.state.connected:
                raise CookerError("Not connected to the cooker")
            command = command.strip()
            log.debug("ble-tx %s", command)
            if not expect_response:
                await self.transport.write((command + "\r").encode("ascii"))
                return ""
            assert self._loop is not None
            self._pending = self._loop.create_future()
            try:
                await self.transport.write((command + "\r").encode("ascii"))
                return await asyncio.wait_for(self._pending, timeout=self.response_timeout)
            except asyncio.TimeoutError:
                raise CookerError(f"Timed out waiting for response to '{command}'") from None
            finally:
                self._pending = None

    # ---- polled properties ------------------------------------------------

    def _parse_temp(self, response: str) -> Optional[float]:
        try:
            return to_celsius(float(response), self.state.device_unit)
        except ValueError:
            return None

    async def update_properties(self) -> None:
        actual = self._parse_temp(await self.request("read temp"))
        if actual is not None:
            self.state.actual_temp_c = actual
        desired = self._parse_temp(await self.request("read set temp"))
        if desired is not None:
            self.state.desired_temp_c = desired
        self.state.is_running = (await self.request("status")).lower() != "stopped"
        if self._timer_supported:
            await self._update_timer()
        self.state.last_update = time.time()

    async def _update_timer(self) -> None:
        # Not in the SousVide spec, but other Anova clients use it: "<minutes> running|stopped".
        try:
            parts = (await self.request("read timer")).split()
            self.state.timer_minutes = int(float(parts[0]))
            self.state.timer_running = len(parts) > 1 and parts[1].lower() == "running"
        except CookerError:
            log.info("Cooker did not answer 'read timer'; disabling timer polling")
            self._timer_supported = False
        except (ValueError, IndexError):
            pass

    # ---- commands ---------------------------------------------------------

    async def start(self) -> None:
        await self.request("start")
        await self.update_properties()

    async def stop(self) -> None:
        await self.request("stop")
        await self.update_properties()

    async def set_desired_temperature(self, value: float, unit: str = "c") -> None:
        value_c = _validate_temperature(value, unit)
        device_value = from_celsius(value_c, self.state.device_unit)
        await self.request(f"set temp {device_value:.1f}")
        self.state.desired_temp_c = value_c

    async def start_timer(self, minutes: int) -> None:
        minutes = _validate_timer(minutes)
        await self.stop_timer()
        await self.request(f"set timer {minutes}")
        await self.request("start time", expect_response=False)
        self.state.timer_minutes = minutes
        self.state.timer_running = True

    async def stop_timer(self) -> None:
        await self.request("stop time")
        self.state.timer_running = False


class MockCooker(SousVide):
    """Simulated cooker, like ``MockSousVide`` in SousVideCtl. Handy without hardware."""

    def __init__(self, room_temp_c: float = 22.8) -> None:
        super().__init__()
        self.room_temp_c = room_temp_c
        self._timer_deadline: Optional[float] = None
        self.state.mock = True
        self.state.device_id = "mock"
        self.state.device_unit = "c"
        self.state.actual_temp_c = self.room_temp_c
        self.state.desired_temp_c = 57.2

    async def connect(self) -> None:
        self.state.connected = True

    async def close(self) -> None:
        self.state.connected = False

    async def update_properties(self) -> None:
        s = self.state
        ambient = s.desired_temp_c if s.is_running else self.room_temp_c
        s.actual_temp_c += (ambient - s.actual_temp_c) * 0.05
        if s.timer_running and self._timer_deadline is not None:
            remaining = self._timer_deadline - time.time()
            if remaining <= 0:
                s.timer_running = False
                s.timer_minutes = 0
                s.is_running = False
            else:
                s.timer_minutes = int(remaining // 60) + 1
        s.last_update = time.time()

    async def start(self) -> None:
        self.state.is_running = True

    async def stop(self) -> None:
        self.state.is_running = False

    async def set_desired_temperature(self, value: float, unit: str = "c") -> None:
        self.state.desired_temp_c = _validate_temperature(value, unit)

    async def start_timer(self, minutes: int) -> None:
        minutes = _validate_timer(minutes)
        self.state.timer_minutes = minutes
        self.state.timer_running = True
        self._timer_deadline = time.time() + minutes * 60

    async def stop_timer(self) -> None:
        self.state.timer_running = False
        self._timer_deadline = None
