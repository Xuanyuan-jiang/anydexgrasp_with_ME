"""
InspireHandR CAN Protocol Driver

USB-CAN adapter (USBCAN / CANalyst-II) based communication with Inspire Hand R.
Drop-in replacement for InspireHandR that uses CAN-over-serial protocol.

Protocol difference:
  - UART (InspireHandR.py): 0xEB 0x90 header, direct RS485
  - CAN  (this file):       0xAA 0xAA header, CAN extended frame via USB-CAN adapter
"""

import numpy as np
import serial
import time

try:
    from .InspireHandR import which_finger_to_close  # package import
except ImportError:
    from InspireHandR import which_finger_to_close   # standalone import via sys.path

# ---------------------------------------------------------------------------
# Register address table (shared between UART and CAN, same Inspire firmware)
# ---------------------------------------------------------------------------
REGDICT = {
    'posSet':     1474,   # 0x05C2
    'angleSet':   1486,   # 0x05CE
    'forceSet':   1498,   # 0x05DA
    'speedSet':   1522,   # 0x05F2
    'posAct':     1534,   # 0x05FE
    'angleAct':   1546,   # 0x060A
    'forceAct':   1582,   # 0x062E
    'current':    1594,   # 0x063A
    'errCode':    1606,   # 0x0646
    'statusCode': 1612,   # 0x064C
    'temp':       1618,   # 0x0652
    'clearErr':   1004,   # 0x03EC
    'saveFlash':  1005,   # 0x03ED
    'forceClb':   1009,   # 0x03F1
    'defSpeed':   1032,   # 0x0408
    'defPower':   1044,   # 0x0414
}


