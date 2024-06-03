
module tb_qoi_compressor ();


//initial $dumpvars(1, tb_qoi_compressor);


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
// qoi_compressor module and its signals
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
wire        ctrl_ready;
reg         ctrl_start = 1'b0;
reg  [15:0] ctrl_width;
reg  [15:0] ctrl_height;

wire        i_tready;
reg         i_tvalid = 1'b0;
reg         i_tlast;
reg  [ 7:0] i_R, i_G, i_B;

reg         o_tready = 1'b1;
wire        o_tvalid;
wire        o_tlast;
wire [ 3:0] o_tkeep;
wire [31:0] o_tdata;

always @ (posedge clk) o_tready <= randuint(0, 1);   // Randomly generate o_tready (backpressure signal on output interface of qoi_compressor) to simulate harsh environments

qoi_compressor u_qoi_compressor (
    .rstn         ( rstn          ),
    .clk          ( clk           ),
    // control interface, use this interface to start a frame
    .ctrl_ready   ( ctrl_ready    ),
    .ctrl_start   ( ctrl_start    ),
    .ctrl_width   ( ctrl_width    ),
    .ctrl_height  ( ctrl_height   ),
    // input pixel interface (AXI-stream)
    .i_tready     ( i_tready      ),
    .i_tvalid     ( i_tvalid      ),
    .i_tlast      ( i_tlast       ),
    .i_R          ( i_R           ),
    .i_G          ( i_G           ),
    .i_B          ( i_B           ),
    // output compressed stream interface (AXI-stream)
    .o_tready     ( o_tready      ),
    .o_tvalid     ( o_tvalid      ),
    .o_tlast      ( o_tlast       ),
    .o_tkeep      ( o_tkeep       ),
    .o_tdata      ( o_tdata       )
);



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// task : push_ppm_image_to_qoi_compressor
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
task push_ppm_image_to_qoi_compressor;
    input [31:0] max_bubble_cnt;  // param: determines the maximum number of random bubbles inserted into the input stream, to test the robustness of qoi_compressor
    input [256*8:1] fname;        // param: ppm file name
    
    integer linelen, depth, scanf_num, start_cycle, i, width, height, fp;
    reg [256*8-1:0] line;
begin
    
    // open a ppm file and parse header ///////////////////////
    depth = 0;
    fp = $fopen(fname, "rb");
    if (fp==0) begin
        $display("*** error: could not open file %s", fname);
        $finish;
    end
    linelen = $fgets(line, fp);
    if (line[8*(linelen-2)+:16] != 16'h5036) begin
        $display("*** error: the first line must be P6");
        $fclose(fp);
        $finish;
    end
    scanf_num = $fgets(line, fp);
    scanf_num = $sscanf(line, "%d%d", width, height);
    if(scanf_num == 1) begin
        scanf_num = $fgets(line, fp);
        scanf_num = $sscanf(line, "%d", height);
    end
    scanf_num = $fgets(line, fp);
    scanf_num = $sscanf(line, "%d", depth);
    if (depth>255) begin
        $display("*** error: images depth must <= 255");
        $fclose(fp);
        $finish;
    end
    
    // control qoi_compressor to start compressing ///////////////////////
    @ (posedge clk);
    while (~ctrl_ready) @ (posedge clk);
    ctrl_start  <= 1'b1;
    ctrl_width  <= width;
    ctrl_height <= height;
    @(posedge clk);
    ctrl_start <= 0;
    
    start_cycle = cycle_count;
    
    // read pixels from file and push to qoi_compressor ///////////////////////
    for (i=0; i<height*width; i=i) begin
        @ (posedge clk);
        if (i_tready) begin
            repeat (randuint(0, max_bubble_cnt)) begin
                i_tvalid <= 1'b0;
                @ (posedge clk);
            end
        end
        if (~i_tvalid | i_tready) begin
            i_tvalid <= 1'b1;
            i_tlast  <= (i+1 == height*width) ? 1'b1 : 1'b0;
            i_R      <= $fgetc(fp);
            i_G      <= $fgetc(fp);
            i_B      <= $fgetc(fp);
            i = i+1;
        end
    end
    
    // wait for the last pixel to be done (i.e. handshake done) ///////////////////////
    @ (posedge clk);
    while ( !(~i_tvalid | i_tready) ) @ (posedge clk);
    i_tvalid <= 1'b0;
    
    $display("compress %20s (%5dx%5d) in %9d cycles", fname, width, height, (cycle_count-start_cycle));
    
    $fclose(fp);  // close file ///////////////////////
end
endtask



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// simulate process
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
initial begin
    push_ppm_image_to_qoi_compressor(  1 , "input_ppm/01.ppm");
    push_ppm_image_to_qoi_compressor(  1 , "input_ppm/02.ppm");
    push_ppm_image_to_qoi_compressor(  1 , "input_ppm/03.ppm");
    push_ppm_image_to_qoi_compressor(200 , "input_ppm/04.ppm");
    push_ppm_image_to_qoi_compressor( 40 , "input_ppm/05.ppm");
    push_ppm_image_to_qoi_compressor(  0 , "input_ppm/06.ppm");
    push_ppm_image_to_qoi_compressor( 10 , "input_ppm/07.ppm");
    push_ppm_image_to_qoi_compressor(  0 , "input_ppm/08.ppm");
    push_ppm_image_to_qoi_compressor(  2 , "input_ppm/09.ppm");
    push_ppm_image_to_qoi_compressor(  0 , "input_ppm/10.ppm");
    push_ppm_image_to_qoi_compressor(  7 , "input_ppm/11.ppm");
    push_ppm_image_to_qoi_compressor(  6 , "input_ppm/12.ppm");
    push_ppm_image_to_qoi_compressor(  3 , "input_ppm/13.ppm");
    push_ppm_image_to_qoi_compressor(  0 , "input_ppm/14.ppm");
    push_ppm_image_to_qoi_compressor(100 , "input_ppm/15.ppm");
    push_ppm_image_to_qoi_compressor(  1 , "input_ppm/16.ppm");
    push_ppm_image_to_qoi_compressor(  0 , "input_ppm/17.ppm");
    push_ppm_image_to_qoi_compressor(  2 , "input_ppm/18.ppm");
    push_ppm_image_to_qoi_compressor(  4 , "input_ppm/19.ppm");
    
    @ (posedge clk);
    while (~ctrl_ready) @ (posedge clk);
    
    $finish;
end



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// save the output QOI stream from qoi_compressor to .qoi files
//   to change the save path, see tb_save_result_to_file.v
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
tb_save_result_to_file u_tb_save_result_to_file (
    .clk          ( clk           ),
    .tready       ( o_tready      ),
    .tvalid       ( o_tvalid      ),
    .tdata        ( o_tdata       ),
    .tlast        ( o_tlast       ),
    .tkeep        ( o_tkeep       )
);


endmodule

