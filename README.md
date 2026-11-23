# Intelligent Traffic Light System

An adaptive two-road traffic light controller written in **HCS12 Assembly** for the **MC9S12DT256** and developed in **Freescale CodeWarrior for HC12**.

The controller uses two potentiometers to represent traffic density, adjusts green-light durations, handles an emergency request for Road A, and provides pedestrian crossings with an audible signal. An LCD displays road states and countdowns. A congestion alert is also implemented.

Developed for **COE324 - Microprocessors Lab, Fall 2026**, at the Lebanese American University.

## Features

- Adaptive green-light timing based on 8-bit ADC readings.
- Priority for the road with greater traffic density, with Road A selected when densities are equal.
- A maximum of two consecutive normal green phases for the same road before the other road receives a turn.
- Interrupt-driven traffic timing using the modulus down-counter, MCCNT.
- Road A emergency requests through the IRQ push button.
- Pedestrian requests through DIP switches, followed by an all-red crossing interval and a PWM buzzer tone.
- LCD road-state display and countdown updates every second.
- Heavy-traffic detection with an LCD warning and intermittent buzzer output.

## Hardware and software

| Item | Purpose |
|---|---|
| MC9S12DT256 training board | Runs the controller |
| CodeWarrior for HC12 | Assembly project, build, download and debugging |
| Board-specific `derivative.inc` | Register definitions and memory symbols |
| Built-in potentiometer | Road A traffic-density input |
| External 5 kΩ or 10 kΩ potentiometer | Road B traffic-density input |
| Six LEDs with individual 220 Ω or 330 Ω resistors | Red, yellow and green signals for both roads |
| Board LCD and its SPI interface | Startup message, road states, countdowns and congestion warning |
| PB1 / IRQ push button | Road A emergency request |
| SW3 DIP1 and DIP4 | Pedestrian requests |
| Buzzer circuitry connected to PWM outputs | Pedestrian and congestion tones |
| Compatible programming/debug interface | Downloads and runs the program on the board |

## Connections

| Signal | Microcontroller connection |
|---|---|
| Road A green LED | PA0 |
| Road A yellow LED | PA1 |
| Road A red LED | PA2 |
| Road B green LED | PA3 |
| Road B yellow LED | PA4 |
| Road B red LED | PA5 |
| Road A potentiometer | AN05, built into the board |
| Road B potentiometer wiper | AN03 |
| Emergency button | PB1 board push button, connected to IRQ |
| Road A pedestrian request | SW3 DIP1, read through Port B bit 0 |
| Road B pedestrian request | SW3 DIP4, read through Port B bit 3 |
| Pedestrian buzzer output | PWM4 |
| Heavy-traffic buzzer output | PWM5 |
| LCD interface | SPI0 routed to Port M |

Connect the external potentiometer's outer terminals to the board's 5 V supply and ground, and its middle terminal to AN03. Each traffic LED uses its own series resistor.

Pedestrian inputs are active-low in this implementation. PB1 is the board's push-button label. The emergency interrupt is handled through IRQ.

Use the training board's schematic to identify connector positions, LCD routing and buzzer connections. PWM4 and PWM5 are separate outputs and require suitable board routing or buzzer circuitry.

## Operation

### Startup

The LCD displays `TRAFFIC` on its first line and `CONTROL` on its second line for five seconds before normal operation begins.

### Density-based road selection

The controller reads AN05 and AN03 as values from 0 to 255. At the start of each normal cycle, it selects the road with the greater density. Equal values favour Road A, subject to the consecutive-green limit.

Green duration is calculated using integer arithmetic:

```text
T_green = 5 + floor(density × 10 / 255) seconds
```

Normal green periods range from 5 to 15 seconds. The selected duration is set at the start of the phase. Density readings continue to update during operation for congestion monitoring and subsequent road selection.

### Traffic-light sequence

| Phase | Selected road | Other road | Duration |
|---|---|---|---|
| Green | Green | Red | 5–15 seconds, based on density |
| Yellow | Yellow | Red | 3 seconds |
| Clearance | Red | Red | 2 seconds |

After the sequence, the controller checks for pending emergency or pedestrian service and selects the next road.

The LCD identifies the state of each road and shows the active phase's remaining time, for example:

```text
A:G 14s
B:R
```

### Emergency priority

Pressing PB1 triggers an IRQ interrupt that sets an emergency flag. The main loop handles the request according to the current phase:

