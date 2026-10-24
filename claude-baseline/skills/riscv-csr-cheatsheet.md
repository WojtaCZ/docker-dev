# RISC-V CSR Cheatsheet (QingKe RV32EC on CH32V003)

Quick reference for the Control and Status Registers most useful when developing for WCH CH32V003 (QingKe V2A core, RV32EC ISA).

## CSR access in C++

```cpp
// Read a CSR
#define csr_read(csr)  ({ uint32_t val; __asm volatile("csrr %0, " #csr : "=r"(val)); val; })

// Write a CSR
#define csr_write(csr, val) __asm volatile("csrw " #csr ", %0" :: "r"((uint32_t)(val)))

// Set bits in a CSR
#define csr_set(csr, bits)   __asm volatile("csrs " #csr ", %0" :: "r"((uint32_t)(bits)))

// Clear bits in a CSR
#define csr_clear(csr, bits) __asm volatile("csrc " #csr ", %0" :: "r"((uint32_t)(bits)))
```

## Frequently used CSRs

| CSR name | Address | Purpose |
|---|---|---|
| `mstatus` | 0x300 | Machine status: MIE (bit 3) = global interrupt enable |
| `mie` | 0x304 | Machine interrupt enable: MEIE (bit 11) = external, MTIE (bit 7) = timer, MSIE (bit 3) = software |
| `mip` | 0x344 | Machine interrupt pending (read) |
| `mtvec` | 0x305 | Machine trap vector: base address of interrupt table (bit 0=0 direct, bit 0=1 vectored) |
| `mepc` | 0x341 | Machine exception program counter (return address from trap) |
| `mcause` | 0x342 | Exception/interrupt cause code |
| `mscratch` | 0x340 | Scratch register for trap handlers |
| `mcycle` | 0xB00 | Machine cycle counter (64-bit: mcycle + mcycleh) |
| `minstret` | 0xB02 | Machine instruction-retired counter |

## Enabling/disabling global interrupts

```cpp
// Enable global interrupts (MIE in mstatus)
inline void enable_interrupts()  { csr_set(mstatus, 0x8); }
inline void disable_interrupts() { csr_clear(mstatus, 0x8); }

// RAII guard
struct IrqLock {
    uint32_t saved;
    IrqLock() : saved(csr_read(mstatus)) { disable_interrupts(); }
    ~IrqLock() { csr_write(mstatus, saved); }
};
```

## Cycle counter for timing

```cpp
inline uint64_t get_cycles() {
    uint32_t lo, hi, hi2;
    do {
        hi = csr_read(mcycleh);
        lo = csr_read(mcycle);
        hi2 = csr_read(mcycleh);
    } while (hi != hi2);  // re-read on overflow
    return ((uint64_t)hi << 32) | lo;
}

// Usage: measure a code block
auto t0 = get_cycles();
do_work();
auto t1 = get_cycles();
uint32_t cycles = (uint32_t)(t1 - t0);
// At 48 MHz: cycles / 48 = microseconds
```

## PFIC (WCH-specific interrupt controller)

CH32V003 uses WCH's PFIC instead of the standard RISC-V PLIC:

```cpp
// Enable an interrupt (WCH ch32v003fun defines PFIC_EnableIRQ etc.)
PFIC_EnableIRQ(TIM1_UP_IRQn);
PFIC_SetPriority(TIM1_UP_IRQn, 0);    // 0 = highest priority

// In the trap vector, WCH vectored mode dispatches to the per-interrupt handler
// defined as: extern "C" void TIM1_UP_IRQHandler()
```
