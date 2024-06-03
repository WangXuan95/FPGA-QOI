
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


localparam [2:0] S_INIT   = 3'd0,
                 S_IDLE   = 3'd1,
                 S_WIDTH  = 3'd2,
                 S_HEIGHT = 3'd3,
                 S_2BYTE  = 3'd4,
                 S_WORK   = 3'd5,
                 S_RUN    = 3'd6;

reg  [ 2:0] state    = S_INIT;
reg         finished = 1'b0; // already meet i_tlast=1, current image input finished. but still need to decode the remain bytes
reg  [ 6:0] cnt      = 7'd0;
reg  [ 5:0] run;
reg  [31:0] width, height;

assign {o_width, o_height} = {width, height};

reg  [ 1:0] rem_cnt;         // remain byte count : 0~3
reg  [23:0] rem_bytes;       // remain bytes

reg         code_en = 1'b0;
reg  [31:0] code;

wire [55:0] m_bytes = (rem_cnt == 2'd0) ? {24'h0, i_tdata                 } :
                      (rem_cnt == 2'd1) ? {16'h0, i_tdata, rem_bytes[ 7:0]} :
                      (rem_cnt == 2'd2) ? { 8'h0, i_tdata, rem_bytes[15:0]} :
                                          {       i_tdata, rem_bytes      } ;

