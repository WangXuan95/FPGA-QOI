
module tb_qoi_decompressor ();


//initial $dumpvars(1, tb_qoi_decompressor);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// clock & reset
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
reg rstn = 1'b0;
reg clk  = 1'b0;
always #5 clk = ~clk;
initial begin repeat(4) @(posedge clk); rstn<=1'b1; end

integer cycle_count=0;
always @ (posedge clk) cycle_count<=cycle_count+1;



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// function : generate random unsigned integer
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
function  [31:0] randuint;
    input [31:0] min;
    input [31:0] max;
begin
    randuint = $random;
    if ( min != 0 || max != 'hFFFFFFFF )
        randuint = (randuint % (1+max-min)) + min;
end
endfunction



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// qoi_decompressor module and its signals
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
wire        i_tready;
reg         i_tvalid = 1'b0;
reg         i_tlast;
reg  [31:0] i_tdata;

reg         o_tready = 1'b1;
wire        o_tvalid;
wire        o_tlast;
wire [ 7:0] o_R, o_G, o_B;
wire [31:0] o_width, o_height;

always @ (posedge clk) o_tready <= randuint(0, 1);   // Randomly generate o_tready (backpressure signal on output interface of qoi_decompressor) to simulate harsh environments

qoi_decompressor u_qoi_decompressor (
    .rstn         ( rstn          ),
    .clk          ( clk           ),
    // input compressed QOI stream interface (AXI-stream)
    .i_tready     ( i_tready      ),
    .i_tvalid     ( i_tvalid      ),
    .i_tlast      ( i_tlast       ),
    .i_tdata      ( i_tdata       ),
    // output pixel interface (AXI-stream)
    .o_tready     ( o_tready      ),
    .o_tvalid     ( o_tvalid      ),
    .o_tlast      ( o_tlast       ),
    .o_R          ( o_R           ),
    .o_G          ( o_G           ),
    .o_B          ( o_B           ),
    .o_width      ( o_width       ),
    .o_height     ( o_height      )
);



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// task : push_qoi_file_to_qoi_decompressor
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
task push_qoi_file_to_qoi_decompressor;
    input [31:0] max_bubble_cnt;
    input [256*8:1] fname;
    
    integer start_cycle, fp, rd;
begin
    
    fp = $fopen(fname, "rb");
    if (fp==0) begin
        $display("*** error: could not open file %s", fname);
        $finish;
    end
    
    rd = $fgetc(fp);
    
    start_cycle = cycle_count;
    
    while (rd != -1) begin
        @ (posedge clk);
        if (i_tready) begin
            repeat (randuint(0, max_bubble_cnt)) begin
                i_tvalid <= 1'b0;
                @ (posedge clk);
            end
        end
        if (~i_tvalid | i_tready) begin
            i_tvalid <= 1'b1;
            
            i_tdata[ 7: 0] <= rd;
            i_tdata[15: 8] <= $fgetc(fp);
            i_tdata[23:16] <= $fgetc(fp);
            i_tdata[31:24] <= $fgetc(fp);
            
            rd = $fgetc(fp);
            
            i_tlast <= (rd == -1) ? 1'b1 : 1'b0;
        end
    end
    
    @ (posedge clk);
    while ( !(~i_tvalid | i_tready) ) @ (posedge clk);
    i_tvalid <= 1'b0;
    
    $display("decompress %20s in %9d cycles", fname, (cycle_count-start_cycle));
    
    $fclose(fp);
end
endtask



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// simulate process
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
initial begin
    push_qoi_file_to_qoi_decompressor(  0 , "input_qoi/01.qoi");
    push_qoi_file_to_qoi_decompressor(  1 , "input_qoi/02.qoi");
    push_qoi_file_to_qoi_decompressor(100 , "input_qoi/03.qoi");
    push_qoi_file_to_qoi_decompressor(  3 , "input_qoi/04.qoi");
    push_qoi_file_to_qoi_decompressor(  6 , "input_qoi/05.qoi");
    push_qoi_file_to_qoi_decompressor( 10 , "input_qoi/06.qoi");
    push_qoi_file_to_qoi_decompressor(  0 , "input_qoi/07.qoi");
    push_qoi_file_to_qoi_decompressor( 50 , "input_qoi/08.qoi");
    push_qoi_file_to_qoi_decompressor(  0 , "input_qoi/09.qoi");
    push_qoi_file_to_qoi_decompressor(  0 , "input_qoi/10.qoi");
    push_qoi_file_to_qoi_decompressor(  0 , "input_qoi/11.qoi");
    push_qoi_file_to_qoi_decompressor(  1 , "input_qoi/12.qoi");
    push_qoi_file_to_qoi_decompressor(  0 , "input_qoi/13.qoi");
    push_qoi_file_to_qoi_decompressor(  0 , "input_qoi/14.qoi");
    push_qoi_file_to_qoi_decompressor(  0 , "input_qoi/15.qoi");
    push_qoi_file_to_qoi_decompressor( 20 , "input_qoi/16.qoi");
    push_qoi_file_to_qoi_decompressor( 80 , "input_qoi/17.qoi");
    push_qoi_file_to_qoi_decompressor( 10 , "input_qoi/18.qoi");
    push_qoi_file_to_qoi_decompressor(  1 , "input_qoi/19.qoi");
    
    @ (posedge clk);
    while (~i_tready) @ (posedge clk);
    
    $finish;
end



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// save the output pixels from qoi_decompressor to .ppm image files
//   to change the save path, see tb_save_pixels_to_ppm_file.v
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
tb_save_pixels_to_ppm_file u_tb_save_pixels_to_ppm_file (
    .clk          ( clk           ),
    .tready       ( o_tready      ),
    .tvalid       ( o_tvalid      ),
    .tlast        ( o_tlast       ),
    .R            ( o_R           ),
    .G            ( o_G           ),
    .B            ( o_B           ),
    .width        ( o_width       ),
    .height       ( o_height      )
);


endmodule

