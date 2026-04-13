module soft_uart#(
    parameter int FIFO_DEPTH = 16
)(
    input logic sys_clk,
    input logic reset,
    input logic rx,
    output logic tx,
    wishboneIf.Slave wbif,
    output logic rx_done,
    output logic tx_done
);

    localparam type data_t = bit [wbif.DATA_WIDTH-1:0];
    logic rx_clk, tx_clk;
    logic [15:0]  regs [7];
    //TX BUFFER OFFSET - 0x0 (WRITE ONLY) REG0
    //TX STATUS OFFSET - 0x2 (READ ONLY) REG1
    //RX BUFFER OFFSET - 0x4 (READ ONLY) REG2
    //RX STATUS OFFSET - 0x6 (READ ONLY) REG3
    //RX/TX STATUS REG BITS: 1-Buffer_full 0-Buffer_empty
    //BAUD DIV VALUE OFFSET - 0x8 (READ/WRITE) REG4
    //ENABLE CONTROL OFFSET - 0xA (READ/WRITE) REG5
    //ENABLE CONTROL BITS: 2-Enable_RX 1-Enable_TX 0-Enable_BAUD
    //CLEAR CONTROL OFFSET - 0xC (WRITE ONLY)REG6
    //ENABLE CONTROL BITS: 1-Clear_RX_fifo 2-Clear_TX_fifo

    enum bit [2:0] {TX_BUFFER, TX_STATUS, RX_BUFFER, RX_STATUS, BAUD_DIV, ENABLE_REG, CLEAR_REG} CAS;

    data_t dat_o_reg = '0;
    data_t dat_i_reg = '0;
    logic ack_o_reg = '0;
    logic cyc_i_reg = '0;
    logic stb_i_reg = '0;
    logic we_i_reg = '0;
    logic [wbif.ADDR_WIDTH-1:0] adr_i_valid = '0;

    assign wbif.data_rd = dat_o_reg;
    assign wbif.ack = ack_o_reg;
    assign wbif.stall = 1'b0; //no actual stall required
    assign wbif.err = cyc_i_reg && stb_i_reg && (adr_i_valid > 4'hA);

    logic rx_clear_fifo, rx_read_fifo, rx_empty, rx_full, rx_reset;
    logic [7:0] rx_data;
    assign rx_reset = reset | ~regs[ENABLE_REG][2];
    assign regs[RX_STATUS][0] = rx_empty;
    assign regs[RX_STATUS][1] = rx_full;
    assign rx_clear_fifo = regs[CLEAR_REG][1];
    assign regs[RX_BUFFER][7:0] = rx_data;

    soft_uart_rx#(
        .DEPTH(FIFO_DEPTH)  
    ) uart_rx_inst(
        .sys_clk(sys_clk),
        .rx_clk(rx_clk),
        .reset(rx_reset),
        .clear_fifo(rx_clear_fifo),
        .read_fifo(rx_read_fifo),
        .rx(rx),
        .data(rx_data),
        .rx_int(rx_done),
        .rx_empty(rx_empty),
        .rx_full(rx_full)
    );


    logic tx_full, tx_empty, tx_clear_fifo, tx_write_fifo, tx_reset;
    logic [7:0] tx_data;
    assign tx_reset = reset | ~regs[ENABLE_REG][1];
    assign regs[TX_STATUS][0] = tx_empty;
    assign regs[TX_STATUS][1] = tx_full;
    assign tx_clear_fifo = regs[CLEAR_REG][0];
    assign tx_data = regs[TX_BUFFER][7:0];

    soft_uart_tx #(
        .DEPTH(FIFO_DEPTH)
    ) uart_tx_inst(
        .sys_clk(sys_clk),
        .tx_clk(tx_clk),
        .reset(tx_reset),
        .clear_fifo(tx_clear_fifo),
        .write_fifo(tx_write_fifo),
        .data(tx_data),
        .tx(tx),
        .tx_int(tx_done),
        .tx_empty(tx_empty),
        .tx_full(tx_full)
);

    logic baud_gen_ce, baud_gen_load;
    logic [15:0] baud_gen_div;
    assign baud_gen_ce = regs[ENABLE_REG][0];
    assign baud_gen_div = regs[BAUD_DIV];
    baud_gen baud_gen_inst(
        .sys_clk(sys_clk),
        .ce(baud_gen_ce),
        .load(baud_gen_load),
        .div(baud_gen_div),
        .rx_clk(rx_clk),
        .tx_clk(tx_clk)
    );

    always @(posedge sys_clk) begin
        if (reset) begin
            ack_o_reg <= '0;
            adr_i_valid <= '0;
            cyc_i_reg <= '0;
            stb_i_reg <= '0;
            we_i_reg <= '0;
            dat_i_reg <= '0;
            dat_o_reg <= '0;
            for(int i=0;i<6;i++)
                regs[i] <= '0;
            rx_read_fifo <= '0;
            tx_write_fifo <= '0;
            baud_gen_load <= '0;
        end
        else begin
            logic rx_read, tx_write, baud_load;

            //pipeline both inputs and outputs for better timing
            ack_o_reg <= cyc_i_reg & stb_i_reg & (adr_i_valid <= 4'hA);
            adr_i_valid <= wbif.addr;
            cyc_i_reg <= wbif.cyc;
            stb_i_reg <= wbif.stb;
            we_i_reg <= wbif.we;
            dat_i_reg <= wbif.data_wr;

            //default valus for control bits
            rx_read = 1'b0;
            tx_write = 1'b0;
            baud_load = 1'b0;

            if (cyc_i_reg & stb_i_reg) begin
                if (we_i_reg) begin
                    unique case(adr_i_valid)
                        4'h0: begin //write to tx buffer
                            regs[TX_BUFFER][7:0] <= dat_i_reg[7:0];
                            tx_write = 1'b1;
                        end
                        4'h8: begin //write to the baud div reg
                            regs[BAUD_DIV] <= dat_i_reg[15:0];
                            baud_load = 1'b1;
                        end
                        4'hA: begin //write to the the enable reg
                            regs[ENABLE_REG][7:0] <= dat_i_reg[7:0];
                        end
                        4'hC: begin //write to the the clear reg
                            regs[CLEAR_REG][7:0] <= dat_i_reg[7:0];
                        end
                    endcase
                end
                unique case(adr_i_valid)
                    4'h2: begin //read tx status
                        dat_o_reg <= {{(wbif.DATA_WIDTH-16){1'b0}}, regs[TX_STATUS]}; 
                    end
                    4'h4: begin //read rx buffer
                        dat_o_reg <= {{(wbif.DATA_WIDTH-16){1'b0}}, regs[RX_BUFFER]};
                        rx_read = 1'b1;
                    end
                    4'h6: begin //read rx status
                        dat_o_reg <= {{(wbif.DATA_WIDTH-16){1'b0}}, regs[RX_STATUS]}; 
                    end
                    4'h8: begin //read baud value
                        dat_o_reg <= {{(wbif.DATA_WIDTH-16){1'b0}}, regs[BAUD_DIV]}; 
                    end
                    4'hA: begin //read baud enable status
                        dat_o_reg <= {{(wbif.DATA_WIDTH-16){1'b0}}, regs[ENABLE_REG]};
                    end
                endcase

            end

            //update bits of control flip-flops
            rx_read_fifo <= rx_read;
            tx_write_fifo <= tx_write;
            baud_gen_load <= baud_load;

        end
    end


endmodule


module soft_uart_rx#(
    parameter int DEPTH=16  
)(
    input logic sys_clk,
    input logic rx_clk,
    input logic reset,
    input logic clear_fifo,
    input logic read_fifo,
    input logic rx,
    output logic [7:0] data,
    output logic rx_int,
    output logic rx_empty,
    output logic rx_full
);

    logic [3:0] sample_counter = 4'b1111;
    logic [3:0] bit_counter = 4'b0000;
    logic [7:0] shift_reg = 0;
    logic [1:0] rx_sync = 2'b11;
    logic count_enable, count_reset;
    logic collect_bit;
    logic [2:0] vote_bits;
    logic final_vote;
    fsm_state current = IDLE, next;

    assign collect_bit = sample_counter == 0;
    assign final_vote = (vote_bits[0] && vote_bits[1]) ||
                        (vote_bits[1] && vote_bits[2]) ||
                        (vote_bits[2] && vote_bits[0]);
    
    always_ff@(posedge rx_clk) begin
        if(reset) begin
            sample_counter <= 4'b1111;
            current <= IDLE;
            rx_sync <= 2'b11;
            shift_reg <= 0;
            vote_bits <= 3'b0;
            bit_counter <= 4'b0000;
        end
        else begin
            //fsm state updater
            current <= next;
           
            if (sample_counter == 4'd7)
                vote_bits[0] <= rx_sync[1];
            if (sample_counter == 4'd8)
                vote_bits[1] <= rx_sync[1];
            if (sample_counter == 4'd9)
                vote_bits[2] <= rx_sync[1];

            //sample counter 
            if(count_reset)
                sample_counter <= 4'b1111;
            else if(count_enable)
                sample_counter <= sample_counter - 1'b1;

            if(current == START) begin
                shift_reg <= 0;
                bit_counter <= 0;
            end
            else if(current == DATA && collect_bit) begin
                shift_reg <= {final_vote, shift_reg[7:1]};
                bit_counter <= bit_counter + 1'b1;
            end
            
            //double-ff synchronizer
            rx_sync[0] <= rx;
            rx_sync[1] <= rx_sync[0];
        end
    end

    always_comb begin
        
        count_reset = 0;
        count_enable = 0;
        rx_int = 0;

        unique case(current)
            IDLE: begin
                count_reset = 1;
                if(!rx_sync[1])
                    next = START;
            end

            START: begin
                count_enable = 1;
                if(collect_bit)
                    if(!final_vote)
                        next = DATA;
                    else
                        next = IDLE;
            end

            DATA: begin
                count_enable = 1; 
                if(bit_counter == 4'd8)
                   next = STOP; 
            end

            STOP: begin
                count_enable = 1;
                if(collect_bit) begin
                    next = IDLE; 
                    rx_int = 1;
                end
            end
        endcase
    end

    async_fifo #(
        .DEPTH(DEPTH), 
        .DATA_T(logic [7:0]),
        .FIFO_NAME("RX_FIFO"),
        .DEBUG(1)
    ) fifo_inst(
        .rclk(sys_clk),
        .wclk(rx_clk),
        .rst(reset),
        .i_clear(clear_fifo),
        .i_wr_en(rx_int),    // Write enable
        .i_rd_en(read_fifo),    // Read enable
        .i_data(shift_reg),     // Data written into FIFO
        .o_data(data),     // Data read from FIFO
        .o_empty(rx_empty),    // FIFO is empty when high
        .o_full(rx_full)     // FIFO is full when high,
    );

endmodule


module soft_uart_tx #(
    parameter int DEPTH=16
)(
    input logic sys_clk,
    input logic tx_clk,
    input logic reset,
    input logic clear_fifo,
    input logic write_fifo,
    input logic [7:0] data,
    output logic tx,
    output logic tx_int,
    output logic tx_empty,
    output logic tx_full
);

    logic [7:0] shift_reg;
    fsm_state current = IDLE, next;
    logic tx_wire;
    logic tx_start;
    logic [3:0] bit_counter = 4'd0; 

    assign tx_start = ~tx_empty && (current == IDLE || current == STOP);

    always@(posedge tx_clk) begin
        if(reset) begin
            tx <= 1;
            current <= IDLE;
            bit_counter <= 4'd0;
        end
        else begin
            tx <= tx_wire;
            if(current == DATA)
                bit_counter <= bit_counter + 1'b1;
            else if(current == START)
                bit_counter <= 4'd0;
        end
    end

    always_comb begin

        tx_wire = 1;
        next = current;

        unique case(current)
            IDLE: begin
                tx_wire = 1;
                if (tx_start)
                    next = START;
            end

            START: begin
                tx_wire = 0;
                next = DATA;
            end

            DATA: begin
                tx_wire = shift_reg[bit_counter];
                if(bit_counter == 4'd8)
                    next = STOP;
            end

            STOP: begin
                tx_wire = 1;
                if(tx_start)
                    next = START;
                else
                    next = IDLE;
            end

        endcase
    end

    assign tx_int = current == STOP;


    async_fifo #(
        .DEPTH(DEPTH), 
        .DATA_T(logic [7:0]),
        .FIFO_NAME("TX_FIFO"),
        .DEBUG(1)
    ) fifo_inst(
        .rclk(tx_clk),
        .wclk(sys_clk),
        .rst(reset),
        .i_clear(clear_fifo),
        .i_wr_en(write_fifo),    // Write enable
        .i_rd_en(tx_start),    // Read enable
        .i_data(data),     // Data written into FIFO
        .o_data(shift_reg),     // Data read from FIFO
        .o_empty(tx_empty),    // FIFO is empty when high
        .o_full(tx_full)     // FIFO is full when high,
    );


endmodule

module baud_gen(
    input logic sys_clk,
    input logic ce,
    input logic load,
    input logic [15:0] div,
    output logic rx_clk,
    output logic tx_clk
);
    //we need to separate counters as the rx clk will be generated to support 16x oversampling
    logic [15:0] rx_counter = 0, tx_counter = 0;
    logic [15:0] div_reg = 12 * (10**6) / 9600; //initialize with a default baud rate of 9600 for 12MHz

    always_ff@(posedge sys_clk) begin
        if(load) begin
            rx_counter <= div >> 4;
            tx_counter <= div;
            div_reg <= div;
        end
        else if(ce) begin
            if(rx_counter == 0)
                rx_counter <= div_reg >> 3;
            else
                rx_counter <= rx_counter - 1'b1;
            if(tx_counter == 0)
                tx_counter <= div_reg;
            else
                tx_counter <= rx_counter - 1'b1;
        end
    end

    assign tx_clk = tx_counter > div_reg >> 1 ? 1'b1 : 1'b0;
    assign rx_clk = rx_counter > div_reg >> 5 ? 1'b1 : 1'b0;

endmodule