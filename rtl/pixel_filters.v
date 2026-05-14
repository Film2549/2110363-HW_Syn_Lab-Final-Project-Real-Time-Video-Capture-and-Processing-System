module pixel_filters (
    input  wire [11:0] pixel_in,
    input  wire [1:0]  mode,
    output reg  [11:0] pixel_out
);
    // Split RGB444 input into separate color channels.
    wire [3:0] r = pixel_in[11:8];
    wire [3:0] g = pixel_in[7:4];
    wire [3:0] b = pixel_in[3:0];

    // Weighted grayscale approximation. Green is weighted highest because it
    // contributes most to perceived brightness.
    wire [7:0] gray_acc = (r << 2) + r + (g << 3) + g + (b << 1); // 5R + 9G + 2B
    wire [3:0] gray     = gray_acc[7:4];

    // Switch-selected real-time filter.
    always @(*) begin
        case (mode)
            2'b00: pixel_out = pixel_in;                // Raw
            2'b01: pixel_out = {gray, gray, gray};      // Grayscale
            2'b10: pixel_out = {~r, ~g, ~b};            // Negative
            2'b11: pixel_out = {r, 4'h0, 4'h0};         // Red-only channel
            default: pixel_out = pixel_in;
        endcase
    end

endmodule
