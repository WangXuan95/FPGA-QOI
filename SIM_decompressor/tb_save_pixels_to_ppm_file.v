

`define   OUT_FILE_PATH      "./output_ppm"
`define   OUT_FILE_FORMAT    "%02d.ppm"


module tb_save_pixels_to_ppm_file (
    input  wire        clk,
    // input : AXI-stream
    input  wire        tready,
    input  wire        tvalid,
    input  wire        tlast,
    input  wire [ 7:0] R, G, B,
    input  wire [31:0] width, height
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// save output stream to file
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
integer        fidx = 0;
integer        fptr = 0;
reg [1024*8:1] fname;           // 1024 bytes string buffer
reg [1024*8:1] f_path_format;   // 1024 bytes string buffer

initial $sformat(f_path_format, "%s\\%s", `OUT_FILE_PATH, `OUT_FILE_FORMAT);

always @ (posedge clk)
    if (tready & tvalid) begin
        if (fptr == 0) begin
            fidx = fidx + 1;
            $sformat(fname, f_path_format, fidx);
            fptr = $fopen(fname, "wb");
            if (fptr == 0) begin
                $display("***error : cannot open %s", fname);
                $stop;
            end
            $fwrite(fptr, "P6\n%1d %1d\n255\n", width, height);     // PPM header
        end
        $fwrite(fptr, "%c%c%c", R, G, B );
        if (tlast) begin
            $fclose(fptr);
            fptr = 0;
        end
    end


endmodule
