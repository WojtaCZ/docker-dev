# CH32V Low Power

Strategies for minimising power on WCH CH32V003 and compatible CH32V devices.

## CH32V003 power modes

| Mode | Core | Peripherals | Wake-up | IDD (typ) |
|---|---|---|---|---|
| Run (48 MHz, all on) | On | On | — | ~14 mA |
| Sleep | Off (WFI) | On | Any IRQ | ~2–3 mA |
| Stop | Off | LDO on, most clocks off | EXTI, TIM, USART | ~20–80 µA |
| Standby | Off | Only VBAT domain | NRST, WKUP pin | ~2–4 µA |

## Entering sleep mode

```cpp
#include "ch32v003fun.h"

// Idle the core — peripherals keep running
// Wake on any IRQ (WFI) or any event (WFE)
__asm volatile ("wfi");   // wait for interrupt
```

## Entering stop mode

```cpp
// Enable low-power stop mode via PWR and RCC
RCC->APB1PCENR |= RCC_APB1Periph_PWR;   // enable PWR clock
PWR->CTLR      |= PWR_CTLR_PDDS;        // select STOP (not STANDBY)
PWR->CTLR      &= ~PWR_CTLR_PDDS;       // actually: PDDS=0 for STOP
SCB->SCR       |= SCB_SCR_SLEEPDEEP_Msk;
__asm volatile("wfi");
SCB->SCR       &= ~SCB_SCR_SLEEPDEEP_Msk;
// After wake: re-initialise clocks (PLL is off during STOP)
SystemInit();
```

## Reducing run-mode consumption

1. **Lower the clock.** At 8 MHz (HSI no PLL): ~3 mA. At 48 MHz: ~14 mA. Set via `SetSysClockTo_XX()` from `system_ch32v003.c`.

2. **Disable unused peripherals** (APB clock gate off saves ~100–500 µA per active block):
   ```cpp
   RCC->APB2PCENR &= ~RCC_APB2Periph_ADC1;   // disable ADC clock
   RCC->APB1PCENR &= ~RCC_APB1Periph_TIM2;   // disable TIM2 clock
   ```

3. **Configure unused GPIOs as input with pull-down** (floating inputs cause static current):
   ```cpp
   GPIOA->CFGLR = 0x88888888;  // all PA: input floating → change to input pull-down
   GPIOA->OUTDR = 0x00000000;  // pull-down (low level in output register → pull-down when in input mode)
   ```

4. **UART TX pin idle state.** UART TX idles high. If your board has a long trace on TX without a pull-up, configure the TX pin as a GPIO output high to avoid leakage current through a connected load.

## Measuring power

```bash
# With WCH-Link or BMP attached, measure with a low-shunt in the VCC line.
# Alternatively: read the ADC on a shunt resistor
# Simple command to verify the firmware size (smaller = less flash read power during run):
riscv-none-elf-size build/firmware.elf
```

## C++ power-aware timer wrapper

```cpp
struct SleepMs {
    explicit SleepMs(uint32_t ms) {
        // Configure TIM2 as a one-shot wakeup timer
        RCC->APB1PCENR |= RCC_APB1Periph_TIM2;
        TIM2->PSC = SystemCoreClock / 1000 - 1;  // 1 ms tick
        TIM2->ARR = ms - 1;
        TIM2->DIER = TIM_IT_Update;
        TIM2->CR1 = TIM_CR1_OPM | TIM_CR1_CEN;
        NVIC_EnableIRQ(TIM2_IRQn);
        __asm volatile("wfi");                   // sleep until TIM2 fires
        RCC->APB1PCENR &= ~RCC_APB1Periph_TIM2; // clock-gate TIM2 after wake
    }
};
```
