module ov7670_sccb_init #(
    parameter integer CLK_HZ          = 100_000_000,
    parameter integer SCCB_HZ         = 100_000,
    parameter integer POWERUP_DELAYMS = 20
) (
    input  wire clk,
    input  wire rst,
    output reg  sioc,
    output wire siod_oe_low,
    input  wire siod_in,
    output reg  busy,
    output reg  done,
    output reg  ack_error
);
    // Timing values derived from the 100 MHz system clock. The SCCB bus is
    // intentionally slow because camera configuration does not need high bandwidth.
    localparam integer LUT_SIZE       = 71;
    localparam integer HALF_PERIOD    = CLK_HZ / (SCCB_HZ * 2);
    localparam integer STARTUP_TICKS  = (CLK_HZ / HALF_PERIOD / 1000) * POWERUP_DELAYMS;
    localparam integer INTERREG_TICKS = (CLK_HZ / HALF_PERIOD / 10000); // ~100 us
    localparam integer RESETREG_TICKS = (CLK_HZ / HALF_PERIOD / 100);   // ~10 ms

    // SCCB write transaction state machine.
    localparam [3:0]
        ST_POWERUP_WAIT = 4'd0,
        ST_LOAD         = 4'd1,
        ST_START_A      = 4'd2,
        ST_START_B      = 4'd3,
        ST_BIT_LOW      = 4'd4,
        ST_BIT_HIGH     = 4'd5,
        ST_ACK_LOW      = 4'd6,
        ST_ACK_HIGH     = 4'd7,
        ST_STOP_A       = 4'd8,
        ST_STOP_B       = 4'd9,
        ST_STOP_C       = 4'd10,
        ST_REG_WAIT     = 4'd11,
        ST_DONE         = 4'd12;

    // Each LUT entry is {register_address, register_data}. The last entry is
    // 16'hFFFF, which marks the end of the initialization sequence.
    reg [15:0] init_lut [0:LUT_SIZE-1];

    reg [3:0]  state;
    reg [15:0] clk_div;
    reg [23:0] wait_ticks;
    reg [7:0]  lut_idx;
    reg [7:0]  reg_addr;
    reg [7:0]  reg_data;
    reg [7:0]  tx_byte;
    reg [1:0]  byte_idx;
    reg [2:0]  bit_idx;
    reg        sda_drive_low;

    wire tick = (clk_div == HALF_PERIOD - 1);

    // SCCB/I2C data is open-drain style. The top module drives SIOD low when
    // this signal is high, otherwise it releases the line.
    assign siod_oe_low = sda_drive_low;

    initial begin
        // Soft reset
        init_lut[0]  = 16'h1280;

        // Clocking / format / scaling for VGA RGB565.
        init_lut[1]  = 16'h1101;
        init_lut[2]  = 16'h6B4A;
        init_lut[3]  = 16'h0C00;
        init_lut[4]  = 16'h3E00;
        init_lut[5]  = 16'h1204;
        init_lut[6]  = 16'h8C00;
        init_lut[7]  = 16'h40D0;
        init_lut[8]  = 16'h3A04;

        // Windowing for VGA path. The previous horizontal window ended with a
        // repeated right-edge column on some OV7670 modules. These HSTART/HSTOP
        // values are the common VGA preset used by many OV7670 reference designs.
        init_lut[9]  = 16'h32B6;
        init_lut[10] = 16'h1713;
        init_lut[11] = 16'h1801;
        init_lut[12] = 16'h1902;
        init_lut[13] = 16'h1A7A;
        init_lut[14] = 16'h030A;

        // Scaling control
        init_lut[15] = 16'h703A;
        init_lut[16] = 16'h7135;
        init_lut[17] = 16'h7211;
        init_lut[18] = 16'h73F0;
        init_lut[19] = 16'hA202;

        // Image tuning defaults
        init_lut[20] = 16'h1500;
        init_lut[21] = 16'h7A20;
        init_lut[22] = 16'h7B10;
        init_lut[23] = 16'h7C1E;
        init_lut[24] = 16'h7D35;
        init_lut[25] = 16'h7E5A;
        init_lut[26] = 16'h7F69;
        init_lut[27] = 16'h8076;
        init_lut[28] = 16'h8180;
        init_lut[29] = 16'h8288;
        init_lut[30] = 16'h838F;
        init_lut[31] = 16'h8496;
        init_lut[32] = 16'h85A3;
        init_lut[33] = 16'h86AF;
        init_lut[34] = 16'h87C4;
        init_lut[35] = 16'h88D7;
        init_lut[36] = 16'h89E8;

        // Enable automatic exposure/gain/white balance. Starting at max gain/AEC
        // overexposes many OV7670 modules, especially under classroom lighting.
        // The banding filter and late AWB gain registers below reduce green cast.
        init_lut[37] = 16'h13EF;
        init_lut[38] = 16'h0000;
        init_lut[39] = 16'h1000;
        init_lut[40] = 16'h0D40;
        init_lut[41] = 16'h1418;
        init_lut[42] = 16'hA505;
        init_lut[43] = 16'hAB07;
        init_lut[44] = 16'h2495;
        init_lut[45] = 16'h2533;
        init_lut[46] = 16'h26E3;

        // Matrix coefficients
        init_lut[47] = 16'h4FB3;
        init_lut[48] = 16'h50B3;
        init_lut[49] = 16'h5100;
        init_lut[50] = 16'h523D;
        init_lut[51] = 16'h53A7;
        init_lut[52] = 16'h54E4;
        init_lut[53] = 16'h589E;

        // Misc recommended controls
        init_lut[54] = 16'h3DC0;
        init_lut[55] = 16'h1E37;
        init_lut[56] = 16'h330B;
        init_lut[57] = 16'h3C78;
        init_lut[58] = 16'h6900;
        init_lut[59] = 16'h7400;
        init_lut[60] = 16'hB084;
        init_lut[61] = 16'hB10C;
        init_lut[62] = 16'hB20E;
        init_lut[63] = 16'hB382;
        init_lut[64] = 16'hB80A;

        // Late AWB/color controls. Applying these after matrix/gamma setup helps
        // modules that otherwise make neutral white objects look green.
        init_lut[65] = 16'h4108;
        init_lut[66] = 16'h6F9F;
        init_lut[67] = 16'h5500;
        init_lut[68] = 16'h5640;
        init_lut[69] = 16'h13EF;

        // End marker
        init_lut[70] = 16'hFFFF;
    end

    always @(posedge clk) begin
        if (rst) begin
            state         <= ST_POWERUP_WAIT;
            clk_div       <= 16'd0;
            wait_ticks    <= STARTUP_TICKS[23:0];
            lut_idx       <= 8'd0;
            reg_addr      <= 8'd0;
            reg_data      <= 8'd0;
            tx_byte       <= 8'h42;
            byte_idx      <= 2'd0;
            bit_idx       <= 3'd7;
            sioc          <= 1'b1;
            sda_drive_low <= 1'b0;
            busy          <= 1'b1;
            done          <= 1'b0;
            ack_error     <= 1'b0;
        end else begin
            if (tick) begin
                clk_div <= 16'd0;

                case (state)
                    ST_POWERUP_WAIT: begin
                        // Give the camera time to power up before the first register write.
                        sioc          <= 1'b1;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b1;
                        done          <= 1'b0;

                        if (wait_ticks == 24'd0) begin
                            state <= ST_LOAD;
                        end else begin
                            wait_ticks <= wait_ticks - 24'd1;
                        end
                    end

                    ST_LOAD: begin
                        // Load the next register pair, or finish when the end marker is reached.
                        if (init_lut[lut_idx] == 16'hFFFF) begin
                            state <= ST_DONE;
                        end else begin
                            reg_addr      <= init_lut[lut_idx][15:8];
                            reg_data      <= init_lut[lut_idx][7:0];
                            tx_byte       <= 8'h42; // OV7670 write address
                            byte_idx      <= 2'd0;
                            bit_idx       <= 3'd7;
                            state         <= ST_START_A;
                        end
                    end

                    ST_START_A: begin
                        // Start condition: SDA falls while SIOC is high.
                        sioc          <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state         <= ST_START_B;
                    end

                    ST_START_B: begin
                        sioc          <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state         <= ST_BIT_LOW;
                    end

                    ST_BIT_LOW: begin
                        // Drive the next data bit while the clock is low.
                        sioc <= 1'b0;
                        if (tx_byte[bit_idx]) begin
                            sda_drive_low <= 1'b0;
                        end else begin
                            sda_drive_low <= 1'b1;
                        end
                        state <= ST_BIT_HIGH;
                    end

                    ST_BIT_HIGH: begin
                        sioc <= 1'b1;
                        if (bit_idx == 3'd0) begin
                            state <= ST_ACK_LOW;
                        end else begin
                            bit_idx <= bit_idx - 3'd1;
                            state   <= ST_BIT_LOW;
                        end
                    end

                    ST_ACK_LOW: begin
                        // Release SDA so the camera can acknowledge the byte.
                        sioc          <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state         <= ST_ACK_HIGH;
                    end

                    ST_ACK_HIGH: begin
                        // ACK is active low. If SDA stays high, remember the error on an LED.
                        sioc <= 1'b1;
                        if (siod_in) begin
                            ack_error <= 1'b1;
                        end
                        if (byte_idx == 2'd2) begin
                            state <= ST_STOP_A;
                        end else begin
                            byte_idx <= byte_idx + 2'd1;
                            bit_idx  <= 3'd7;

                            case (byte_idx)
                                2'd0: tx_byte <= reg_addr;
                                2'd1: tx_byte <= reg_data;
                                default: tx_byte <= 8'h00;
                            endcase

                            state <= ST_BIT_LOW;
                        end
                    end

                    ST_STOP_A: begin
                        // Stop condition begins by pulling SDA low while SIOC is low.
                        sioc          <= 1'b0;
                        sda_drive_low <= 1'b1;
                        state         <= ST_STOP_B;
                    end

                    ST_STOP_B: begin
                        sioc          <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state         <= ST_STOP_C;
                    end

                    ST_STOP_C: begin
                        // Release SDA and wait before sending the next register.
                        sioc          <= 1'b1;
                        sda_drive_low <= 1'b0;
                        if ((reg_addr == 8'h12) && (reg_data == 8'h80)) begin
                            wait_ticks <= RESETREG_TICKS[23:0];
                        end else begin
                            wait_ticks <= INTERREG_TICKS[23:0];
                        end
                        state <= ST_REG_WAIT;
                    end

                    ST_REG_WAIT: begin
                        if (wait_ticks == 24'd0) begin
                            lut_idx <= lut_idx + 8'd1;
                            state   <= ST_LOAD;
                        end else begin
                            wait_ticks <= wait_ticks - 24'd1;
                        end
                    end

                    ST_DONE: begin
                        // Initialization is complete; leave the bus idle.
                        sioc          <= 1'b1;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_DONE;
                    end

                    default: state <= ST_POWERUP_WAIT;
                endcase
            end else begin
                clk_div <= clk_div + 16'd1;
            end
        end
    end

endmodule
