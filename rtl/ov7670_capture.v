module ov7670_capture #(
    parameter FULL_FRAME_WIDTH  = 640,
    parameter FULL_FRAME_HEIGHT = 480,
    parameter FULL_ADDR_WIDTH   = 19,
    parameter BASE_FRAME_WIDTH  = 320,
    parameter BASE_FRAME_HEIGHT = 240,
    parameter BASE_ADDR_WIDTH   = 17
) (
    input  wire                      pclk,
    input  wire                      rst,
    input  wire [7:0]                cam_data,
    input  wire                      href,
    input  wire                      vsync,

    output reg                       full_wr_en,
    output reg [FULL_ADDR_WIDTH-1:0] full_wr_addr,
    output reg [2:0]                 full_wr_data,

    output reg                       base_wr_en,
    output reg [BASE_ADDR_WIDTH-1:0] base_wr_addr,
    output reg [11:0]                base_wr_data,

    output reg                       frame_done_toggle
);
    // Previous sync values are kept so the capture logic can detect line and
    // frame edges from the camera timing signals.
    reg                       href_d;
    reg                       vsync_d;

    // The OV7670 sends one RGB565 pixel as two 8-bit transfers. byte_phase
    // marks whether the next byte is the first or second byte of the pixel.
    reg                       byte_phase;
    reg [7:0]                 pixel_hi;

    // Pixel position and row base addresses for the two framebuffer formats.
    reg [9:0]                 x_count;
    reg [9:0]                 y_count;
    reg [FULL_ADDR_WIDTH-1:0] full_row_addr;
    reg [BASE_ADDR_WIDTH-1:0] base_row_addr;
    reg                       frame_has_pixel;

    // Edge detection for camera line/frame timing.
    wire href_fall  = href_d && !href;
    wire vsync_rise = !vsync_d && vsync;

    // Rebuild RGB565 components from the saved first byte and current second byte.
    wire [4:0] r5 = {pixel_hi[7:3]};
    wire [5:0] g6 = {pixel_hi[2:0], cam_data[7:5]};
    wire [4:0] b5 = {cam_data[4:0]};

    // Compact brightness estimate used for the full-resolution grayscale mode.
    // The near-black/near-white clamps help preserve contrast after reducing to 3 bits.
    wire [6:0] brightness = {2'b00, r5} + {2'b00, g6[5:1]} + {2'b00, b5};
    wire       near_black = (brightness < 7'd18);
    wire       near_white = (brightness > 7'd75);

    // Base color mode stores a reduced RGB444 pixel.
    wire [3:0] base_r4 = r5[4:1];
    wire [3:0] base_g4 = g6[5:2];
    wire [3:0] base_b4 = b5[4:1];

    // Weighted grayscale approximation: 5R + 9G + 2B.
    wire [7:0] gray_acc  = (base_r4 << 2) + base_r4 +
                           (base_g4 << 3) + base_g4 +
                           (base_b4 << 1); // 5R + 9G + 2B, max 240
    wire [2:0] full_gray = near_black ? 3'd0 :
                           (near_white ? 3'd7 : gray_acc[7:5]);

    // Full mode keeps every 640x480 pixel. Base mode stores every other pixel
    // and every other line to form a 320x240 color image.
    wire capture_full = (x_count < FULL_FRAME_WIDTH) &&
                        (y_count < FULL_FRAME_HEIGHT);
    wire capture_base = capture_full && !x_count[0] && !y_count[0] &&
                        (x_count[9:1] < BASE_FRAME_WIDTH) &&
                        (y_count[9:1] < BASE_FRAME_HEIGHT);

    always @(posedge pclk) begin
        if (rst) begin
            href_d        <= 1'b0;
            vsync_d       <= 1'b0;
            byte_phase    <= 1'b0;
            pixel_hi      <= 8'd0;
            x_count       <= 10'd0;
            y_count       <= 10'd0;
            full_row_addr <= {FULL_ADDR_WIDTH{1'b0}};
            base_row_addr <= {BASE_ADDR_WIDTH{1'b0}};
            frame_has_pixel <= 1'b0;
            full_wr_en    <= 1'b0;
            full_wr_addr  <= {FULL_ADDR_WIDTH{1'b0}};
            full_wr_data  <= 3'd0;
            base_wr_en    <= 1'b0;
            base_wr_addr  <= {BASE_ADDR_WIDTH{1'b0}};
            base_wr_data  <= 12'd0;
            frame_done_toggle <= 1'b0;
        end else begin
            href_d     <= href;
            vsync_d    <= vsync;
            full_wr_en <= 1'b0;
            base_wr_en <= 1'b0;

            // Notify the VGA clock domain after a frame containing real pixels ends.
            if (vsync_rise && frame_has_pixel) begin
                frame_done_toggle <= ~frame_done_toggle;
                frame_has_pixel   <= 1'b0;
            end

            if (vsync) begin
                // Frame sync from camera. Start counting pixels from top-left.
                byte_phase    <= 1'b0;
                x_count       <= 10'd0;
                y_count       <= 10'd0;
                full_row_addr <= {FULL_ADDR_WIDTH{1'b0}};
                base_row_addr <= {BASE_ADDR_WIDTH{1'b0}};
            end else begin
                if (href) begin
                    if (!byte_phase) begin
                        // First byte of RGB565.
                        pixel_hi   <= cam_data;
                        byte_phase <= 1'b1;
                    end else begin
                        // Second byte completes the pixel, so the write data
                        // and framebuffer address can be generated.
                        byte_phase <= 1'b0;

                        if (capture_full) begin
                            full_wr_en   <= 1'b1;
                            full_wr_addr <= full_row_addr + x_count;
                            full_wr_data <= full_gray;
                            frame_has_pixel <= 1'b1;
                        end

                        if (capture_base) begin
                            base_wr_en   <= 1'b1;
                            base_wr_addr <= base_row_addr + x_count[9:1];
                            base_wr_data <= {base_r4, base_g4, base_b4};
                        end

                        x_count <= x_count + 10'd1;
                    end
                end

                // End of active camera line. Move to the next row and update
                // the row base addresses without using multipliers.
                if (href_fall) begin
                    byte_phase <= 1'b0;
                    x_count    <= 10'd0;

                    if (y_count < FULL_FRAME_HEIGHT) begin
                        y_count <= y_count + 10'd1;
                    end

                    if (y_count < (FULL_FRAME_HEIGHT - 1)) begin
                        full_row_addr <= full_row_addr + FULL_FRAME_WIDTH;
                    end

                    if (!y_count[0] && (y_count < (FULL_FRAME_HEIGHT - 2))) begin
                        base_row_addr <= base_row_addr + BASE_FRAME_WIDTH;
                    end
                end
            end
        end
    end

endmodule
