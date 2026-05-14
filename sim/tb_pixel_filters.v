`timescale 1ns/1ps

module tb_pixel_filters;
    reg  [11:0] pixel_in;
    reg  [1:0]  mode;
    wire [11:0] pixel_out;

    pixel_filters dut (
        .pixel_in(pixel_in),
        .mode(mode),
        .pixel_out(pixel_out)
    );

    task check;
        input [1:0]  t_mode;
        input [11:0] t_in;
        input [11:0] t_exp;
        begin
            mode     = t_mode;
            pixel_in = t_in;
            #1;
            if (pixel_out !== t_exp) begin
                $display("ERROR: mode=%b in=%h out=%h expected=%h", t_mode, t_in, pixel_out, t_exp);
                $finish;
            end
        end
    endtask

    initial begin
        check(2'b00, 12'hA53, 12'hA53); // raw
        check(2'b10, 12'hA53, 12'h5AC); // negative
        check(2'b11, 12'hA53, 12'hA00); // red-only

        // grayscale expected from formula: gray=(5R+9G+2B)>>4
        // R=10,G=5,B=3 => (50+45+6)=101 => 6
        check(2'b01, 12'hA53, 12'h666);

        $display("PASS: tb_pixel_filters");
        $finish;
    end
endmodule
