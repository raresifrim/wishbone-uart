typedef enum bit [2:0] {IDLE, START, DATA, PARITY, STOP} fsm_state;

module hard_uart #(
    parameter int DATA_FRAME = 8,
    parameter int BAUD_RATE = 9600,
    parameter int CLK_FREQ_MHZ = 12,
    parameter string PARITY_BIT = "NONE" //NONE/ODD/EVEN
)(
    input logic sys_clk,
    input logic reset,
    input logic rx,
    input logic tx_start,
    input logic [DATA_FRAME-1:0] data_in,
    output logic tx,
    output logic [DATA_FRAME-1:0] data_out,
    output logic rx_done,
    output logic tx_done,
    output logic rx_err
);

    hard_uart_rx #(
        .DATA_FRAME(DATA_FRAME),
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ),
        .PARITY_BIT(PARITY_BIT)
    ) uart_rx_inst(
        .sys_clk(sys_clk),
        .reset(reset),
        .rx(rx),
        .data(data_out),
        .done(rx_done),
        .err(rx_err)
    );

    hard_uart_tx #(
        .DATA_FRAME(DATA_FRAME),
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ),
        .PARITY_BIT(PARITY_BIT)
    ) uart_tx_inst(
        .sys_clk(sys_clk),
        .reset(reset),
        .start(tx_start),
        .data(data_in),
        .tx(tx),
        .done(tx_done)
    );

endmodule

module hard_uart_rx #(
    parameter int DATA_FRAME = 8,
    parameter int BAUD_RATE = 9600,
    parameter int CLK_FREQ_MHZ = 12,
    parameter string PARITY_BIT = "NONE" //NONE/ODD/EVEN
)(
    input logic sys_clk,
    input logic reset,
    input logic rx,
    output logic [DATA_FRAME-1:0] data,
    output logic done,
    output logic err
);
    
    localparam int CLK_TICK = (CLK_FREQ_MHZ * (10**6)) / BAUD_RATE;

    /* registers such as:
     * shift_reg that collectes the data bits
     * bits_collected counter that is used to check if entire data frame was collected
     * counter used for baud rate generator
     * rx_sync used as double-ff synchronizer
     * current used as state machine reg
     */
    logic [3:0] bits_collected = '0;
    logic [DATA_FRAME-1:0] shift_reg = '0;
    logic [1:0] rx_sync = 2'b11;
    logic [$clog2(CLK_TICK)-1:0] counter = '0;
    fsm_state current = IDLE, next;

    /* control and status logic used for controling the registers above:
     * count_up, count_reg for the counter
     * counter_at_half, counter_full to check the baud generator state 
     * collect_bit to mark that a bit can be collected as part of the data frame
     */ 
    logic count_up, count_reset;
    logic counter_at_half, counter_full;
    logic collect_bit;

    always_ff@(posedge sys_clk) begin
        if(reset) begin
            current <= IDLE;
            rx_sync <= 2'b11;
            bits_collected <= 0;
            shift_reg <= 0;
            err <= 0;
        end
        else begin
            current <= next;
            //double-ff synchronizer
            rx_sync[0] <= rx;
            rx_sync[1] <= rx_sync[0];
            
            if(current == IDLE) begin
                bits_collected <= 0;
                shift_reg <= 0;
                err <= 0;
            end
            
            if(current == DATA && collect_bit)begin
                bits_collected <= bits_collected + 1'b1;
                shift_reg <= {rx_sync[1], shift_reg[DATA_FRAME-1:1]};
            end
            if (PARITY_BIT != "NONE") begin
                if(current == PARITY && collect_bit) begin
                    if(PARITY_BIT == "EVEN")
                        err <= ^{shift_reg, rx_sync[1]};
                    if (PARITY_BIT == "ODD")
                        err <= ~^{shift_reg, rx_sync[1]};
                end
            end
        end
    end

    //counter logic
    always_ff@(posedge sys_clk) begin
        if(reset || count_reset)
            counter <= 0;
        else if(count_up)
            counter <= counter + 1'b1;
    end 
    assign counter_full  = counter == CLK_TICK-1;
    assign counter_at_half  = counter == CLK_TICK/2;
    assign count_reset = (current == IDLE && counter_at_half) || counter_full;

    always_comb begin

        //default case
        next = current;
        count_up = 0;
        collect_bit = 0;

        unique case(current) inside
            IDLE: begin
                count_up = ~rx_sync[1];
                if (counter_at_half)
                    next = DATA;
            end

            DATA: begin
                count_up = 1;
                collect_bit = counter_full;
                if(bits_collected == DATA_FRAME)
                    if(PARITY_BIT == "NONE")
                        next = STOP;
                    else
                        next = PARITY;               
            end

            PARITY: begin
                count_up = 1;
                if (counter_full) begin
                    collect_bit = 1;
                    next = STOP;
                end
            end

            STOP: begin
               count_up = rx_sync[1];
               if (counter_full)
                    next = IDLE;
            end

        endcase

    end

    assign data = shift_reg;
    assign done = current == STOP;

