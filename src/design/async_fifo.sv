module async_fifo #(
        parameter int DEPTH=16, 
        parameter type DATA_T = bit [7:0],
        parameter string FIFO_NAME = "",
        parameter int DEBUG = 1
    )(
        input  logic                     rclk,
        input  logic                     wclk,
        input  logic                     rst,
        input  logic                     i_clear,
        input  logic                     i_wr_en,    // Write enable
        input  logic                     i_rd_en,    // Read enable
        input  DATA_T                    i_data,     // Data written into FIFO
        output DATA_T                    o_data,     // Data read from FIFO
        output logic                     o_empty,    // FIFO is empty when high
        output logic                     o_full     // FIFO is full when high,
    );

    //one extra bit for computing full and empty
    logic [$clog2(DEPTH):0] wptr, wgray, wsync1, wsync2;
    logic [$clog2(DEPTH):0] rptr, rgray, rsync1, rsync2; 
    logic w_empty, w_full;
    logic nreset;
    DATA_T fifo [DEPTH];

    logic master_reset;
    assign master_reset = (rst || i_clear);

    always_ff@(posedge rclk, posedge master_reset) begin
        if(master_reset) 
            {wsync2,wsync1} <= 0; 
        else
            {wsync2,wsync1} <= {wsync1, wgray}; 
    end

    always_ff@(posedge wclk, posedge master_reset) begin
        if(master_reset) 
            {rsync2,rsync1} <= 0; 
        else
            {rsync2,rsync1} <= {rsync1, rgray}; 
    end

    always_ff @(posedge wclk, posedge master_reset) begin
        if (master_reset) begin
            wptr <= 0;
            wgray <= 0;
            o_full <= 0;
        end
        else begin
            logic [$clog2(DEPTH):0] wbin; 
            wbin = wptr + 1'(i_wr_en & !o_full); 
            wptr <= wbin;
            wgray <= (wbin >> 1) ^ wbin;
            fifo[wptr[$clog2(DEPTH)-1:0]] <= i_data;
            o_full <= w_full;
        end 
    end

    always_ff @(posedge rclk, posedge master_reset) begin
        if (master_reset) begin
            rptr <= 0;
            rgray <= 0;
            o_empty <= 0;
            o_data <= 0;
        end
        else begin 
            logic [$clog2(DEPTH):0] rbin; 
            rbin = rptr + 1'(i_rd_en & !o_empty); 
            rptr <= rbin;
            rgray <= (rbin >> 1) ^ rbin;
            o_empty <= w_empty;
            o_data <= fifo[rptr[$clog2(DEPTH)-1:0]];
        end
    end

    //technique seen @sunburst design
    assign w_full  = rsync2 == {~wgray[$clog2(DEPTH)], wgray[$clog2(DEPTH)-1:0]};
    assign w_empty = rgray == wsync2;

    initial begin
        if (DEBUG)
            $monitor("[%0t] [FIFO %s] wr_en=%0b din=0x%0h rd_en=%0b dout=0x%0h empty=%0b full=%0b", $time, FIFO_NAME, i_wr_en, i_data, i_rd_en, o_data, o_empty, o_full);
    end
    
endmodule