class InspireHandR_CAN:
    """
    Inspire Hand R driver using CAN-over-USB serial protocol.
    API-compatible with InspireHandR (UART version).
    """

    def __init__(self, port='/dev/ttyUSB0', hand_id=1):
        self.ser = serial.Serial(port, 115200, timeout=1)
        if not self.ser.is_open:
            raise RuntimeError(f"Failed to open serial port {port}")
        print(f"[InspireHandR_CAN] Port {port} opened (USB-CAN mode, hand_id={hand_id})")

        self.hand_id = hand_id
        # 14-bit binary string for CAN extended ID encoding
        self._id_14bit = format(hand_id, '014b')

        # Initial configuration (same as UART version)
        self.setpower(1000, 1000, 1000, 1000, 1000, 1000)
        self.setspeed(1000, 1000, 1000, 1000, 1000, 1000)
        self.set_clear_error()

        # Default init angles
        self.f1_init_angle = 1000   # 小指
        self.f2_init_angle = 1000   # 无名指
        self.f3_init_angle = 1000   # 中指
        self.f4_init_angle = 1000   # 食指
        self.f5_init_angle = 1000   # 拇指
        self.f6_init_angle = 1000   # 拇指转向掌心

        self.reset()

    # ==================================================================
    #  CAN-over-USB adapter  low-level helpers
    # ==================================================================

    def _make_ext_id_bytes(self, address, is_write):
        """Build CAN extended frame ID as little-endian 4-byte list.

        Layout (MSB first):
            Write: 0000010 | address_bits | hand_id_14bit
            Read:  0000000 | address_bits | hand_id_14bit
        """
        addr_bits = bin(address)[2:]
        prefix = "0000010" if is_write else "0000000"
        full_bits = f"{prefix}{addr_bits}{self._id_14bit}"

        num = int(full_bits, 2)
        hex_str = format(num, 'X')
        if len(hex_str) % 2:
            hex_str = '0' + hex_str
        # little-endian
        return [int(hex_str[i:i+2], 16)
                for i in range(0, len(hex_str), 2)][::-1]

    def _send_write_frame(self, address, data_bytes):
        """Send one CAN write frame via USB-CAN adapter.

        Frame layout (21 bytes total):
            AA AA | ext_id(4) | data(8, 0xFF padded) | DLC(1) 00 01 00 | chk | 55 55
        """
        ext_id = self._make_ext_id_bytes(address, is_write=True)
        dlc = len(data_bytes)

        buf = bytearray([0xAA, 0xAA])
        buf.extend(ext_id)
        buf.extend(data_bytes)
        if dlc < 8:
            buf.extend([0xFF] * (8 - dlc))
        # metadata: [DLC, 0x00, 0x01(extended frame), 0x00]
        buf.append(dlc)
        buf.extend([0x00, 0x01, 0x00])
        buf.append(sum(buf[2:]) & 0xFF)
        buf.extend([0x55, 0x55])

        self.ser.write(buf)
        self.ser.reset_input_buffer()

    def _send_read_request(self, address, req_len):
        """Send CAN read request and return raw response bytes.

        Frame layout (21 bytes total):
            AA AA | ext_id(4) | req_len 00*7 | 01 00 01 00 | chk | 55 55

        Response: 23 bytes from adapter.
        """
        ext_id = self._make_ext_id_bytes(address, is_write=False)

        buf = bytearray([0xAA, 0xAA])
        buf.extend(ext_id)
        # data payload: first byte = requested data length, rest zeros
        buf.append(req_len)
        buf.extend([0x00] * 7)
        # metadata for read request
        buf.extend([0x01, 0x00, 0x01, 0x00])
        buf.append(sum(buf[2:]) & 0xFF)
        buf.extend([0x55, 0x55])

        self.ser.write(buf)
        self.ser.reset_input_buffer()
        time.sleep(0.1)
        return self.ser.read(23)

    # ==================================================================
    #  Composite read / write helpers
    # ==================================================================

    def _write_6_uint16(self, address, values):
        """Write 6 uint16 values split across 2 CAN frames (4 + 2)."""
        # Frame 1: values[0..3] → address
        data1 = bytearray()
        for v in values[:4]:
            data1.append(v & 0xFF)
            data1.append((v >> 8) & 0xFF)
        self._send_write_frame(address, data1)

        # Frame 2: values[4..5] → address + 8
        data2 = bytearray()
        for v in values[4:6]:
            data2.append(v & 0xFF)
            data2.append((v >> 8) & 0xFF)
        self._send_write_frame(address + 8, data2)

    def _read_6_uint16(self, address):
        """Read 6 uint16 values via 2 CAN read requests (4 + 2)."""
        vals = []

        # First read: 4 values (8 bytes) from address
        resp1 = self._send_read_request(address, 0x08)
        if len(resp1) >= 14:
            for i in range(0, 8, 2):
                lo, hi = resp1[6 + i], resp1[6 + i + 1]
                v = (hi << 8) | lo
                vals.append(0 if v > 60000 else v)
        else:
            vals = [0] * 4

        # Second read: 2 values (4 bytes) from address + 8
        resp2 = self._send_read_request(address + 8, 0x04)
        if len(resp2) >= 10:
            for i in range(0, 4, 2):
                lo, hi = resp2[6 + i], resp2[6 + i + 1]
                v = (hi << 8) | lo
                vals.append(0 if v > 60000 else v)
        else:
            vals.extend([0, 0])

        return vals[:6]

    def _read_6_uint8(self, address):
        """Read 6 uint8 values (temp / error / status)."""
        resp = self._send_read_request(address, 0x06)
        if len(resp) >= 12:
            return [resp[6 + i] for i in range(6)]
        return [0] * 6

    # ==================================================================
    #  Public API  (same signatures as InspireHandR)
    # ==================================================================

    def setpos(self, pos1, pos2, pos3, pos4, pos5, pos6):
        for v in [pos1, pos2, pos3, pos4, pos5, pos6]:
            if v < -1 or v > 2000:
                print('数据超出正确范围：-1-2000')
                return
        self._write_6_uint16(REGDICT['posSet'],
            [v & 0xFFFF for v in [pos1, pos2, pos3, pos4, pos5, pos6]])

    def setangle(self, angle1, angle2, angle3, angle4, angle5, angle6):
        for v in [angle1, angle2, angle3, angle4, angle5, angle6]:
            if v < -1 or v > 1000:
                print('数据超出正确范围：-1-1000')
                return
        self._write_6_uint16(REGDICT['angleSet'],
            [v & 0xFFFF for v in [angle1, angle2, angle3, angle4, angle5, angle6]])

    def setpower(self, power1, power2, power3, power4, power5, power6):
        for v in [power1, power2, power3, power4, power5, power6]:
            if v < 0 or v > 1000:
                print('数据超出正确范围：0-1000')
                return
        self._write_6_uint16(REGDICT['forceSet'],
            [power1, power2, power3, power4, power5, power6])

    def setspeed(self, speed1, speed2, speed3, speed4, speed5, speed6):
        for v in [speed1, speed2, speed3, speed4, speed5, speed6]:
            if v < 0 or v > 1000:
                print('数据超出正确范围：0-1000')
                return
        self._write_6_uint16(REGDICT['speedSet'],
            [speed1, speed2, speed3, speed4, speed5, speed6])

    # ---- read registers ----

    def get_setpos(self):
        return self._read_6_uint16(REGDICT['posSet'])

    def get_setangle(self):
        return self._read_6_uint16(REGDICT['angleSet'])

    def get_setpower(self):
        return self._read_6_uint16(REGDICT['forceSet'])

    def get_actpos(self):
        return self._read_6_uint16(REGDICT['posAct'])

    def get_actangle(self):
        return self._read_6_uint16(REGDICT['angleAct'])

    def get_actforce(self):
        vals = self._read_6_uint16(REGDICT['forceAct'])
        return [v - 65536 if v > 32767 else v for v in vals]

    def get_current(self):
        return self._read_6_uint16(REGDICT['current'])

    def get_error(self):
        return self._read_6_uint8(REGDICT['errCode'])

    def get_status(self):
        return self._read_6_uint8(REGDICT['statusCode'])

    def get_temp(self):
        return self._read_6_uint8(REGDICT['temp'])

    # ---- single-value writes ----

    def set_clear_error(self):
        self._send_write_frame(REGDICT['clearErr'], bytearray([0x01, 0x00]))

    def set_save_flash(self):
        self._send_write_frame(REGDICT['saveFlash'], bytearray([0x01, 0x00]))

    def gesture_force_clb(self):
        self._send_write_frame(REGDICT['forceClb'], bytearray([0x01, 0x00]))

    # ---- default parameters ----

    def setdefaultspeed(self, speed1, speed2, speed3, speed4, speed5, speed6):
        for v in [speed1, speed2, speed3, speed4, speed5, speed6]:
            if v < 0 or v > 1000:
                print('数据超出正确范围：0-1000')
                return
        self._write_6_uint16(REGDICT['defSpeed'],
            [speed1, speed2, speed3, speed4, speed5, speed6])

    def setdefaultpower(self, power1, power2, power3, power4, power5, power6):
        for v in [power1, power2, power3, power4, power5, power6]:
            if v < 0 or v > 1000:
                print('数据超出正确范围：0-1000')
                return
        self._write_6_uint16(REGDICT['defPower'],
            [power1, power2, power3, power4, power5, power6])

    # ---- high-level actions ----

    def reset(self):
        self.setangle(
            self.f1_init_angle, self.f2_init_angle, self.f3_init_angle,
            self.f4_init_angle, self.f5_init_angle, self.f6_init_angle)

    def open_gripper(self, angle=np.array([1000, 1000, 1000, 1000, 1000, 1000]),
                     sleep_time=0.5):
        a = [int(x) for x in angle]
        self.setangle(*a)
        time.sleep(sleep_time)

    def close_gripper(self, InspireHandR_type, sleep_time=0.2):
        print("Close gripper (CAN)")
        close_finger = which_finger_to_close[str(int(InspireHandR_type))]
        angle = self.get_actangle()
        others_latitude = 60
        for _ in range(20):
            for ids, finger in enumerate(close_finger):
                if finger != 0:
                    angle[ids] = max(angle[ids] - others_latitude, finger)
            self.setangle(*[int(a) for a in angle])
        time.sleep(sleep_time)

    def soft_setpos(self, pos1, pos2, pos3, pos4, pos5, pos6):
        temp_value = [0] * 6
        is_static = [0] * 6
        static_value = [0] * 6
        pos_value = [pos1, pos2, pos3, pos4, pos5, pos6]
        tic = time.time()
        for ii in range(5):
            actforce = self.get_actforce()
            print('actforce:', actforce)
            for i, f in enumerate(actforce[:5]):
                if is_static[i] or f > 1000:
                    continue
                threshold = 100 if i == 5 else 50
                if f > threshold:
                    is_static[i] = 1
                    static_value[i] = temp_value[i]
            temp_value = pos_value.copy()
            for i in range(6):
                if is_static[i]:
                    pos_value[i] = static_value[i]
            self.setpos(*pos_value)
            print('ii: %d, toc=%f' % (ii, time.time() - tic))

    def close(self):
        """Close the serial port."""
        if self.ser and self.ser.is_open:
            self.ser.close()
