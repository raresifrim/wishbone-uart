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
    .data_in(data + 1'b1),
    .data_out(data),
    .rx_err()    
  );
  
endmodule
