module top_ov7670_vga (
    input  wire        CLK100MHZ,
    input  wire        btnC,
    input  wire [15:0] sw,
    output wire [15:0] led,

    input  wire [7:0]  cam_data,
    input  wire        cam_pclk,
    input  wire        cam_href,
    input  wire        cam_vsync,
    output wire        cam_xclk,
    output wire        cam_pwdn,
    output wire        cam_reset,
    output wire        cam_sioc,
    inout  wire        cam_siod,

    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync
);
    localparam FULL_FRAME_WIDTH  = 640;
    localparam FULL_FRAME_HEIGHT = 480;
    localparam FULL_ADDR_WIDTH   = 19;
    localparam BASE_FRAME_WIDTH  = 320;
    localparam BASE_FRAME_HEIGHT = 240;
    localparam BASE_ADDR_WIDTH   = 17;
    localparam [9:0]  H_VISIBLE          = 10'd640;
    localparam [10:0] H_TOTAL            = 11'd800;
    localparam [9:0]  V_VISIBLE          = 10'd480;
    localparam [10:0] V_TOTAL            = 11'd525;
    localparam [10:0] FRAME_READ_LATENCY = 11'd3;
    localparam [10:0] DEBUG_READ_LATENCY = 11'd2;

    wire clk25;
    wire clk25_locked;
    wire rst = btnC || !clk25_locked;

    // Use a clocking resource instead of a fabric flip-flop divider. A divided
    // fabric clock can have enough skew/uncertainty to show up as edge artifacts
    // when the VGA read path and camera write path interact.
    clock_gen_25mhz u_clock_gen (
        .clk100(CLK100MHZ),
        .rst   (btnC),
        .clk25 (clk25),
        .locked(clk25_locked)
    );

    assign cam_xclk  = clk25;
    assign cam_pwdn  = 1'b0;
    assign cam_reset = 1'b1;

    // SCCB (I2C-like) camera configuration
    wire sccb_sda_low;
    wire sccb_done;
    wire sccb_busy;
    wire sccb_ack_error;

    assign cam_siod = sccb_sda_low ? 1'b0 : 1'bz;

    ov7670_sccb_init u_sccb_init (
        .clk         (CLK100MHZ),
        .rst         (rst),
        .sioc        (cam_sioc),
        .siod_oe_low (sccb_sda_low),
        .siod_in     (cam_siod),
        .busy        (sccb_busy),
        .done        (sccb_done),
        .ack_error   (sccb_ack_error)
    );

    // Camera capture path:
    // - full mode stores VGA 3-bit grayscale for the extra-credit path
    // - base mode stores downsampled QVGA RGB444 for better color
    wire                       full_fb_wr_en;
    wire [FULL_ADDR_WIDTH-1:0] full_fb_wr_addr;
    wire [2:0]                 full_fb_wr_data;
    wire                       base_fb_wr_en;
    wire [BASE_ADDR_WIDTH-1:0] base_fb_wr_addr;
    wire [11:0]                base_fb_wr_data;
    wire                       capture_frame_done_toggle;

    ov7670_capture #(
        .FULL_FRAME_WIDTH  (FULL_FRAME_WIDTH),
        .FULL_FRAME_HEIGHT (FULL_FRAME_HEIGHT),
        .FULL_ADDR_WIDTH   (FULL_ADDR_WIDTH),
        .BASE_FRAME_WIDTH  (BASE_FRAME_WIDTH),
        .BASE_FRAME_HEIGHT (BASE_FRAME_HEIGHT),
        .BASE_ADDR_WIDTH   (BASE_ADDR_WIDTH)
    ) u_capture (
        .pclk        (cam_pclk),
        .rst         (rst),
        .cam_data    (cam_data),
        .href        (cam_href),
        .vsync       (cam_vsync),
        .full_wr_en  (full_fb_wr_en),
        .full_wr_addr(full_fb_wr_addr),
        .full_wr_data(full_fb_wr_data),
        .base_wr_en  (base_fb_wr_en),
        .base_wr_addr(base_fb_wr_addr),
        .base_wr_data(base_fb_wr_data),
        .frame_done_toggle(capture_frame_done_toggle)
    );

    // VGA timing
    wire [9:0] h_count;
    wire [9:0] v_count;
    wire       active_video;

    vga_timing_640x480 u_vga_timing (
        .clk         (clk25),
        .rst         (rst),
        .h_count     (h_count),
        .v_count     (v_count),
        .hsync       (vga_hsync),
        .vsync       (vga_vsync),
        .active_video(active_video),
        .frame_start ()
    );

    // Read side from the shared dual-mode frame buffer.
    reg  [FULL_ADDR_WIDTH-1:0] full_fb_rd_addr;
    reg  [BASE_ADDR_WIDTH-1:0] base_fb_rd_addr;
    wire [11:0]                fb_rd_rgb444;

    reg  [1:0]            mode_d;
    reg                   debug_mode_d;
    reg  [11:0]           debug_pixel;
    reg                   capture_frame_toggle_meta;
    reg                   capture_frame_toggle_sync;
    reg                   capture_frame_toggle_seen;
    reg                   resolution_mode_d;
    reg [1:0]             camera_ready_count;
    reg                   camera_frame_ready;

    // The VGA output register sees framebuffer data three clocks after the
    // address is issued, so read ahead to keep the last visible columns aligned.
    wire [10:0] frame_h_sum = {1'b0, h_count} + FRAME_READ_LATENCY[10:0];
    wire        frame_h_wrap = (frame_h_sum >= H_TOTAL[10:0]);
    wire [10:0] frame_h_mod = frame_h_wrap ? (frame_h_sum - H_TOTAL[10:0]) : frame_h_sum;
    wire [9:0]  frame_v_next = (v_count == (V_TOTAL - 1)) ? 10'd0 : (v_count + 10'd1);
    wire [9:0]  frame_h = frame_h_mod[9:0];
    wire [9:0]  frame_v = frame_h_wrap ? frame_v_next : v_count;
    wire        frame_prefetch_active = (frame_h < H_VISIBLE[9:0]) && (frame_v < V_VISIBLE[9:0]);

    // The generated debug pattern has one less register stage than the BRAM path.
    wire [10:0] debug_h_sum = {1'b0, h_count} + DEBUG_READ_LATENCY[10:0];
    wire        debug_h_wrap = (debug_h_sum >= H_TOTAL[10:0]);
    wire [10:0] debug_h_mod = debug_h_wrap ? (debug_h_sum - H_TOTAL[10:0]) : debug_h_sum;
    wire [9:0]  debug_v_next = (v_count == (V_TOTAL - 1)) ? 10'd0 : (v_count + 10'd1);
    wire [9:0]  debug_h = debug_h_mod[9:0];
    wire [9:0]  debug_v = debug_h_wrap ? debug_v_next : v_count;
    wire        debug_prefetch_active = (debug_h < H_VISIBLE[9:0]) && (debug_v < V_VISIBLE[9:0]);

    wire [FULL_ADDR_WIDTH-1:0] full_row_512 = {1'b0, frame_v[8:0], 9'b0};
    wire [FULL_ADDR_WIDTH-1:0] full_row_128 = {3'b000, frame_v[8:0], 7'b0};
    wire [FULL_ADDR_WIDTH-1:0] full_col     = {9'b000000000, frame_h};
    wire [FULL_ADDR_WIDTH-1:0] full_fb_addr = full_row_512 + full_row_128 + full_col;

    wire [8:0] src_x = frame_h[9:1];
    wire [7:0] src_y = frame_v[8:1];
    wire [BASE_ADDR_WIDTH-1:0] base_row_256 = {1'b0, src_y, 8'b0};
    wire [BASE_ADDR_WIDTH-1:0] base_row_064 = {3'b000, src_y, 6'b0};
    wire [BASE_ADDR_WIDTH-1:0] base_col     = {8'b00000000, src_x};
    wire [BASE_ADDR_WIDTH-1:0] base_fb_addr = base_row_256 + base_row_064 + base_col;

    wire [3:0] debug_stripe_phase = debug_h % 10'd12;
    wire [1:0] debug_stripe_sel =
        (debug_stripe_phase < 4'd3) ? 2'd0 :
        (debug_stripe_phase < 4'd6) ? 2'd1 :
        (debug_stripe_phase < 4'd9) ? 2'd2 : 2'd3;
    wire [11:0] debug_stripe_color =
        (debug_stripe_sel == 2'd0) ? 12'hF00 :
        (debug_stripe_sel == 2'd1) ? 12'h0F0 :
        (debug_stripe_sel == 2'd2) ? 12'h00F : 12'hFF0;

    always @(posedge clk25) begin
        if (rst) begin
            full_fb_rd_addr <= {FULL_ADDR_WIDTH{1'b0}};
            base_fb_rd_addr <= {BASE_ADDR_WIDTH{1'b0}};
            mode_d         <= 2'b00;
            debug_mode_d   <= 1'b0;
            debug_pixel    <= 12'h000;
            capture_frame_toggle_meta <= 1'b0;
            capture_frame_toggle_sync <= 1'b0;
            capture_frame_toggle_seen <= 1'b0;
            resolution_mode_d         <= 1'b0;
            camera_ready_count        <= 2'd0;
            camera_frame_ready        <= 1'b0;
        end else begin
            capture_frame_toggle_meta <= capture_frame_done_toggle;
            capture_frame_toggle_sync <= capture_frame_toggle_meta;

            if (resolution_mode_d != sw[14]) begin
                resolution_mode_d         <= sw[14];
                capture_frame_toggle_seen <= capture_frame_toggle_sync;
                camera_ready_count        <= 2'd0;
                camera_frame_ready        <= 1'b0;
            end else if (capture_frame_toggle_sync != capture_frame_toggle_seen) begin
                capture_frame_toggle_seen <= capture_frame_toggle_sync;
                if (!camera_frame_ready) begin
                    if (camera_ready_count == 2'd1) begin
                        camera_frame_ready <= 1'b1;
                    end else begin
                        camera_ready_count <= camera_ready_count + 2'd1;
                    end
                end
            end

            if (frame_prefetch_active) begin
                full_fb_rd_addr <= full_fb_addr;
                base_fb_rd_addr <= base_fb_addr;
            end else begin
                full_fb_rd_addr <= {FULL_ADDR_WIDTH{1'b0}};
                base_fb_rd_addr <= {BASE_ADDR_WIDTH{1'b0}};
            end

            if (debug_prefetch_active) begin
                debug_pixel <= debug_stripe_color;
            end else begin
                debug_pixel <= 12'h000;
            end

            mode_d         <= sw[1:0];
            debug_mode_d   <= sw[15];
        end
    end

    framebuffer_dualmode #(
        .FULL_ADDR_WIDTH(FULL_ADDR_WIDTH),
        .BASE_ADDR_WIDTH(BASE_ADDR_WIDTH)
    ) u_framebuffer (
        .wr_clk       (cam_pclk),
        .write_mode   (sw[14]),
        .full_wr_en   (full_fb_wr_en),
        .full_wr_addr (full_fb_wr_addr),
        .full_wr_data (full_fb_wr_data),
        .base_wr_en   (base_fb_wr_en),
        .base_wr_addr (base_fb_wr_addr),
        .base_wr_data (base_fb_wr_data),
        .rd_clk       (clk25),
        .read_mode    (sw[14]),
        .full_rd_addr (full_fb_rd_addr),
        .base_rd_addr (base_fb_rd_addr),
        .rd_rgb444    (fb_rd_rgb444)
    );

    wire [11:0] filtered_pixel;
    pixel_filters u_filters (
        .pixel_in (fb_rd_rgb444),
        .mode     (mode_d),
        .pixel_out(filtered_pixel)
    );

    reg [11:0] video_pixel;
    always @(posedge clk25) begin
        if (rst) begin
            video_pixel <= 12'h000;
        end else begin
            if (debug_mode_d) begin
                video_pixel <= debug_pixel;
            end else if (!camera_frame_ready) begin
                video_pixel <= 12'h000;
            end else begin
                video_pixel <= filtered_pixel;
            end
        end
    end

    wire output_active = active_video;
    assign vga_r = output_active ? video_pixel[11:8] : 4'h0;
    assign vga_g = output_active ? video_pixel[7:4]  : 4'h0;
    assign vga_b = output_active ? video_pixel[3:0]  : 4'h0;

    assign led[0]  = sccb_done;
    assign led[1]  = sccb_busy;
    assign led[2]  = cam_vsync;
    assign led[3]  = cam_href;
    assign led[4]  = cam_pclk;
    assign led[5]  = sccb_ack_error;
    assign led[6]  = sw[14]; // resolution mode: 0=base RGB444, 1=full grayscale
    assign led[7]  = sw[15]; // debug pattern enable
    assign led[8]  = camera_frame_ready;
    assign led[15:9] = 7'd0;

endmodule

module clock_gen_25mhz (
    input  wire clk100,
    input  wire rst,
    output wire clk25,
    output wire locked
);
`ifdef __ICARUS__
    reg [1:0] div;
    reg       locked_reg;

    always @(posedge clk100) begin
        if (rst) begin
            div        <= 2'b00;
            locked_reg <= 1'b0;
        end else begin
            div        <= div + 2'b01;
            locked_reg <= 1'b1;
        end
    end

    assign clk25  = div[1];
    assign locked = locked_reg;
`else
    wire clkfb;
    wire clkfb_buf;
    wire clk25_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(10.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE_F(40.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKFBOUT (clkfb),
        .CLKFBOUTB(),
        .CLKOUT0  (clk25_unbuf),
        .CLKOUT0B (),
        .CLKOUT1  (),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .LOCKED   (locked),
        .CLKFBIN  (clkfb_buf),
        .CLKIN1   (clk100),
        .PWRDWN   (1'b0),
        .RST      (rst)
    );

    BUFG u_clkfb_buf (
        .I(clkfb),
        .O(clkfb_buf)
    );

    BUFG u_clk25_buf (
        .I(clk25_unbuf),
        .O(clk25)
    );
`endif
endmodule
