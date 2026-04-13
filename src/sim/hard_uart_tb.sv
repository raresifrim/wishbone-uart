module hard_uart_tb();

    localparam int CLK_FREQ_MHZ = 12;
    localparam int BAUD_RATE = 115200;
    localparam string PARITY_BIT = "ODD";
    localparam int CLK_TICKS = (CLK_FREQ_MHZ * (10**6)) / BAUD_RATE;
    localparam int CLK_PERIOD = 10;

    logic sys_clk, reset;
    logic rx, tx;
    logic rx_done, tx_done;
    bit [7:0] char;
    bit parity_bit;

    string msg = "HELLO WORLD!";

    top_hard_uart_fpga #(
        .DATA_FRAME(8),
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ),
        .PARITY_BIT(PARITY_BIT)) 
    dut(.*);

    initial begin
        sys_clk = 0;
        forever #(CLK_PERIOD/2) sys_clk = ~sys_clk;
    end

    //rx logic
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, hard_uart_tb);

        //perform initial reset
        #0 reset = 1; rx = 1;
        #CLK_PERIOD reset = 0;
        #CLK_PERIOD;

        //start transmiting the message
        foreach (msg[i]) begin
            char = msg[i];
            parity_bit = (PARITY_BIT == "EVEN" && ^char == 1'b1) || (PARITY_BIT == "ODD" && ^char == 1'b0) ? 1'b1 : 1'b0;

            rx = 0; //send start bit
            for (int i=0;i < CLK_TICKS; i++)
                #CLK_PERIOD;
            
            $display("Sending char %c(0x%X)" , char, char);

            //send data frame
            for (int j=0;j<8;j++) begin
                rx = char[j];
                for (int i=0;i < CLK_TICKS; i++)
                    #CLK_PERIOD;
            end

            //send parity bit if needed
            if (PARITY_BIT != "NONE") begin
                rx = parity_bit;
                for (int i=0;i < CLK_TICKS; i++)
                    #CLK_PERIOD;
            end

            rx = 1; //send stop bit
            for (int i=0;i < CLK_TICKS; i++)
                #CLK_PERIOD; 
        end

        $finish;
    end

    bit [7:0] received_char;
    initial begin
        forever begin
            //wait for rx to be done
            wait(rx_done == 1);

            wait(tx == 0) //wait for start bit
            for (int i=0;i < CLK_TICKS/2; i++)
                #CLK_PERIOD; 
            
            //collect data
            for(int j=0;j<8;j++) begin
                for (int i=0;i < CLK_TICKS; i++)
                    #CLK_PERIOD; 
                received_char[j] = tx; //sample at half 
            end

            $display("Received char %c", received_char);

            if(PARITY_BIT != "NONE") begin
               //wait for parity bit
                for (int i=0;i < CLK_TICKS; i++)
                    #CLK_PERIOD;  
            end

            //wait for stop bit
            for (int i=0;i < CLK_TICKS; i++)
                #CLK_PERIOD;  
        end
    end

endmodule