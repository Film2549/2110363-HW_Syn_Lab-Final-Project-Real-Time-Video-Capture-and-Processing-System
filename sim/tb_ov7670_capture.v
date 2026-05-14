`timescale 1ns/1ps

module tb_ov7670_capture;
    localparam FULL_FRAME_WIDTH  = 4;
    localparam FULL_FRAME_HEIGHT = 2;
    localparam FULL_ADDR_WIDTH   = 4;
    localparam BASE_FRAME_WIDTH  = 2;
    localparam BASE_FRAME_HEIGHT = 1;
    localparam BASE_ADDR_WIDTH   = 2;

    reg  pclk;
    reg  rst;
    reg  [7:0] cam_data;
    reg  href;
    reg  vsync;

    wire                       full_wr_en;
    wire [FULL_ADDR_WIDTH-1:0] full_wr_addr;
    wire [2:0]                 full_wr_data;
    wire                       base_wr_en;
    wire [BASE_ADDR_WIDTH-1:0] base_wr_addr;
    wire [11:0]                base_wr_data;
    wire                       frame_done_toggle;

    ov7670_capture #(
        .FULL_FRAME_WIDTH (FULL_FRAME_WIDTH),
        .FULL_FRAME_HEIGHT(FULL_FRAME_HEIGHT),
        .FULL_ADDR_WIDTH  (FULL_ADDR_WIDTH),
        .BASE_FRAME_WIDTH (BASE_FRAME_WIDTH),
        .BASE_FRAME_HEIGHT(BASE_FRAME_HEIGHT),
        .BASE_ADDR_WIDTH  (BASE_ADDR_WIDTH)
    ) dut (
        .pclk        (pclk),
        .rst         (rst),
        .cam_data    (cam_data),
        .href        (href),
        .vsync       (vsync),
        .full_wr_en  (full_wr_en),
        .full_wr_addr(full_wr_addr),
        .full_wr_data(full_wr_data),
        .base_wr_en  (base_wr_en),
        .base_wr_addr(base_wr_addr),
        .base_wr_data(base_wr_data),
        .frame_done_toggle(frame_done_toggle)
    );

    always #5 pclk = ~pclk;

    reg [15:0] line0 [0:3];
    reg [15:0] line1 [0:3];

    integer full_write_count;
    integer base_write_count;
    reg [2:0] expected_full_data [0:7];
    reg [11:0] expected_base_data [0:1];

    task send_pixel;
        input [15:0] pix;
        begin
            cam_data = pix[15:8];
            @(negedge pclk);
            cam_data = pix[7:0];
            @(negedge pclk);
        end
    endtask

    task send_line;
        input [15:0] p0;
        input [15:0] p1;
        input [15:0] p2;
        input [15:0] p3;
        begin
            @(negedge pclk);
            href = 1'b1;
            send_pixel(p0);
            send_pixel(p1);
            send_pixel(p2);
            send_pixel(p3);
            href = 1'b0;
            @(posedge pclk);
        end
    endtask

    initial begin
        pclk = 1'b0;
        rst = 1'b1;
        cam_data = 8'h00;
        href = 1'b0;
        vsync = 1'b0;
        full_write_count = 0;
        base_write_count = 0;

        line0[0] = 16'hF800; // red
        line0[1] = 16'h07E0; // green
        line0[2] = 16'h001F; // blue
        line0[3] = 16'hFFFF; // white

        line1[0] = 16'h0000; // black
        line1[1] = 16'hF81F; // magenta
        line1[2] = 16'h07FF; // cyan
        line1[3] = 16'hFFE0; // yellow

        expected_full_data[0] = 3'd2; // red grayscale
        expected_full_data[1] = 3'd4; // green grayscale
        expected_full_data[2] = 3'd0; // blue grayscale
        expected_full_data[3] = 3'd7; // white grayscale
        expected_full_data[4] = 3'd0; // black
        expected_full_data[5] = 3'd3; // magenta grayscale
        expected_full_data[6] = 3'd5; // cyan grayscale
        expected_full_data[7] = 3'd6; // yellow grayscale

        expected_base_data[0] = 12'hF00; // line0 x0 red in RGB444
        expected_base_data[1] = 12'h00F; // line0 x2 blue in RGB444

        repeat (4) @(posedge pclk);
        rst = 1'b0;

        // Frame start pulse
        vsync = 1'b1;
        @(posedge pclk);
        vsync = 1'b0;

        send_line(line0[0], line0[1], line0[2], line0[3]);
        send_line(line1[0], line1[1], line1[2], line1[3]);

        repeat (4) @(posedge pclk);

        if (full_write_count != 8) begin
            $display("ERROR: expected 8 full writes, got %0d", full_write_count);
            $finish;
        end

        if (base_write_count != 2) begin
            $display("ERROR: expected 2 base writes, got %0d", base_write_count);
            $finish;
        end

        $display("PASS: tb_ov7670_capture");
        $finish;
    end

    always @(negedge pclk) begin
        if (full_wr_en) begin
            if (full_wr_addr !== full_write_count[FULL_ADDR_WIDTH-1:0]) begin
                $display("ERROR: full_wr_addr=%0d expected=%0d", full_wr_addr, full_write_count);
                $finish;
            end
            if (full_wr_data !== expected_full_data[full_write_count]) begin
                $display(
                    "ERROR: full_wr_data=%b expected=%b at write %0d",
                    full_wr_data,
                    expected_full_data[full_write_count],
                    full_write_count
                );
                $finish;
            end
            full_write_count <= full_write_count + 1;
        end

        if (base_wr_en) begin
            if (base_wr_addr !== base_write_count[BASE_ADDR_WIDTH-1:0]) begin
                $display("ERROR: base_wr_addr=%0d expected=%0d", base_wr_addr, base_write_count);
                $finish;
            end
            if (base_wr_data !== expected_base_data[base_write_count]) begin
                $display(
                    "ERROR: base_wr_data=%h expected=%h at write %0d",
                    base_wr_data,
                    expected_base_data[base_write_count],
                    base_write_count
                );
                $finish;
            end
            base_write_count <= base_write_count + 1;
        end
    end
endmodule
