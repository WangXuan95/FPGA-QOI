![语言](https://img.shields.io/badge/语言-verilog_(IEEE1364_2001)-9A90FD.svg) ![仿真](https://img.shields.io/badge/仿真-iverilog-green.svg) ![部署](https://img.shields.io/badge/部署-quartus-blue.svg) ![部署](https://img.shields.io/badge/部署-vivado-FF1010.svg)

　

<span id="en">FPGA-based QOI image compressor and decompressor</span>
===========================

**QOI** (Quite Okay Image) is a simple lossless RGB/RGBA image compression format. You can find QOI specification and reference software compressor/decompressor from [Official website of QOI](https://qoiformat.org/) . I also offer a simple QOI compressor/decompressor in C language, see [github.com/WangXuan95/ImCvt](https://github.com/WangXuan95/ImCvt) .

This repo offers **FPGA**-based streaming **QOI** compressor and decompressor, features:

* Pure Verilog design, compatible with various FPGA platforms.
* standard AXI-stream interface.
* [qoi_compressor.v](RTL/qoi_compressor.v) can compress raw RGB images to QOI streams.
* [qoi_decompressor.v](RTL/qoi_decompressor.v) can decompress QOI streams to raw RGB images.
* only support RGB, do not support RGBA.
* Performance: can compress/decompress a pixel (R, G, and B) per clock cycle.

　

# FPGA deployment result

|               FPGA chip                |  qoi_compressor.v   | qoi_decompressor.v  |
| :------------------------------------: | :-----------------: | :-----------------: |
| Xilinx ZYNQ Ultra+ XCZU3EG-SFVC784-2-E | 800 MHz ,  478 LUTs | 340 MHz ,  483 LUTs |
|     Xilinx Artix7 XC7A100TCSG324-1     | 295 MHz ,  458 LUTs | 102 MHz ,  467 LUTs |
|      Altera Cyclone4 EP4CE30F29C8      | 160 MHz ,  751 LEs  |  68 MHz ,  781 LEs  |

*Note*: The clock frequency of *qoi_decompressor.v* can be further optimized, which will be the future work.

　

# use qoi_compressor

The input and output signals of [qoi_compressor.v](RTL/qoi_compressor.v) is:

```verilog
module qoi_compressor (
    input  wire        rstn,
    input  wire        clk,
    // control interface, use this interface to start a image
    output wire        ctrl_ready,
    input  wire        ctrl_start,
    input  wire [15:0] ctrl_width,
    input  wire [15:0] ctrl_height,
    // input pixel interface (AXI-stream)
    output wire        i_tready,
    input  wire        i_tvalid,
    input  wire        i_tlast,
    input  wire [ 7:0] i_R, i_G, i_B,
    // output compressed QOI stream interface (AXI-stream)
    input  wire        o_tready,
    output reg         o_tvalid,
    output reg         o_tlast,
    output reg  [ 3:0] o_tkeep,
    output reg  [31:0] o_tdata      // little endian
);
```

To compress a image using [qoi_compressor.v](RTL/qoi_compressor.v) , you should:

1. **Handshake on the control interface**: set the image width and height on `ctrl_width` and `ctrl_height` , and let `ctrl_start=1` , when both `ctrl_start=ctrl_ready=1` at the same clock cycle, the handshake success.
2. **Push Pixels to the input pixel interface**: scan the raw image in raster order (from left to right, from top to bottom), push each pixel to the input pixel interface. The interface follows the AXI stream protocol, whenever `i_tready=i_tvalid=1`  , a handshake success and a pixel (R, G, and B) is pushed into the module.
3. **Obtain QOI compressed stream from the output interface**, which also follows the AXI-stream protocol. Note that the byte order of `o_tdata` is **little endian** .

After the above progress, you can go to step1 to compress the next image.

The obtained QOI compressed stream contains the complete QOI format (QOI file header + QOI compressed data). For example, here's a tiny QOI compressed stream, which only contains 21 bytes :

```
71 6F 69 66 00 00 00 02
00 00 00 02 03 00 FE 61
62 63 6E 37 6D
```

The module output this stream like this (be aware of **little endian**):

```
handshake1 : o_tdata = 32'h66696F71
handshake2 : o_tdata = 32'h02000000
handshake3 : o_tdata = 32'h02000000
handshake4 : o_tdata = 32'h61FE0003
handshake5 : o_tdata = 32'h376E6362
handshake6 : o_tdata = 32'hxxxxxx6D (o_tlast=1, o_tkeep=4'b0001)
```

There's only one byte in the last handshake, therefore `o_tkeep=4'b0001`.

　

# use qoi_decompressor

The input and output signals of [qoi_decompressor.v](RTL/qoi_decompressor.v) is:

```verilog
module qoi_decompressor (
    input  wire        rstn,
    input  wire        clk,
    // input compressed QOI stream interface (AXI-stream)
    output wire        i_tready,
    input  wire        i_tvalid,
    input  wire        i_tlast,
    input  wire [31:0] i_tdata,     // little endian
    // output pixel interface (AXI-stream)
    input  wire        o_tready,
    output reg         o_tvalid,
    output reg         o_tlast,
    output reg  [ 7:0] o_R, o_G, o_B,
    output wire [31:0] o_width, o_height
);
```

To decompress a QOI image using [qoi_decompressor.v](RTL/qoi_decompressor.v) , you should:

1. **Push QOI compressed stream to the input interface**: which follows the AXI-stream protocol. The byte order of `i_tdata` is **little endian** . Note that the input QOI data stream should be the complete QOI format (QOI file header + QOI compressed data).
2. **Obtain decompressed pixels from the output interface**, which also follows the AXI-stream protocol. 

Although the length of the input QOI stream may not be a multiple of 4,  `i_tkeep` signal is not required on the input interface, since the module knows how many pixels it needs to decompress and automatically blocks the excess input bytes in the last handshake.

But, we still need to let `i_tlast=1` at the last handshake by the end of a QOI stream.

　

# Simulation and Verification

I provide a simulation testbench of  [qoi_compressor.v](RTL/qoi_compressor.v)  in the [SIM_compressor](./SIM_compressor) folder.

And a simulation testbench of  [qoi_decompressor.v](RTL/qoi_decompressor.v)  in the [SIM_decompressor](./SIM_decompressor) folder.

### Simulate using iverilog

First, install iverilog , see: [iverilog_usage](https://github.com/WangXuan95/WangXuan95/blob/main/iverilog_usage/iverilog_usage.md) .

To run the testbench of [qoi_compressor.v](RTL/qoi_compressor.v)  , double-click *tb_qoi_compressor_run_iverilog.bat* , which will take about 10 minutes to simulate. It reads 19 raw PPM image files in the *input_ppm* folder, pushes them to the module, obtains the output QOI stream and write them to the *output_qoi* folder.

To run the testbench of   [qoi_decompressor.v](RTL/qoi_decompressor.v)  ， double-click *tb_qoi_decompressor_run_iverilog.bat* , which will take about 10 minutes to simulate. It reads 19 QOI files in the *input_qoi* folder , pushes them to the module, obtains the output pixels and write them to the *output_ppm* folder as PPM format.

To understand the waveform of the module input/output, you can export simulation waveforms and view them.

> Note: The PPM format is a very simple RGB image file format which contains the uncompressed raw RGB pixels. The format description of PPM can be found at : https://netpbm.sourceforge.net/doc/ppm.html

### Simulate using other simulators

Testbench is provided, just do it yourself.

　

　

　

# Related links

-  [Official website of QOI](https://qoiformat.org/) ：you can find QOI specification and software code here.
-  [github.com/WangXuan95/ImCvt](https://github.com/WangXuan95/ImCvt) : a simple QOI compressor/decompressor in C language, only 200 lines of C.
