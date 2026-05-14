`timescale 1ns/1ps

module tb_vga_timing;
    reg clk = 1'b0;
    reg rst = 1'b1;

    wire [9:0] h_count;
    wire [9:0] v_count;
    wire       hsync;
    wire       vsync;
    wire       active_video;
    wire       frame_start;

    vga_timing_640x480 dut (
        .clk(clk),
        .rst(rst),
        .h_count(h_count),
        .v_count(v_count),
        .hsync(hsync),
        .vsync(vsync),
        .active_video(active_video),
        .frame_start(frame_start)
    );

    always #20 clk = ~clk; // 25 MHz

    integer line_count;
    reg started;

    initial begin
        line_count  = 0;
        started     = 1'b0;

        repeat (5) @(posedge clk);
        rst = 1'b0;

        while (1) begin
            @(posedge clk);

            if (h_count == 10'd799) begin
                line_count = line_count + 1;
            end

            if (frame_start) begin
                if (!started) begin
                    started = 1'b1;
                    line_count = 0;
                end else begin
                    if (line_count == 525) begin
                        $display("PASS: tb_vga_timing");
                    end else begin
                        $display("ERROR: Expected 525 lines per frame, got %0d", line_count);
                    end
                    $finish;
                end
            end
        end
    end
endmodule
