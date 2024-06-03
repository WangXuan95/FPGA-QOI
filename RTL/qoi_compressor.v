
module qoi_compressor (
    input  wire        rstn,
    input  wire        clk,
    // control interface, use this interface to start a frame
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


localparam [2:0] S_INIT  = 3'd0,
                 S_HDR   = 3'd1,
                 S_WAIT  = 3'd2,
                 S_WORK  = 3'd3,
                 S_FLUSH = 3'd4;

reg  [ 2:0] state = S_INIT;
reg  [ 6:0] cnt   = 7'd0;
reg  [ 8:0] pipe_shift = 9'h0;
reg  [15:0] width, xpos, ypos;
reg         width_e1, xpos_e1;

wire   pipe_ready =  ~o_tvalid | o_tready;
wire   pipe_flow  = ((state == S_WORK && i_tvalid) || state==S_FLUSH) & pipe_ready;
reg    pipe_flow_r1, pipe_flow_r2;
always @ (posedge clk) {pipe_flow_r1, pipe_flow_r2} <= {pipe_flow, pipe_flow_r1};

assign ctrl_ready =  (state == S_WAIT);
assign i_tready   =  (state == S_WORK) & pipe_ready;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        state <= S_INIT;
        cnt   <= 7'd0;
        pipe_shift <= 9'h0;
        
    end else begin
        case (state)
            S_INIT :    // use this state to initialize hash table
                if (cnt < 7'd72) begin
                    cnt <= cnt + 7'd1;
                end else begin
                    cnt <= 7'd0;
                    state <= S_WAIT;
                end
            
            S_WAIT :
                state  <= ctrl_start ? S_HDR : S_WAIT;
            
            S_HDR  :
                if (pipe_ready) begin
                    if (cnt < 7'd2) begin
                        cnt <= cnt + 7'd1;
                    end else begin
                        cnt <= 7'd0;
                        state <= S_WORK;
                    end
                end
            
            S_WORK :
                if (pipe_ready & i_tvalid) begin
                    state <= ((xpos==16'd1 && ypos==16'd1) || i_tlast) ? S_FLUSH : S_WORK;
                    pipe_shift <= {1'b1, pipe_shift[8:1]};
                end
            
            default /*S_FLUSH*/ : begin
                state <= (pipe_shift == 9'h0) ? S_INIT : S_FLUSH;
                if (pipe_ready)
                    pipe_shift <= {1'b0, pipe_shift[8:1]};
            end
        endcase
    end


always @ (posedge clk)
    case (state)
        S_WAIT : begin
            width   <= (ctrl_width == 16'd0) ? 16'd1 : ctrl_width;
            xpos    <= (ctrl_width == 16'd0) ? 16'd1 : ctrl_width;
            width_e1<= (ctrl_width <= 16'd1);
            xpos_e1 <= (ctrl_width <= 16'd1);
            ypos    <= (ctrl_height== 16'd0) ? 16'd1 : ctrl_height;
        end
        
        S_WORK :
            if (pipe_ready & i_tvalid) begin
                if (xpos_e1) begin
                    xpos    <= width;
                    xpos_e1 <= width_e1;
                    ypos    <= ypos - 16'd1;
                end else begin
                    xpos    <= xpos - 16'd1;
                    xpos_e1 <=(xpos ==16'd2);
                end
            end
    endcase


wire    a_e, b_e, c_e, d_e, e_e, f_e, g_e, h_e, j_e;                 // pipeline stages : a~h
assign {a_e, b_e, c_e, d_e, e_e, f_e, g_e, h_e, j_e} = pipe_shift;   // extract enable bits of each pipeline stage

reg  [23:0] a_BGR, b_BGR, c_BGR, d_BGR, e_BGR, f_BGR;

reg         d_same_as_previous;
reg  [ 5:0] e_run   , f_run_m1;
reg         e_run_nz, f_run_nz;

reg  [ 7:0] d_dB, d_dG, d_dR;
reg  [ 7:0] e_xB, e_xG, e_xR;

reg         e_diff;
reg  [ 5:0] e_diff_d;

reg         f_diff;
reg  [ 5:0] f_diff_d;

reg         f_luma;
reg  [13:0] f_luma_d;

reg  [ 5:0] a_hash_5G, a_hash_7B, b_hash_5G7B, b_hash_3R;
reg  [ 5:0] c_hash=6'd0, d_hash, e_hash, f_hash;

reg  [24:0] HASH_TAB [63:0];    // 25b : 1b valid + 8b B + 8b G + 8b R
reg  [24:0] rd1, rd2, rd4;
wire [24:0] rd3, rd5;

always @ (posedge clk)  HASH_TAB[c_hash] <= {c_e, c_BGR}; // write HASH_TAB
always @ (posedge clk)  rd1 <= HASH_TAB[c_hash];          // read  HASH_TAB

always @ (posedge clk)  if (pipe_flow_r2) rd2 <= rd1;
assign                                    rd3  = pipe_flow_r2 ? rd1 : rd2;
always @ (posedge clk)  if (pipe_flow_r1) rd4 <= rd3;
assign                                    rd5  = pipe_flow_r1 ? rd3 : rd4;

reg         e_hash_BGR_e;
reg  [23:0] e_hash_BGR;
reg         f_hash_match;

reg  [ 1:0] g_type;      // 0:none   1:1byte   2:2byte   3:4byte
reg  [31:0] g_bytes;

reg  [ 1:0] g_rem_cnt;   // remain byte count : 0~3
reg  [23:0] g_rem_bytes;

wire [ 2:0] g_merge_cnt   = (g_type<2'd3) ?  ({1'b0,g_type}+{1'b0,g_rem_cnt}) : {1'b1,g_rem_cnt} ;
wire [55:0] g_merge_bytes = (g_rem_cnt==2'd0) ? {24'h0, g_bytes                   } :
                            (g_rem_cnt==2'd1) ? {16'h0, g_bytes, g_rem_bytes[ 7:0]} :
                            (g_rem_cnt==2'd2) ? { 8'h0, g_bytes, g_rem_bytes[15:0]} :
                                                {       g_bytes, g_rem_bytes      } ;

reg         h_tvalid;
reg         h_tlast;
reg  [ 3:0] h_tkeep;
reg  [31:0] h_tdata;


always @ (posedge clk)
    if (pipe_flow) begin
        {a_BGR, b_BGR, c_BGR, d_BGR, e_BGR, f_BGR} <= {i_B,i_G,i_R, a_BGR, b_BGR, c_BGR, d_BGR, e_BGR};
        
        d_same_as_previous <= c_e && d_e && (c_BGR == d_BGR);
        e_run    <= (d_same_as_previous && (e_run < 6'd62)) ? (e_run + 6'd1) : 6'd0;
        e_run_nz <= (d_same_as_previous && (e_run < 6'd62));
        f_run_m1 <= e_run - 6'd1;
        f_run_nz <= e_run_nz;
        
        d_dB <= c_BGR[23:16] - d_BGR[23:16] + 8'd2;
        d_dG <= c_BGR[15: 8] - d_BGR[15: 8] + 8'd2;
        d_dR <= c_BGR[ 7: 0] - d_BGR[ 7: 0] + 8'd2;
        
        e_xB <= d_dB - d_dG + 8'd8;
        e_xG <= d_dG        + 8'd30;
        e_xR <= d_dR - d_dG + 8'd8;
        
        e_diff   <= (d_dR<8'd4  && d_dG<8'd4  && d_dB<8'd4 ) && e_e;
        e_diff_d <= {d_dR[1:0],    d_dG[1:0],    d_dB[1:0]};
        
        f_diff   <= e_diff;
        f_diff_d <= e_diff_d;
        
        f_luma   <= (e_xR<8'd16 && e_xB<8'd16 && e_xG<8'd64) && f_e;
        f_luma_d <= {e_xR[3:0],    e_xB[3:0],    e_xG[5:0]};
        
        a_hash_5G  <= i_G[5:0] + {i_G[3:0],2'b0};
        a_hash_7B  <= i_B[5:0] + {i_B[4:0],1'b0} + {i_B[3:0],2'b0};
        b_hash_5G7B <= a_hash_5G + a_hash_7B;
        b_hash_3R   <= a_BGR[5:0] + {a_BGR[4:0],1'b0} + 6'd53;
        c_hash <= b_hash_3R + b_hash_5G7B;
        d_hash <= c_hash;
        e_hash <= d_hash;
        f_hash <= e_hash;
        
        {e_hash_BGR_e, e_hash_BGR} <= rd5;
        f_hash_match <= (e_hash_BGR_e && (e_hash_BGR == e_BGR));
        
        if (~f_e) begin
            g_type  <= 2'd0;
            g_bytes <= 0;
        end else if (f_run_nz) begin
            //if (e_run_nz) $display("QOI_OP_RUN    %d", f_run_m1+6'd1);
            g_type  <= e_run_nz ? 2'd0 : 2'd1;            // QOI_OP_RUN
            g_bytes <= {24'h0, 2'b11, f_run_m1};
        end else if (f_hash_match) begin                  // QOI_OP_INDEX
            //$display("QOI_OP_INDEX  %d", f_hash);
            g_type  <= 2'd1;
            g_bytes <= {24'h0, 2'b00, f_hash};
        end else if (f_diff) begin                        // QOI_OP_DIFF
            //$display("QOI_OP_DIFF   %1x  %1x  %1x", f_diff_d[5:4], f_diff_d[3:2], f_diff_d[1:0] );
            g_type  <= 2'd1;
            g_bytes <= {24'h0, 2'b01, f_diff_d};
        end else if (f_luma) begin                        // QOI_OP_LUMA
            //$display("QOI_OP_LUMA   %1x  %1x  %02x", f_luma_d[13:10], f_luma_d[9:6], f_luma_d[5:0] );
            g_type  <= 2'd2;
            g_bytes <= {16'h0, f_luma_d[13:6], 2'b10, f_luma_d[5:0]};
        end else begin                                    // QOI_OP_RGB
            //$display("QOI_OP_RGB    %02x  %02x  %02x", f_BGR[23:16], f_BGR[15:8], f_BGR[7:0] );
            g_type  <= 2'd3;
            g_bytes <= {f_BGR, 8'hFE};
        end
        
        if (g_e) begin
            if (g_merge_cnt[2]) begin
                g_rem_cnt   <= g_merge_cnt[1:0];
                g_rem_bytes <= g_merge_bytes[55:32];
                
                h_tvalid <= 1'b1;
                h_tlast  <= (~f_e) && (g_merge_cnt[1:0]==2'd0);
                h_tkeep  <= 4'b1111;
                h_tdata  <= g_merge_bytes[31:0];
            end else begin
                g_rem_cnt   <= g_merge_cnt[1:0];
                g_rem_bytes <= g_merge_bytes[23:0];
                
                h_tvalid <= 1'b0;
            end
        end else if (h_e) begin       // g_e=0, h_e=1  only when the end, flush the remain bytes in g_rem_bytes
            h_tvalid <= (g_rem_cnt > 2'd0) ? 1'b1 : 1'b0;
            h_tlast  <= (g_rem_cnt > 2'd0) ? 1'b1 : 1'b0;
            h_tkeep  <= (g_rem_cnt== 2'd3) ? 4'b0111 : (g_rem_cnt==2'd2) ? 4'b0011 : 4'b0001 ;
            h_tdata  <= {8'h0, g_rem_bytes};
        end else begin
            h_tvalid <= 1'b0;
            h_tlast  <= 1'b0;
        end
        
    end else if (state == S_INIT) begin
        c_hash <= c_hash + 6'd1;
        
        g_rem_cnt   <= 2'd2;       // init: the last 2 bytes in header "\x03\x00"
        g_rem_bytes <= 24'h00_03;  // init: the last 2 bytes in header "\x03\x00"
        
        h_tvalid <= 1'b0;
    end


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        {o_tvalid, o_tlast, o_tkeep, o_tdata} <= 38'h0;
    end else begin
        if (state==S_HDR && pipe_ready) begin
            o_tvalid <= 1'b1;
            o_tlast  <= 1'b0;
            o_tkeep  <= 4'b1111;
            o_tdata  <= (cnt==7'd0) ? 32'h66_69_6f_71                :  // "qoif" in little endian
                        (cnt==7'd1) ? {xpos[7:0], xpos[15:8], 16'd0} :  // image width
                                      {ypos[7:0], ypos[15:8], 16'd0} ;  // image height
        end else if (pipe_flow) begin
            o_tvalid <= h_tvalid;
            o_tlast  <= h_tlast;
            o_tkeep  <= h_tkeep;
            o_tdata  <= h_tdata;
        end else if (o_tready) begin
            o_tvalid <= 1'b0;
            o_tlast  <= 1'b0;
        end
    end


endmodule

