`timescale 1ns/1ps

module soft_uart_tb;

    // Parameters
    parameter int FIFO_DEPTH = 16;
    parameter int CLK_PERIOD = 10; // 100MHz
    
    localparam logic [9:0] ADDR_TX_BUF    = 10'h0;
    localparam logic [9:0] ADDR_TX_STAT   = 10'h2;
    localparam logic [9:0] ADDR_RX_BUF    = 10'h4;
    localparam logic [9:0] ADDR_RX_STAT   = 10'h6;
    localparam logic [9:0] ADDR_BAUD_DIV  = 10'h8;
    localparam logic [9:0] ADDR_CTRL_EN   = 10'hA;
    localparam logic [9:0] ADDR_CTRL_CLR  = 10'hC;

    // Testbench signals
    logic clk;
    logic reset;
    logic rx;
    logic tx;
    logic rx_done;
    logic tx_done;

    // Wishbone Interface Instance
    wishboneIf #(.ADDR_WIDTH(10)) wb_bus(clk);

    // DUT Instantiation
    soft_uart #(
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .sys_clk(clk),
        .reset(reset),
        .rx(rx),
        .tx(tx),
        .wbif(wb_bus.Slave),
        .rx_done(rx_done),
        .tx_done(tx_done)
    );

    // --- Clock Generation ---
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, soft_uart_tb);
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    
    // Task to drive a byte into the RX pin (simulating external device)
    // Assumes 8N1: 1 start bit (0), 8 data bits (LSB first), 1 stop bit (1)
    task automatic drive_external_rx(input [7:0] data, input int baud_div);
        int bit_period = CLK_PERIOD * baud_div;
        
        $display("[External] Sending byte 0x%h to RX line", data);
        
        // Start bit
        rx = 0;
        #(bit_period);
        
        // Data bits (LSB first)
        for (int i = 0; i < 8; i++) begin
            rx = data[i];
            #(bit_period);
        end
        
        // Stop bit
        rx = 1;
        #(bit_period);
    endtask

    // --- Main Test Sequence ---
    logic [31:0] read_data;
    int test_baud_div = 100; // Small value for faster simulation
    logic [7:0] test_data [6] = {8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'hC0, 8'hDE};

    initial begin
        // Initialize signals
        reset = 1;
        rx = 1; // Idle state for UART is High

        repeat(5) @(posedge clk);
        reset = 0;
        $display("--- Reset Released ---");

        // 1. Configure Baud Rate
        wb_bus.MasterWrite(ADDR_BAUD_DIV, test_baud_div);

        // 2. Enable Baud Gen, TX, and RX (Bits: RX=2, TX=1, Baud=0 -> 3'b111 = 0x7)
        wb_bus.MasterWrite(ADDR_CTRL_EN, 32'h7);
        $display("UART Enabled: Baud, TX, and RX");

        // 3. Test TX (Write to FIFO and wait for completion)
        $display("--- Testing TX Path ---");
        wb_bus.MasterWrite(ADDR_TX_BUF, 32'hA5);
        wait(tx_done);
        $display("TX Done pulsed.");
        
        wb_bus.MasterWrite(ADDR_TX_BUF, 32'h5A);
        wait(tx_done);
        $display("TX Done pulsed.");

        foreach(test_data[i])
            wb_bus.MasterWrite(ADDR_TX_BUF, 32'(test_data[i]));
        wait(tx_done);
        $display("TX Done pulsed.");

        // 4. Test RX (Simulate incoming serial data)
        $display("--- Testing RX Path ---");
        fork
            drive_external_rx(8'h3C, test_baud_div);
        join_none

        // Wait for RX Status bit 0 (Buffer_empty) to go low, or check rx_done
        wait(rx_done);

        // Check Status Register
        wb_bus.MasterRead(ADDR_RX_STAT, read_data);
        if (read_data[0] == 0) begin // Bit 0 is Buffer_empty
            $display("RX Buffer is not empty, reading data...");
            wb_bus.MasterRead(ADDR_RX_BUF, read_data);
            if (read_data[7:0] == 8'h3C)
                $display("SUCCESS: Received correct data 0x%h", read_data[7:0]);
            else begin
                $display("ERROR: Data mismatch! Received 0x%h", read_data[7:0]);
                $stop;
            end
        end
        else begin
           $display("Nothing to read..."); 
        end
        
        #(CLK_PERIOD);

        foreach(test_data[i]) begin
            drive_external_rx(test_data[i], test_baud_div);
        end


        foreach(test_data[i]) begin
            wb_bus.MasterRead(ADDR_RX_STAT, read_data);
            if(read_data[0] == 1) begin //if empty wait for data to be received
                wait(rx_done);
            end   
            wb_bus.MasterRead(ADDR_RX_BUF, read_data); 
            if (read_data[7:0] == test_data[i])
                $display("SUCCESS: Received correct data 0x%h", read_data[7:0]);
            else begin
                $display("ERROR: Data mismatch! Received 0x%h", read_data[7:0]);
                $stop;
            end
        end

        
        //// 5. Test FIFO Clear
        //$display("--- Testing FIFO Clear ---");
        //wb_bus.MasterWrite(ADDR_CTRL_CLR, 32'h6); // Clear RX (bit 1) and TX (bit 2)
        
        #100;
        $display("Testbench Finished.");
        $finish;
    end

    // Monitor for debug
    initial begin
        $monitor("Time: %0t | TX: %b | RX: %b | RX_DONE: %b | TX_DONE: %b", 
                 $time, tx, rx, rx_done, tx_done);
    end

endmodule