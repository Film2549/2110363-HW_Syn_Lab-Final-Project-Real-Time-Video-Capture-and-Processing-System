# Basys3 OV7670 VGA Camera Project

This project is a Verilog/Vivado implementation for displaying live video from an OV7670 camera module on a VGA monitor using a Basys 3 FPGA board.

## What This Project Does

- Configures the OV7670 camera through SCCB
- Captures RGB565 camera data
- Stores frames in Basys 3 block RAM
- Outputs video through VGA at 640x480 timing
- Supports simple real-time filters
- Includes a debug color-stripe pattern for testing VGA output

## Hardware Needed

- Digilent Basys 3 FPGA board
- OV7670 camera module
- VGA monitor
- Jumper wires for the camera connection

## Software Needed

- AMD/Xilinx Vivado
- Icarus Verilog, optional, for running the testbenches

## Controls

| Input | Function |
|---|---|
| `btnC` | Reset |
| `sw[1:0]` | Filter select |
| `sw[14]` | Resolution mode |
| `sw[15]` | Debug VGA pattern |

Filter modes:

| `sw[1:0]` | Mode |
|---|---|
| `00` | Raw video |
| `01` | Grayscale |
| `10` | Negative |
| `11` | Red-only |

Resolution modes:

| `sw[14]` | Mode |
|---|---|
| `0` | 320x240 RGB444, scaled to VGA |
| `1` | 640x480 3-bit grayscale |

## Main Files

```text
rtl/           Verilog source files
sim/           Testbenches
constraints/   Basys 3 pin constraints
scripts/       Vivado TCL scripts
reports/       Vivado reports
```

Main top-level file:

```text
rtl/top_ov7670_vga.v
```

Constraint file:

```text
constraints/basys3_ov7670_vga.xdc
```

## How To Use

Open the project in Vivado:

```tcl
open_project fnproject.xpr
```

Then run synthesis, implementation, and generate the bitstream.

You can also rebuild using the TCL script:

```tcl
source scripts/create_project.tcl
```

The generated bitstream is:

```text
fnproject.runs/impl_1/top_ov7670_vga.bit
```

## Notes

The design uses Basys 3 block RAM as a framebuffer. Because the board has limited memory, full-resolution mode uses grayscale, while the lower-resolution mode keeps color.

After reset or changing resolution mode, wait about one frame for the framebuffer to refill.

Thanks to [Quackudy](https://github.com/Quackudy), [ImtaeZ](https://github.com/ImtaeZ), and [Mavin]() for helping with this project😸🙏.
