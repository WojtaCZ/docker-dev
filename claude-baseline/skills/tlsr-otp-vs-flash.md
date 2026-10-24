# Telink TLSR8258: OTP vs Flash

Understanding the two non-volatile memory types on TLSR8258 and when to use each.

## Flash (NOR, 512 KB on TLSR8258)

The main program storage. Standard erase-write-read cycle:
- Erase unit: **4 KB sector** (sets all bytes to 0xFF).
- Write unit: any byte/word (can only write 0-bits; cannot flip 0→1 without erase).
- Endurance: ~100,000 erase cycles per sector.
- Read: random access, 0-wait-state at typical operating frequencies.

Operations via Telink SDK:
```c
// Erase one 4 KB sector
flash_erase_sector(addr);    // addr must be 4 KB-aligned

// Write up to 256 bytes (page write)
flash_write_page(addr, len, data_ptr);

// Read
flash_read_page(addr, len, data_ptr);
```

Flash is **not safe to modify while the radio is active** — the flash controller shares a bus with the RF engine. The Telink BLE stack handles this by suspending RF during flash operations via `flash_prot_enable()` / `flash_prot_disable()`, or by scheduling flash writes in the `blt_idle_loop`.

## OTP (One-Time Programmable, 256 bytes)

Telink TLSR8258 has a small OTP region typically used by the factory for:
- MAC address (at offset `0x00` in OTP / `0x07700A` in flash shadow)
- Trim and calibration values
- Production flags

**Cannot be erased or rewritten.** Write once per bit region (0→0 only).

Reading OTP:
```c
// OTP is mapped to the flash address space on TLSR — read via flash API
flash_read_page(0x077000, 256, otp_buffer);
```

## Wear levelling for frequently-updated data

For data written more than ~1000 times (e.g. connection counters, rolling codes, sensor calibration):

```c
// Simple log-structured write: find the last written page, write the next
// Erase when the sector is full (wrap around)
#define STORAGE_BASE  0x076000
#define STORAGE_PAGES 16       // 16 × 256-byte pages per 4 KB sector

static uint32_t find_last_page() {
    for (int i = STORAGE_PAGES - 1; i >= 0; --i) {
        uint8_t hdr;
        flash_read_page(STORAGE_BASE + i * 256, 1, &hdr);
        if (hdr != 0xFF) return i;
    }
    return STORAGE_PAGES;  // all erased
}

void storage_write(const uint8_t* data, uint8_t len) {
    uint32_t page = find_last_page() + 1;
    if (page >= STORAGE_PAGES) {
        flash_erase_sector(STORAGE_BASE);
        page = 0;
    }
    flash_write_page(STORAGE_BASE + page * 256, len, (u8*)data);
}
```

## Flashing the device

The TLSR8258 does not expose a standard SWD interface — it uses Telink's proprietary **SWS** (Single Wire Serial) protocol.

Tools:
- **Telink BDT** (Burning Debug Tool) — Windows GUI, requires the SWS USB dongle.
- **BMP with tlsr_tools** — community driver that implements SWS over a BMP GPIO. Experimental.
- **OpenOCD** does not support TLSR8258/SWS natively as of 0.12.

With BMP + SWS (via `tlsr_tools` community tool):
```bash
# Build tlsr_tools from: https://github.com/Ai-Thinker-Open/TLSR825x_Tools
# Then:
./tlsr_term.py -p /dev/ttyACM0 flash -a 0x000000 firmware.bin
```

Without BDT or community tools: flashing requires a Windows host with Telink BDT GUI.
