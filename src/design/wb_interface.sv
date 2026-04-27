interface wishboneIf #(
        parameter type DATA_T = bit[31:0],
        parameter int ADDR_WIDTH = 10,
        parameter int DATA_WIDTH = $bits(DATA_T),
        parameter int SELECT_WIDTH = (DATA_WIDTH/8)
    )(
        input wire clk
    );

    logic [ADDR_WIDTH-1:0]   addr;   // ADR_I() address
    DATA_T                   data_wr;   // DAT_I() data for write access
    DATA_T                   data_rd;   // DAT_O() data for read access
    logic                    we;    // WE_I write enable input
    logic [SELECT_WIDTH-1:0] sel;   // SEL_I() select input
    logic                    stb;   // STB_I strobe input
    logic                    ack;   // ACK_O acknowledge output
    logic                    stall;
    logic                    cyc;    // CYC_I cycle input
    logic                    err;

    modport Slave (
        //inputs from Master
        input addr,
        input data_wr,
        input we,
        input sel,
        input stb,
        input cyc,
        //Outputs to Master
        output data_rd,
        output ack,
        output stall,
        output err
    );

    modport Master (
        //outputs to Slave
        output addr,
        output data_wr,
        output we,
        output sel,
        output stb,
        output cyc,
        //inputs from Slave
        input data_rd,
        input ack,
        input stall,
        input err
    );

    //functions for synthesis purposes
    function automatic void wb_write_req(logic [ADDR_WIDTH-1:0] address, DATA_T data);
        addr = address;
        data_wr = data;
        we  = '1;
        sel = '1;
        stb = '1;
        cyc = '1;    
    endfunction

    function automatic void wb_read_req(logic [ADDR_WIDTH-1:0] address);
        addr = address;
        we  = '0;
        sel = '1;
        stb = '1;
        cyc = '1;
        data_wr = '0;    
    endfunction

    function automatic void wb_end_req();
        addr = '0;
        data_wr = '0;
        we  = '0;
        sel = '0;
        stb = '0;
        cyc = '0;
    endfunction

    //Tasks for simulation purposes
    task automatic MasterWrite (input logic[ADDR_WIDTH-1:0] waddr, input DATA_T wdata);
        if(stall)
            $display("Downstream module is busy, waiting for it to become ready before sending write request");
        @(posedge clk iff stall == '0)
        addr = waddr;
        data_wr = wdata;
        we  = '1;
        sel = '1;
        stb = '1;
        cyc = '1;
        @(posedge clk);
        we  = '0;
        stb = '0;
        if (~ack)
            wait(ack == 1'b1);
        cyc = '0;
        $display("Received ack on write request @address %h with data %h", waddr, wdata);
    endtask

    task automatic MasterRead (input logic[ADDR_WIDTH-1:0] raddr,output DATA_T rdata);
        if(stall)
            $display("Downstream module is busy, waiting for it to become ready before sending write request");
        @(posedge clk iff stall == '0)
        addr = raddr;
        data_wr = '0;
        we  = '0;
        sel = '1;
        stb = '1;
        cyc = '1;
        @(posedge clk);
        stb = '0;
        if (~ack)
            wait(ack == 1'b1);
        cyc = '0;
        rdata = data_rd;
        $display("Received ack on read request @address %h with data %h", raddr, rdata);
    endtask

endinterface //interfacename