endmodule


module hard_uart_tx#(
    parameter int DATA_FRAME = 8,
    parameter int BAUD_RATE = 9600,
    parameter int CLK_FREQ_MHZ = 12,
    parameter string PARITY_BIT = "NONE" //NONE/ODD/EVEN
)(
    input logic sys_clk,
    input logic reset,
    input logic start,
    input logic [DATA_FRAME-1:0] data,
    output logic tx,
    output logic done
);

    localparam int CLK_TICK = (CLK_FREQ_MHZ * (10**6)) / BAUD_RATE;

    logic [$clog2(CLK_TICK)-1:0] counter = 0;
    logic [DATA_FRAME-1:0] shift_reg = 0;
    logic parity_bit = 0;
    fsm_state current = IDLE, next;
    logic [3:0] bits_send = 0;

    logic count_up, count_reset;
    logic counter_full;
    logic send_bit;

    //counter logic
    always_ff@(posedge sys_clk) begin
        if(reset || count_reset)
            counter <= 0;
        else if(count_up)
            counter <= counter + 1'b1;
    end 
    assign counter_full  = counter == CLK_TICK-1;
    assign count_reset = counter_full;
    assign count_up = current != IDLE;

    always_ff@(posedge sys_clk) begin
        if(reset) begin
            current <= IDLE;
            shift_reg <= 0;
            bits_send <= 0;
            if (PARITY_BIT != "NONE")
                parity_bit <= 0;
        end
        else begin
            current <= next;
            if(current == IDLE && start) begin
                shift_reg <= data;
                if (PARITY_BIT == "EVEN")
                    parity_bit <= ^data == 1'b1 ? 1'b1 : 1'b0;
                else if (PARITY_BIT == "ODD")
                    parity_bit <= ^data == 1'b1 ? 1'b0 : 1'b1;
                bits_send <= 0;
            end
            else if(send_bit)begin
                shift_reg <= {1'b0, shift_reg[DATA_FRAME-1:1]};
                bits_send <= bits_send + 1'b1;
            end
        end
    end

    always_comb begin
        
        send_bit = 0;
        next = current;
        tx = 1;

        unique case(current) inside
            IDLE: begin
                tx = 1;
                if(start)
                    next = START;
            end

            START: begin
                tx = 0;
                if (counter_full)
                    next = DATA;
            end

            DATA: begin
                tx = shift_reg[0];
                send_bit = counter_full;
                if(bits_send == DATA_FRAME)
                    if(PARITY_BIT == "NONE")
                        next = STOP;
                    else 
                        next = PARITY;
            end

            PARITY: begin
                tx = parity_bit;
                if(counter_full)
                    next = STOP;
            end

            STOP: begin
                tx = 1;
                if(counter_full)
                    next = IDLE;
            end
        endcase
    end

    assign done = current == STOP;
endmodule