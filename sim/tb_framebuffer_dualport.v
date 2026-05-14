`timescale 1ns/1ps

module tb_framebuffer_dualport;
    localparam FULL_ADDR_WIDTH = 19;
    localparam BASE_ADDR_WIDTH = 17;

    reg                        wr_clk;
    reg                        write_mode;
    reg                        full_wr_en;
    reg  [FULL_ADDR_WIDTH-1:0] full_wr_addr;
    reg  [2:0]                 full_wr_data;
    reg                        base_wr_en;
    reg  [BASE_ADDR_WIDTH-1:0] base_wr_addr;
    reg  [11:0]                base_wr_data;

    reg                        rd_clk;
    reg                        read_mode;
    reg  [FULL_ADDR_WIDTH-1:0] full_rd_addr;
    reg  [BASE_ADDR_WIDTH-1:0] base_rd_addr;
    wire [11:0]                rd_rgb444;

    framebuffer_dualmode #(
        .FULL_ADDR_WIDTH(FULL_ADDR_WIDTH),
        .BASE_ADDR_WIDTH(BASE_ADDR_WIDTH)
    ) dut (
        .wr_clk       (wr_clk),
        .write_mode   (write_mode),
        .full_wr_en   (full_wr_en),
        .full_wr_addr (full_wr_addr),
        .full_wr_data (full_wr_data),
        .base_wr_en   (base_wr_en),
        .base_wr_addr (base_wr_addr),
        .base_wr_data (base_wr_data),
        .rd_clk       (rd_clk),
        .read_mode    (read_mode),
        .full_rd_addr (full_rd_addr),
        .base_rd_addr (base_rd_addr),
        .rd_rgb444    (rd_rgb444)
    );

    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    function [11:0] gray3_to_rgb444;
        input [2:0] gray3;
        reg   [3:0] gray4;
        begin
            gray4 = {gray3, gray3[2]};
            gray3_to_rgb444 = {gray4, gray4, gray4};
        end
    endfunction

    task write_base;
        input [BASE_ADDR_WIDTH-1:0] addr;
        input [11:0] data;
        begin
            @(negedge wr_clk);
            write_mode   = 1'b0;
            base_wr_addr = addr;
            base_wr_data = data;
            base_wr_en   = 1'b1;
            full_wr_en   = 1'b0;
            @(negedge wr_clk);
            base_wr_en   = 1'b0;
        end
    endtask

    task write_full;
        input [FULL_ADDR_WIDTH-1:0] addr;
        input [2:0] data;
        begin
            @(negedge wr_clk);
            write_mode   = 1'b1;
            full_wr_addr = addr;
            full_wr_data = data;
            full_wr_en   = 1'b1;
            base_wr_en   = 1'b0;
            @(negedge wr_clk);
            full_wr_en   = 1'b0;
        end
    endtask

    task check_base;
        input [BASE_ADDR_WIDTH-1:0] addr;
        input [11:0] expected;
        begin
            @(negedge rd_clk);
            read_mode    = 1'b0;
            base_rd_addr = addr;
            @(posedge rd_clk);
            #1;
            if (rd_rgb444 !== expected) begin
                $display(
                    "ERROR: base read addr=%0d got=%h expected=%h",
                    addr,
                    rd_rgb444,
                    expected
                );
                $finish;
            end
        end
    endtask

    task check_full;
        input [FULL_ADDR_WIDTH-1:0] addr;
        input [2:0] expected_gray;
        reg [11:0] expected_rgb;
        begin
            expected_rgb = gray3_to_rgb444(expected_gray);
            @(negedge rd_clk);
            read_mode    = 1'b1;
            full_rd_addr = addr;
            @(posedge rd_clk);
            #1;
            if (rd_rgb444 !== expected_rgb) begin
                $display(
                    "ERROR: full read addr=%0d got=%h expected=%h",
                    addr,
                    rd_rgb444,
                    expected_rgb
                );
                $finish;
            end
        end
    endtask

    initial begin
        wr_clk       = 1'b0;
        rd_clk       = 1'b0;
        write_mode   = 1'b0;
        read_mode    = 1'b0;
        full_wr_en   = 1'b0;
        full_wr_addr = {FULL_ADDR_WIDTH{1'b0}};
        full_wr_data = 3'd0;
        base_wr_en   = 1'b0;
        base_wr_addr = {BASE_ADDR_WIDTH{1'b0}};
        base_wr_data = 12'h000;
        full_rd_addr = {FULL_ADDR_WIDTH{1'b0}};
        base_rd_addr = {BASE_ADDR_WIDTH{1'b0}};

        repeat (4) @(posedge wr_clk);

        // Base mode stores one RGB444 pixel across the four 3-bit RAM banks.
        write_base(17'd0,  12'hABC);
        write_base(17'd1,  12'h123);
        write_base(17'd10, 12'hF0A);

        check_base(17'd0,  12'hABC);
        check_base(17'd1,  12'h123);
        check_base(17'd10, 12'hF0A);

        // Full mode packs four consecutive 3-bit grayscale pixels into the
        // same four physical banks at one shared bank address.
        write_full(19'd0, 3'd0);
        write_full(19'd1, 3'd1);
        write_full(19'd2, 3'd2);
        write_full(19'd3, 3'd3);
        write_full(19'd4, 3'd4);
        write_full(19'd5, 3'd5);
        write_full(19'd6, 3'd6);
        write_full(19'd7, 3'd7);

        check_full(19'd0, 3'd0);
        check_full(19'd1, 3'd1);
        check_full(19'd2, 3'd2);
        check_full(19'd3, 3'd3);
        check_full(19'd4, 3'd4);
        check_full(19'd5, 3'd5);
        check_full(19'd6, 3'd6);
        check_full(19'd7, 3'd7);

        $display("PASS: tb_framebuffer_dualport");
        $finish;
    end
endmodule