- If Road A is green, eight seconds are added to its remaining green time.
- If Road B is green, the controller transitions through three seconds of Road B yellow and two seconds of all-red clearance, then gives Road A eight seconds of green.
- If the request arrives during yellow or all-red clearance, the remaining transition completes before Road A receives the emergency green phase.

Pending emergency service takes precedence over a pedestrian request at the end of a cycle.

### Pedestrian crossing

SW3 DIP1 or DIP4 sets a shared pending pedestrian request. The current traffic sequence finishes before the crossing is served.

During the crossing:

- Both roads display red for approximately eight seconds.
- PWM4 generates a 1 kHz tone with a 50% duty cycle.
- The LCD displays both roads in the red state.

The pedestrian interval uses a software delay. Main-loop input processing pauses during this delay, while interrupts remain enabled. Return the DIP switch to its inactive position after requesting a crossing to avoid repeated requests.

### Heavy-traffic alert

When both ADC readings are at least 230:

- The LCD displays `HEAVY` and `TRAFFIC`.
- PWM5 produces a 5 kHz tone at a 50% duty cycle, alternating on and off each second.
- The normal traffic-light sequence continues.

The alert clears when either density drops below 230. The warning temporarily replaces the normal LCD countdown.

## Timing and program structure

The timer and PWM settings assume a **2 MHz bus clock**, as indicated by the source's timing calculations. A different clock configuration requires corresponding changes to MCCNT, PWM and software-delay settings.

MCCNT underflows every 0.5 seconds. Its interrupt service routine combines two ticks into a one-second flag. The main loop uses this flag to update phase durations, sample density and refresh the LCD.

| Routine | Responsibility |
|---|---|
| `NEWCYCLE` | Selects the next road and calculates green time |
| `READADC` | Reads Road A and Road B density inputs |
| `SETLEDS` | Applies the road/phase LED pattern |
| `EMGHAND` | Processes emergency requests |
| `PEDCROSS` | Runs the pedestrian crossing and audible signal |
| `HEAVYCHK` | Detects congestion and toggles its buzzer output |
| `SHOW` / `PRINT` | Formats and writes LCD messages |
| `MCISR` | Produces the one-second timing flag |
| `IRQISR` | Records the emergency request |

The source uses absolute assembly, with program code starting at `$4000` and explicit MCCNT, IRQ and reset vectors.

## Build and run in CodeWarrior

1. Open the project's CodeWarrior project file if the complete project is included in the repository.
2. If starting from the Assembly source only, create an **HCS12 absolute Assembly project** targeting the **MC9S12DT256** in CodeWarrior for HC12.
3. Use the project's supplied `derivative.inc` and confirm that the target, memory configuration and interrupt-vector handling match the board. The source depends on `RAMStart`, `RAMEnd` and the device register definitions.
4. Add the Assembly source as the application's main source file. Avoid including another startup source that defines the same entry points or vectors.
5. Verify the board's 2 MHz bus-clock configuration and connect the hardware according to the connection table.
6. Build the project using CodeWarrior's **Make/Build** command.
7. Select the board's supported programming/debug connection and download the program.
8. Run the program and confirm that the five-second startup message appears.
9. Vary the potentiometers and exercise the emergency and pedestrian controls.

The standalone Assembly file requires the matching CodeWarrior project configuration and board support files to build and run.

## Hardware demonstration checklist

The project has been reported as working on the training board. The following checks document its principal demonstrations:

- Set Road A density above Road B and observe Road A priority.
- Reverse the density values and observe Road B priority.
- Set equal densities and check Road A selection, accounting for the consecutive-green limit.
- Check five-second and fifteen-second green periods at the minimum and maximum ADC readings.
- Keep one road more congested and verify that the other receives a normal turn after two consecutive green phases.
- Press PB1 during Road A green and observe the eight-second extension.
- Press PB1 during Road B green and observe the transition to Road A emergency service.
- Request a pedestrian crossing and check the all-red interval and PWM4 tone.
- Raise both densities to at least 230 and check the congestion message and intermittent PWM5 tone.
- Lower either density below 230 and check that the congestion alert clears.

## Engineering concepts

HCS12 Assembly programming, register-level peripheral configuration, ADC acquisition, interrupt service routines, timer-based sequencing, PWM generation, SPI LCD interfacing, integer arithmetic, state-based control and hardware testing.
