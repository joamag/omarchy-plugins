from enum import Flag, IntEnum


class BatteryStatus(Flag):
    DISCHARGING = 0x00
    RECHARGING = 0x01
    ALMOST_FULL = 0x02
    FULL = 0x03
    SLOW_RECHARGE = 0x04
    INVALID_BATTERY = 0x05
    THERMAL_ERROR = 0x06
    OFFLINE = 0xFF


class BatteryLevelApproximation(IntEnum):
    EMPTY = 0
    CRITICAL = 5
    LOW = 20
    GOOD = 50
    FULL = 90


class Battery:
    def __init__(self, level, next_level, status, voltage=None):
        self.level = level
        self.next_level = next_level
        self.status = status
        self.voltage = voltage
