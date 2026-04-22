`timescale 1ns/1ps

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

    localparam AW = $clog2(DEPTH); 

    //one extra bit for computing full and empty
    logic [AW:0] wptr, wgray, wsync1, wsync2;
    logic [AW:0] rptr, rgray, rsync1, rsync2; 
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
        end
        else begin
            logic [AW:0] wbin; 
            wbin = wptr + 1'(i_wr_en & !o_full); 
            wptr <= wbin;
            wgray <= (wbin >> 1) ^ wbin;
            //make sure we don't actually overwrite otherwise we might loose early data that wasn't sent
            if(i_wr_en & !o_full)
                fifo[wptr[AW-1:0]] <= i_data;
        end 
    end

    always_ff @(posedge rclk, posedge master_reset) begin
        if (master_reset) begin
            rptr <= 0;
            rgray <= 0;
            o_data <= 0;
        end
        else begin 
            logic [AW:0] rbin; 
            rbin = rptr + 1'(i_rd_en & !o_empty); 
            rptr <= rbin;
            rgray <= (rbin >> 1) ^ rbin;
            o_data <= fifo[rptr[AW-1:0]];
        end
    end

    //technique seen @sunburst design
    assign o_full = (wgray[AW:AW-1] == ~rsync2[AW:AW-1])
				&& (wgray[AW-2:0]==rsync2[AW-2:0]);
    assign o_empty = (rgray == wsync2);

    initial begin
        if (DEBUG)
            $monitor("[%0t] [FIFO %s] wr_en=%0b din=0x%0h rd_en=%0b dout=0x%0h empty=%0b full=%0b", $time, FIFO_NAME, i_wr_en, i_data, i_rd_en, o_data, o_empty, o_full);
    end
    
endmodule

