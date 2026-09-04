from .common import Battery, BatteryLevelApproximation, BatteryStatus


class FakeDevice:
    def __init__(self, spec):
        self.name = spec.get("name", "")
        self.kind = spec.get("kind", "unknown")
        self.serial = spec.get("serial", "")
        self.online = spec.get("online", True)
        self._battery = spec.get("battery")

    def battery(self):
        if self._battery == "raise":
            raise OSError("device went away")
        if self._battery is None:
            return None
        level = self._battery.get("level")
        if isinstance(level, str):
            level = BatteryLevelApproximation[level]
        status = self._battery.get("status")
        return Battery(level, self._battery.get("next_level"), BatteryStatus[status] if status else None)


class FakeReceiver:
    def __init__(self, spec):
        self._devices = [FakeDevice(d) for d in spec.get("devices", [])]
        self.closed = False

    def __iter__(self):
        return iter(self._devices)

    def close(self):
        self.closed = True


def create_receiver(low_level, info, setting_callback=None):
    if info.get("fail"):
        return None
    return FakeReceiver(info)
