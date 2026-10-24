# TLSR8258 BLE Stack

Guide to understanding and working with the Telink TLSR8258 BLE stack structure as shipped in the Telink_825X_SDK.

## SDK structure (once mounted at /opt/telink/sdk)

```
/opt/telink/sdk/
├── tools/
│   └── tc32/bin/       ← tc32-elf-gcc, tc32-elf-g++, tc32-elf-gdb, tc32-elf-objcopy
├── b85m_ble_sdk/
│   ├── vendor/
│   │   ├── 8258_ble_sample/   ← reference BLE application
│   │   └── common/
│   ├── stack/ble/              ← BLE core (precompiled library)
│   ├── drivers/                ← hardware abstraction (SPI, UART, GPIO, etc.)
│   └── common/                 ← types, assert, printf-over-UART
└── doc/
```

## BLE application structure

The TLSR8258 BLE stack follows an event-driven model:

```
main()
  └── bls_app_init()
        ├── rf_drv_init()        // radio hardware init
        ├── blc_initMacAddress() // read MAC from flash
        ├── blc_ll_initBasicMCU()
        ├── blc_ll_initAdvertising_module()
        ├── blc_ll_initConnection_module()
        ├── blc_gap_peripheral_init()
        ├── blc_att_pushNotifyData() / blc_gatt_pushWriteData()
        └── user_init_normal()   ← YOUR APPLICATION CODE

main_loop()  (called in while(1))
  ├── blt_sdk_main_loop()        // BLE stack tick
  ├── proc_button()              // GPIO polling
  └── proc_led()                 // LED updates
```

## Key callback hooks

```c
// Called when a central connects to this peripheral
int app_connect_event_handler(u8 e, u8 *p, int n) {
    // p points to event data; e is the event type
    return 0;
}

// Registered via:
blc_hci_registerControllerEventHandler(app_connect_event_handler);

// GATT write callback (receives data from central)
int app_gatt_write_callback(void *p) {
    rf_packet_att_write_t *req = (rf_packet_att_write_t*)p;
    // req->value[0..n] = incoming data
    return 0;
}
```

## Advertising data format

```c
// Standard advertising packet structure (GAP)
u8 tbl_advData[] = {
    0x02, 0x01, 0x05,       // Flags: LE General Discoverable, BR/EDR Not Supported
    0x03, 0x03, 0xF0, 0xFF, // Complete List of 16-bit Service UUIDs: 0xFFF0
    0x09, 0x09, 'M','y','D','e','v','i','c','e'  // Complete Local Name: "MyDevice"
};
```

## Flash memory map (TLSR8258)

| Region | Address | Size |
|---|---|---|
| Bootloader | 0x000000 | 4 KB |
| OTA image 1 | 0x004000 | varies |
| Custom NVS | 0x076000 | 8 KB |
| MAC address | 0x07700A | 6 bytes |
| Calibration | 0x077000 | 256 bytes |

Reading/writing custom flash:
```c
flash_read_page(0x076000, sizeof(my_data), (u8*)&my_data);
flash_erase_sector(0x076000);
flash_write_page(0x076000, sizeof(my_data), (u8*)&my_data);
```

## Building a project

```bash
# From inside the SDK sample directory
make -j$(nproc) TC32_PATH=/opt/telink/sdk/tools/tc32

# Output: 8258_ble_sample.bin
ls -lh *.bin
```

## C++ usage notes

tc32-elf-g++ is available but the BLE SDK itself is written in C. Mixing works:
- Wrap `#include`s of SDK headers in `extern "C" { }` blocks.
- C++ classes and templates work.
- No STL. No exceptions. No RTTI. 16 KB RAM budget — treat like a bare-metal M0+.
