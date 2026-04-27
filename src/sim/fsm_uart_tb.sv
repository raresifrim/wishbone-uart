`timescale 1ns/1ps

module fsm_uart_tb();

    localparam int CLK_FREQ_MHZ = 12;
    localparam int BAUD_RATE = 115200;
    localparam int CLK_TICKS = (CLK_FREQ_MHZ * (10**6)) / BAUD_RATE;
    localparam int CLK_PERIOD = 10;

    logic sys_clk, reset;
    logic rx, tx;
    logic rx_done, tx_done;
    bit [7:0] char;
    bit parity_bit;

    string msg = "HELLO WORLD!";

    top_soft_uart_fpga #(
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) dut(.*);

    initial begin
        sys_clk = 0;
        forever #(CLK_PERIOD/2) sys_clk = ~sys_clk;
    end


    //rx logic
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, fsm_uart_tb);

        //perform initial reset
        #0 reset = 1; rx = 1;
        #CLK_PERIOD reset = 0;
        #(CLK_PERIOD*4); //wait for initialization of the FSM

        //start transmiting the message
        foreach (msg[i]) begin
            char = msg[i];

            rx = 0; //send start bit
            #(CLK_PERIOD * CLK_TICKS);
            
            $display("Sending char %c(0x%X)" , char, char);

            //send data frame
            for (int j=0;j<8;j++) begin
                rx = char[j];
                #(CLK_PERIOD * CLK_TICKS);
            end

            rx = 1; //send stop bit
            #(CLK_PERIOD * CLK_TICKS);
        end
        
        //wait for last complete data frame to be sent at the tx_clk rate
        //10 bits of data + another 3 tx_clk cycles for reading from and writing into the fifo, and starting the transmission
        #(CLK_PERIOD * CLK_TICKS * 13);
        $finish;
    end

    bit [7:0] received_char;
    initial begin
        #(CLK_PERIOD*5); //wait for reset and initialization of the FSM
        forever begin
            wait(tx == 0) //wait for start bit
            for (int i=0;i < CLK_TICKS/2; i++)
                #CLK_PERIOD; 
            
            //collect data
            for(int j=0;j<8;j++) begin
                for (int i=0;i < CLK_TICKS; i++)
                    #CLK_PERIOD; 
                received_char[j] = tx; //sample at half 
            end

            $display("Received char %c(%x)", received_char, received_char);

            //wait for stop bit
            for (int i=0;i < CLK_TICKS; i++)
                #CLK_PERIOD;  
        end
    end

endmodule