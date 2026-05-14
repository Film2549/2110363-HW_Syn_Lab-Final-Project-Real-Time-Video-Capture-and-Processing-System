module framebuffer_bank_3bit #(
    parameter ADDR_WIDTH = 17,
    parameter DEPTH      = 76800
) (
    input  wire                  wr_clk,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [2:0]            wr_data,

    input  wire                  rd_clk,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [2:0]            rd_data
);
    // One 3-bit dual-clock RAM bank. The camera side writes with wr_clk,
    // and the VGA side reads with rd_clk.
    (* ram_style = "block" *) reg [2:0] mem [0:DEPTH-1];

    always @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end
endmodule

module framebuffer_dualmode #(
    parameter FULL_ADDR_WIDTH = 19,
    parameter BASE_ADDR_WIDTH = 17
) (
    input  wire                       wr_clk,
    input  wire                       write_mode, // 0=base RGB444, 1=full grayscale
    input  wire                       full_wr_en,
    input  wire [FULL_ADDR_WIDTH-1:0] full_wr_addr,
    input  wire [2:0]                 full_wr_data,
    input  wire                       base_wr_en,
    input  wire [BASE_ADDR_WIDTH-1:0] base_wr_addr,
    input  wire [11:0]                base_wr_data,

    input  wire                       rd_clk,
    input  wire                       read_mode,  // 0=base RGB444, 1=full grayscale
    input  wire [FULL_ADDR_WIDTH-1:0] full_rd_addr,
    input  wire [BASE_ADDR_WIDTH-1:0] base_rd_addr,
    output wire [11:0]                rd_rgb444
);
    localparam BANK_DEPTH = 76800; // 320 * 240

    // In full-resolution mode, four consecutive grayscale pixels share the
    // same bank address and are selected by the lower two address bits.
    wire [BASE_ADDR_WIDTH-1:0] full_wr_bank_addr = full_wr_addr[FULL_ADDR_WIDTH-1:2];
    wire [BASE_ADDR_WIDTH-1:0] full_rd_bank_addr = full_rd_addr[FULL_ADDR_WIDTH-1:2];

    wire full_bank0_sel = (full_wr_addr[1:0] == 2'd0);
    wire full_bank1_sel = (full_wr_addr[1:0] == 2'd1);
    wire full_bank2_sel = (full_wr_addr[1:0] == 2'd2);
    wire full_bank3_sel = (full_wr_addr[1:0] == 2'd3);

    // Base mode writes all four banks at the same address to form RGB444.
    // Full mode writes only one selected bank for each grayscale pixel.
    wire bank0_wr_en = write_mode ? (full_wr_en && full_bank0_sel) : base_wr_en;
    wire bank1_wr_en = write_mode ? (full_wr_en && full_bank1_sel) : base_wr_en;
    wire bank2_wr_en = write_mode ? (full_wr_en && full_bank2_sel) : base_wr_en;
    wire bank3_wr_en = write_mode ? (full_wr_en && full_bank3_sel) : base_wr_en;

    // The same physical bank address lines are reused for both formats.
    wire [BASE_ADDR_WIDTH-1:0] bank_wr_addr = write_mode ? full_wr_bank_addr : base_wr_addr;
    wire [BASE_ADDR_WIDTH-1:0] bank_rd_addr = read_mode  ? full_rd_bank_addr : base_rd_addr;

    // Data packing differs by mode:
    // - base mode stores one RGB444 pixel across four banks
    // - full mode stores one 3-bit grayscale value in the selected bank
    wire [2:0] bank0_wr_data = write_mode ? full_wr_data : base_wr_data[11:9];
    wire [2:0] bank1_wr_data = write_mode ? full_wr_data : base_wr_data[8:6];
    wire [2:0] bank2_wr_data = write_mode ? full_wr_data : base_wr_data[5:3];
    wire [2:0] bank3_wr_data = write_mode ? full_wr_data : base_wr_data[2:0];

    wire [2:0] rd0;
    wire [2:0] rd1;
    wire [2:0] rd2;
    wire [2:0] rd3;

    // Four small 3-bit banks provide the same total storage for both modes:
    // 320x240x12 in base mode or 640x480x3 in full mode.
    framebuffer_bank_3bit #(
        .ADDR_WIDTH(BASE_ADDR_WIDTH),
        .DEPTH     (BANK_DEPTH)
    ) u_bank0 (
        .wr_clk (wr_clk),
        .wr_en  (bank0_wr_en),
        .wr_addr(bank_wr_addr),
        .wr_data(bank0_wr_data),
        .rd_clk (rd_clk),
        .rd_addr(bank_rd_addr),
        .rd_data(rd0)
    );

    framebuffer_bank_3bit #(
        .ADDR_WIDTH(BASE_ADDR_WIDTH),
        .DEPTH     (BANK_DEPTH)
    ) u_bank1 (
        .wr_clk (wr_clk),
        .wr_en  (bank1_wr_en),
        .wr_addr(bank_wr_addr),
        .wr_data(bank1_wr_data),
        .rd_clk (rd_clk),
        .rd_addr(bank_rd_addr),
        .rd_data(rd1)
    );

    framebuffer_bank_3bit #(
        .ADDR_WIDTH(BASE_ADDR_WIDTH),
        .DEPTH     (BANK_DEPTH)
    ) u_bank2 (
        .wr_clk (wr_clk),
        .wr_en  (bank2_wr_en),
        .wr_addr(bank_wr_addr),
        .wr_data(bank2_wr_data),
        .rd_clk (rd_clk),
        .rd_addr(bank_rd_addr),
        .rd_data(rd2)
    );

    framebuffer_bank_3bit #(
        .ADDR_WIDTH(BASE_ADDR_WIDTH),
        .DEPTH     (BANK_DEPTH)
    ) u_bank3 (
        .wr_clk (wr_clk),
        .wr_en  (bank3_wr_en),
        .wr_addr(bank_wr_addr),
        .wr_data(bank3_wr_data),
        .rd_clk (rd_clk),
        .rd_addr(bank_rd_addr),
        .rd_data(rd3)
    );

    reg       read_mode_d;
    reg [1:0] full_rd_sel_d;

    // Delay the mode and pixel selector to match the synchronous BRAM read data.
    always @(posedge rd_clk) begin
        read_mode_d   <= read_mode;
        full_rd_sel_d <= full_rd_addr[1:0];
    end

    // Full mode reconstructs RGB444 by expanding the selected 3-bit grayscale value.
    wire [2:0] full_gray =
        (full_rd_sel_d == 2'd0) ? rd0 :
        (full_rd_sel_d == 2'd1) ? rd1 :
        (full_rd_sel_d == 2'd2) ? rd2 : rd3;

    wire [3:0] full_gray4   = {full_gray, full_gray[2]};
    wire [11:0] full_rgb444 = {full_gray4, full_gray4, full_gray4};

    // Base mode directly combines the four banks into one RGB444 pixel.
    wire [11:0] base_rgb444 = {rd0, rd1, rd2, rd3};

    assign rd_rgb444 = read_mode_d ? full_rgb444 : base_rgb444;

endmodule
