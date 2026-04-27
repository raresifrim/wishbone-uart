module top_hard_uart_fpga#(
  parameter int DATA_FRAME = 8,
  parameter int BAUD_RATE = 9600,
  parameter int CLK_FREQ_MHZ = 12,
  parameter string PARITY_BIT = "NONE" //NONE/ODD/EVEN
)(
  input logic sys_clk,
  input logic reset,
  input logic rx,
  output logic tx,
  output logic rx_done,
  output logic tx_done
);

  logic [7:0] data;

  hard_uart #(
    .DATA_FRAME(DATA_FRAME),
    .BAUD_RATE(BAUD_RATE),
    .CLK_FREQ_MHZ(CLK_FREQ_MHZ),
    .PARITY_BIT(PARITY_BIT)
  ) uart_loopback (
    .sys_clk(sys_clk),
    .reset(reset),
    .rx(rx),
    .tx(tx),
    .tx_done(tx_done),
    .rx_done(rx_done),
    .tx_start(rx_done),
    .data_in(data),
    .data_out(data),
    .rx_err()    
  );
  
endmodule


module top_soft_uart_fpga#(
  parameter int BAUD_RATE = 9600,
  parameter int CLK_FREQ_MHZ = 12
)(
  input logic sys_clk,
  input logic reset,
  input logic rx,
  output logic tx,
  output logic rx_done,
  output logic tx_done
);

  localparam bit   [31:0] DIVIDER = (CLK_FREQ_MHZ * (10**6)) / BAUD_RATE;
  localparam logic [31:0] ADDR_TX_BUF    = 32'h0;
  localparam logic [31:0] ADDR_RX_BUF    = 32'h4;
  localparam logic [31:0] ADDR_BAUD_DIV  = 32'h8;
  localparam logic [31:0] ADDR_CTRL_EN   = 32'hA;
  
  wishboneIf#(.DATA_T(bit[31:0]), .ADDR_WIDTH(32)) wbIf(sys_clk);

  soft_uart uart_loopback(
    .sys_clk(sys_clk),
    .reset(reset),
    .rx(rx),
    .tx(tx),
    .wbif(wbIf.Slave),
    .rx_done(rx_done),
    .tx_done(tx_done)
  );

    typedef enum bit[1:0] {INIT_BAUD, ENABLE, WAIT, READ_AND_WRITE} fsm;
    fsm current = INIT_BAUD, next;

    always_ff@(posedge sys_clk) begin
      if(reset)
        current <= INIT_BAUD;
      else
        current <= next;
    end

    always_comb begin

      unique case(current)
        INIT_BAUD: begin
          wbIf.wb_write_req(ADDR_BAUD_DIV, DIVIDER);
          next = ENABLE;
        end

        ENABLE: begin
          wbIf.wb_write_req(ADDR_CTRL_EN, 32'h7); //Enable Baud Gen, TX, and RX
          next = WAIT;
        end

        WAIT: begin
          if(rx_done) begin
            next = READ_AND_WRITE;
            wbIf.wb_read_req(ADDR_RX_BUF);
          end else begin
            wbIf.wb_end_req();
            next = WAIT;
          end
        end

        READ_AND_WRITE: begin
          if(wbIf.ack == 1) begin
            wbIf.wb_write_req(ADDR_TX_BUF, wbIf.data_rd);
            next = WAIT;
          end
          else begin
            wbIf.wb_end_req();
            next = READ_AND_WRITE;
          end
        end
        default: begin
          wbIf.wb_end_req();
          next = WAIT;
        end
      endcase
    end
  
endmodule