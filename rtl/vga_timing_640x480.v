module vga_timing_640x480 (
    input  wire       clk,
    input  wire       rst,
    output reg [9:0]  h_count,
    output reg [9:0]  v_count,
    output wire       hsync,
    output wire       vsync,
    output wire       active_video,
    output wire       frame_start
);
    // Standard 640x480 VGA horizontal timing at a 25 MHz pixel clock.
    localparam H_VISIBLE = 10'd640;
    localparam H_FRONT   = 10'd16;
    localparam H_SYNC    = 10'd96;
    localparam H_BACK    = 10'd48;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK; // 800

    // Standard 640x480 VGA vertical timing.
    localparam V_VISIBLE = 10'd480;
    localparam V_FRONT   = 10'd10;
    localparam V_SYNC    = 10'd2;
    localparam V_BACK    = 10'd33;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK; // 525

    // Pixel counters scan across one line, then advance to the next line.
    always @(posedge clk) begin
        if (rst) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 10'd0;
                end else begin
                    v_count <= v_count + 10'd1;
                end
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // VGA sync pulses are active low.
    assign hsync = ~((h_count >= (H_VISIBLE + H_FRONT)) &&
                     (h_count <  (H_VISIBLE + H_FRONT + H_SYNC)));

    assign vsync = ~((v_count >= (V_VISIBLE + V_FRONT)) &&
                     (v_count <  (V_VISIBLE + V_FRONT + V_SYNC)));

    // active_video is high only inside the visible 640x480 region.
    assign active_video = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign frame_start  = (h_count == 10'd0) && (v_count == 10'd0);

endmodule