reg  [ 2:0] consume_cnt;   // not real register
always @(*) begin
    if      (m_bytes[7:6] == 2'b00) consume_cnt = 3'd1;  // QOI_OP_INDEX
    else if (m_bytes[7:6] == 2'b01) consume_cnt = 3'd1;  // QOI_OP_DIFF
    else if (m_bytes[7:6] == 2'b10) consume_cnt = 3'd2;  // QOI_OP_LUMA
    else if (m_bytes[5:0] <  6'h3E) consume_cnt = 3'd1;  // QOI_OP_RUN
    else                            consume_cnt = 3'd4;  // QOI_OP_RGB
end

wire [23:0] new_rem_bytes = (consume_cnt==3'd1) ? m_bytes[31: 8] :
                            (consume_cnt==3'd2) ? m_bytes[39:16] :
                                                  m_bytes[55:32] ;

wire is_run = (m_bytes[7:6] == 2'b11 && m_bytes[5:0] < 6'h3E);

wire enough = ({1'b0,rem_cnt} >= consume_cnt);  // current rem_bytes is enough to form a new pixel, needn't to input a next i_tdata

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        state     <= S_INIT;
        finished  <= 1'b0;
        cnt       <= 7'd0;
        width     <= 0;
        height    <= 0;
        run       <= 6'd0;
        rem_cnt   <= 2'd0;
        rem_bytes <= 24'h0;
        code_en   <= 1'b0;
        code      <= 0;
        
    end else begin
        if (~o_tvalid | o_tready)
            code_en <= 1'b0;
        
        case (state)
            S_INIT : begin    // use this state to initialize hash table
                if (cnt < 7'd72) begin
                    cnt <= cnt + 7'd1;
                end else begin
                    cnt <= 7'd0;
                    state <= S_IDLE;
                end
                code[5:0] <= cnt[5:0] + 6'd1;  // as the hash table address when initialize hash table
            end
            
            S_IDLE :
                if (i_tvalid && i_tdata==32'h66_69_6f_71)  // "qoif" in little endian
                    state <= i_tlast ? S_IDLE : S_WIDTH;
            
            S_WIDTH : begin
                if (i_tvalid)
                    state <= i_tlast ? S_IDLE : S_HEIGHT;
                width  <= {i_tdata[7:0], i_tdata[15:8], i_tdata[23:16], i_tdata[31:24]};
            end
            
            S_HEIGHT : begin
                if (i_tvalid)
                    state <= i_tlast ? S_IDLE : S_2BYTE;
                height <= {i_tdata[7:0], i_tdata[15:8], i_tdata[23:16], i_tdata[31:24]};
            end
            
            S_2BYTE : begin
                if (i_tvalid)
                    state <= i_tlast ? S_IDLE : S_WORK;
                rem_cnt   <= 2'd2;
                rem_bytes <= {8'h0, i_tdata[31:16]};
                finished  <= 1'b0;
            end
            
            S_WORK :
                if (enough) begin               // consume remain bytes rather than input i_tdata
                    // i_tready = 1'b0;
                    if  (~code_en | ~o_tvalid | o_tready) begin
                        if (is_run) begin
                            run <= m_bytes[5:0];
                            if (m_bytes[5:0]>6'd0) state <= S_RUN;
                        end
                        rem_cnt   <= rem_cnt - consume_cnt[1:0];
                        rem_bytes <= new_rem_bytes;
                        code_en   <= 1'b1;
                        code      <= m_bytes[31:0];
                    end
                end else if (~finished) begin   // consume input i_tdata
                    // i_tready = 1'b0;
                    if  (~code_en | ~o_tvalid | o_tready) begin
                        // i_tready = 1'b1;
                        if (i_tvalid) begin
                            finished <= i_tlast;
                            if (is_run) begin
                                run <= m_bytes[5:0];
                                if (m_bytes[5:0]>6'd0) state <= S_RUN;
                            end
                            rem_cnt   <= rem_cnt - consume_cnt[1:0];
                            rem_bytes <= new_rem_bytes;
                            code_en   <= 1'b1;
                            code      <= m_bytes[31:0];
                        end
                    end
                end else begin
                    // i_tready = 1'b0;
                    if (~code_en & ~o_tvalid)
                        state <= S_INIT;
                end
            
            default /*S_RUN*/  :
                if (~code_en | ~o_tvalid | o_tready) begin
                    code_en   <= 1'b1;
                    if (run > 6'd1) run <= run - 6'd1;
                    else            state <= S_WORK;
                end
        endcase
    end

assign i_tready = (state == S_IDLE  ) ? 1'b1 :
                  (state == S_WIDTH ) ? 1'b1 :
                  (state == S_HEIGHT) ? 1'b1 :
                  (state == S_2BYTE ) ? 1'b1 :
                  (state == S_WORK  ) ? (~enough & ~finished & (~code_en | ~o_tvalid | o_tready)) :
                                        1'b0;



reg  [23:0] HASH_TAB [63:0];

wire [ 7:0] dR = o_R + code[5:4] - 8'd2;
wire [ 7:0] dG = o_G + code[3:2] - 8'd2;
wire [ 7:0] dB = o_B + code[1:0] - 8'd2;

wire [ 7:0] xG = o_G + code[5:0]               - 8'd32;
wire [ 7:0] xR = o_R + code[5:0] + code[15:12] - 8'd40;
wire [ 7:0] xB = o_B + code[5:0] + code[11: 8] - 8'd40;

wire [ 7:0] R, G, B;

assign {R, G, B} = (code[7] == 1'b0) ? {dR, dG, dB}  :
                   (code[6] == 1'b0) ? {xR, xG, xB}  :
                   (code[5:0]<6'h3E) ? {o_R,o_G,o_B} :
                                       {code[15:8], code[23:16], code[31:24]} ;

wire [ 5:0] hash = 6'd53 +
                   R[5:0] + {R[4:0],1'b0} +                 // 3*R
                   G[5:0] + {G[3:0],2'b0} +                 // 5*R
                   B[5:0] + {B[4:0],1'b0} + {B[3:0],2'b0};  // 7*B


reg  [31:0] xpos, ypos;

always @ (posedge clk)
    if (state == S_INIT) begin
        HASH_TAB[code[5:0]] <= 24'h0;
        {o_R, o_G, o_B} <= 24'h0;
        xpos <= 1;
        ypos <= 1;
        
        o_tvalid <= 1'b0;
        o_tlast  <= 1'b0;
    end else if (~o_tvalid | o_tready) begin
        o_tvalid <= code_en && (ypos <= height);
        
        if (code_en) begin
            o_tlast <= (ypos == height) && (xpos == width);
            
            if (xpos < width) begin
                xpos <= xpos + 1;
            end else begin
                xpos <= 1;
                ypos <= (ypos<=height) ? (ypos+1) : ypos;
            end
            
            if (code[7:6] == 2'd0) begin
                {o_R, o_G, o_B} <= HASH_TAB[code[5:0]];
            end else begin
                {o_R, o_G, o_B} <= {R, G, B};
                HASH_TAB[hash]  <= {R, G, B};
            end
        end
    end

/////////////////////////////////////////////////////////
/*always @ (posedge clk)
    if (o_tready & o_tvalid) begin
        case (o_tdata[7:6])
            2'd0 : $display("HASH  %d"         , o_tdata[5:0] );
            2'd1 : $display("DIFF  (%d %d %d)" , o_tdata[5:4]   , o_tdata[3:2]  , o_tdata[1:0] );
            2'd2 : $display("LUMA  (%d %d %d)" , o_tdata[15:12] , o_tdata[11:8] , o_tdata[5:0] );
            2'd3 :
                if (o_tdata[5:0] < 6'h3E)
                   $display("RUN   %d"         , o_tdata[5:0]+1 );
                else
                   $display("RGB   %02x %02x %02x" , o_tdata[15:8] , o_tdata[23:16] , o_tdata[31:24] );
        endcase
    end*/

endmodule

