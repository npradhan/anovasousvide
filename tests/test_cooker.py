import asyncio

import pytest

from anova_web.cooker import AnovaPrecisionCooker, CookerError, MockCooker, Transport


class FakeAnova(Transport):
    """Emulates the cooker's GATT characteristic, responding like the real device."""

    def __init__(self, unit="f", split_responses=False, no_cr=False, ignore=()):
        self.unit = unit
        self.set_temp = 135.0
        self.temp = 73.4
        self.status = "stopped"
        self.timer = 0
        self.timer_running = False
        self.split_responses = split_responses
        self.no_cr = no_cr
        self.ignore = set(ignore)
        self.sent = []

    @property
    def device_id(self):
        return "AA:BB:CC:DD:EE:FF"

    async def connect(self):
        pass

    async def disconnect(self):
        pass

    def _reply(self, text):
        payload = (text if self.no_cr else text + "\r").encode()
        if self.split_responses:
            chunks = [payload[:2], payload[2:]]
        else:
            chunks = [payload]
        loop = asyncio.get_running_loop()
        for i, chunk in enumerate(chunks):
            loop.call_later(0.001 * (i + 1), self.on_data, chunk)

    async def write(self, data):
        assert data.endswith(b"\r")
        cmd = data.decode().strip()
        self.sent.append(cmd)
        if cmd in self.ignore:
            return
        if cmd == "read unit":
            self._reply(self.unit)
        elif cmd == "read temp":
            self._reply(f"{self.temp:.1f}")
        elif cmd == "read set temp":
            self._reply(f"{self.set_temp:.1f}")
        elif cmd == "status":
            self._reply(self.status)
        elif cmd == "start":
            self.status = "running"
            self._reply("start")
        elif cmd == "stop":
            self.status = "stopped"
            self._reply("stop")
        elif cmd.startswith("set temp "):
            self.set_temp = float(cmd.split()[-1])
            self._reply(f"{self.set_temp:.1f}")
        elif cmd.startswith("set timer "):
            self.timer = int(cmd.split()[-1])
            self._reply(str(self.timer))
        elif cmd == "start time":
            self.timer_running = True  # no response, per the protocol spec
        elif cmd == "stop time":
            self.timer_running = False
            self._reply("stop time")
        elif cmd == "read timer":
            self._reply(f"{self.timer} {'running' if self.timer_running else 'stopped'}")
        else:
            self._reply("Invalid Command")


async def connected(**kwargs):
    fake = FakeAnova(**kwargs)
    cooker = AnovaPrecisionCooker(fake, response_timeout=0.3)
    await cooker.connect()
    return fake, cooker


async def test_connect_reads_state_in_fahrenheit():
    fake, cooker = await connected()
    s = cooker.state
    assert s.connected and s.device_id == "AA:BB:CC:DD:EE:FF"
    assert s.device_unit == "f"
    assert s.actual_temp_c == pytest.approx(23.0, abs=0.01)
    assert s.desired_temp_c == pytest.approx(57.22, abs=0.01)
    assert s.is_running is False
    assert fake.sent[:4] == ["read unit", "read temp", "read set temp", "status"]


async def test_start_and_stop():
    fake, cooker = await connected()
    await cooker.start()
    assert cooker.state.is_running
    await cooker.stop()
    assert not cooker.state.is_running
    assert "start" in fake.sent and "stop" in fake.sent


async def test_set_temperature_converts_to_device_unit():
    fake, cooker = await connected(unit="f")
    await cooker.set_desired_temperature(60, "c")
    assert "set temp 140.0" in fake.sent
    assert cooker.state.desired_temp_c == pytest.approx(60)

    fake, cooker = await connected(unit="c")
    await cooker.set_desired_temperature(135, "f")
    assert "set temp 57.2" in fake.sent


async def test_set_temperature_rejects_out_of_range():
    _, cooker = await connected()
    with pytest.raises(ValueError):
        await cooker.set_desired_temperature(120, "c")


async def test_timer_sequence_matches_library():
    fake, cooker = await connected()
    fake.sent.clear()
    await cooker.start_timer(90)
    assert fake.sent == ["stop time", "set timer 90", "start time"]
    assert cooker.state.timer_running and cooker.state.timer_minutes == 90
    with pytest.raises(ValueError):
        await cooker.start_timer(0)


async def test_fragmented_and_unterminated_responses():
    _, cooker = await connected(split_responses=True)
    assert cooker.state.desired_temp_c == pytest.approx(57.22, abs=0.01)
    _, cooker = await connected(no_cr=True)
    assert cooker.state.actual_temp_c == pytest.approx(23.0, abs=0.01)


async def test_unsupported_read_timer_is_disabled_after_timeout():
    fake, cooker = await connected()
    fake.ignore.add("read timer")
    await cooker.update_properties()
    fake.sent.clear()
    await cooker.update_properties()
    assert "read timer" not in fake.sent


async def test_timeout_raises_cooker_error():
    fake, cooker = await connected()
    fake.ignore.add("start")
    with pytest.raises(CookerError):
        await cooker.start()


async def test_requests_are_serialized():
    fake, cooker = await connected()
    fake.sent.clear()
    results = await asyncio.gather(*(cooker.request(c) for c in ["read temp", "status", "read set temp"]))
    assert results == ["73.4", "stopped", "135.0"]


async def test_disconnect_fails_pending_request():
    fake, cooker = await connected()
    fake.ignore.add("status")
    task = asyncio.create_task(cooker.request("status"))
    await asyncio.sleep(0.01)
    fake.on_disconnect()
    with pytest.raises(CookerError):
        await task
    assert not cooker.state.connected


async def test_mock_cooker_heats_up():
    cooker = MockCooker()
    await cooker.connect()
    await cooker.start()
    before = cooker.state.actual_temp_c
    await cooker.update_properties()
    assert cooker.state.actual_temp_c > before
