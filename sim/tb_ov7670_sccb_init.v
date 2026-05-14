`timescale 1ns/1ps

module tb_ov7670_sccb_init;
    reg clk;
    reg rst;

    wire sioc;
    wire siod_oe_low;
    wire busy;
    wire done;
    wire ack_error;

    // Ideal open-drain SCCB line model:
    // - the FPGA drives low when siod_oe_low is 1
    // - otherwise the pull-up makes the line high
    // - siod_in is held low to model the camera acknowledging every byte
    wire sda_line = siod_oe_low ? 1'b0 : 1'b1;
    wire siod_in  = 1'b0;

    ov7670_sccb_init #(
        .CLK_HZ         (1_000_000),
        .SCCB_HZ        (100_000),
        .POWERUP_DELAYMS(1)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .sioc       (sioc),
        .siod_oe_low(siod_oe_low),
        .siod_in    (siod_in),
        .busy       (busy),
        .done       (done),
        .ack_error  (ack_error)
    );

    always #5 clk = ~clk;

    integer start_count;
    integer stop_count;
    integer tx_count;
    integer timeout_count;
    integer bit_count;
    integer byte_count;
    reg     in_transaction;
    reg [7:0] shift_byte;
    reg [7:0] first_dev_addr;
    reg [7:0] first_reg_addr;
    reg [7:0] first_reg_data;

    always @(negedge sda_line) begin
        if (!rst && sioc) begin
            start_count    = start_count + 1;
            in_transaction = 1'b1;
            bit_count      = 0;
            byte_count     = 0;
            shift_byte     = 8'h00;
        end
    end

    always @(posedge sda_line) begin
        if (!rst && sioc && in_transaction) begin
            stop_count     = stop_count + 1;
            tx_count       = tx_count + 1;
            in_transaction = 1'b0;
        end
    end

    always @(posedge sioc) begin
        if (!rst && in_transaction) begin
            if (bit_count < 8) begin
                shift_byte = {shift_byte[6:0], sda_line};
                bit_count  = bit_count + 1;
            end else begin
                if (tx_count == 0) begin
                    if (byte_count == 0) begin
                        first_dev_addr = shift_byte;
                    end else if (byte_count == 1) begin
                        first_reg_addr = shift_byte;
                    end else if (byte_count == 2) begin
                        first_reg_data = shift_byte;
                    end
                end

                byte_count = byte_count + 1;
                bit_count  = 0;
                shift_byte = 8'h00;
            end
        end
    end

    initial begin
        clk            = 1'b0;
        rst            = 1'b1;
        start_count    = 0;
        stop_count     = 0;
        tx_count       = 0;
        timeout_count  = 0;
        bit_count      = 0;
        byte_count     = 0;
        in_transaction = 1'b0;
        shift_byte     = 8'h00;
        first_dev_addr = 8'h00;
        first_reg_addr = 8'h00;
        first_reg_data = 8'h00;

        repeat (10) @(posedge clk);
        rst = 1'b0;

        while (!done && timeout_count < 200000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (!done) begin
            $display("ERROR: SCCB initialization timed out");
            $finish;
        end

        if (busy !== 1'b0) begin
            $display("ERROR: busy should be low after done");
            $finish;
        end

        if (ack_error !== 1'b0) begin
            $display("ERROR: ack_error should remain low when camera ACKs");
            $finish;
        end

        if (tx_count !== 70) begin
            $display("ERROR: expected 70 SCCB register writes, got %0d", tx_count);
            $finish;
        end

        if ((start_count !== 70) || (stop_count !== 70)) begin
            $display(
                "ERROR: expected 70 starts/stops, got starts=%0d stops=%0d",
                start_count,
                stop_count
            );
            $finish;
        end

        if ((first_dev_addr !== 8'h42) ||
            (first_reg_addr !== 8'h12) ||
            (first_reg_data !== 8'h80)) begin
            $display(
                "ERROR: first write decoded as dev=%h reg=%h data=%h, expected 42 12 80",
                first_dev_addr,
                first_reg_addr,
                first_reg_data
            );
            $finish;
        end

        $display("PASS: tb_ov7670_sccb_init");
        $finish;
    end
endmodule
