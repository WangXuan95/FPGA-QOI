del sim.out dump.vcd
iverilog  -g2001  -o sim.out  tb_qoi_compressor.v  ..\RTL\qoi_compressor.v  tb_save_result_to_file.v
vvp -n sim.out
del sim.out
pause