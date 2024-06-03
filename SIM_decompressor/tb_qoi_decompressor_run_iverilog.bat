del sim.out dump.vcd
iverilog  -g2001  -o sim.out  tb_qoi_decompressor.v  ..\RTL\qoi_decompressor.v  tb_save_pixels_to_ppm_file.v
vvp -n sim.out
del sim.out
pause