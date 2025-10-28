`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
module f9pcap_tgbaser_axis #(
  /// if (XCVR_QPLL_MASTER) 輸出 qpll...out
  /// else                  使用 qpll...in
  parameter  XCVR_QPLL_MASTER   = 1,
  parameter  AXIS_DATA_WIDTH    = 64,
  parameter  AXIS_KEEP_WIDTH    = AXIS_DATA_WIDTH / 8,
  parameter  COUNT_125US        = 125000/6.4,
  parameter  EXAMPLE_SIMULATION = 0,
  //  0: for ULTRASCALE xcvr;
  // 32: for 7SERIES xcvr;
  parameter  TXSEQUENCE_PAUSE     = 0,
  parameter  TXSEQUENCE_ODD_PAUSE = (TXSEQUENCE_PAUSE == 65 ? 1'b1 : 1'b0),
  localparam TXSEQUENCE_WIDTH     = TXSEQUENCE_PAUSE==0 ? 1 : $clog2(TXSEQUENCE_PAUSE+1)
)(
  // xcvr FREERUN_FREQUENCY: 100M
  input  xcvr_ctrl_clk,
  input  xcvr_ctrl_rst,

  // 156.25M: 必須先將 p/n 緩衝, 然後此 clk 可以驅動多組 [Quad XCVR];
  // - "7SERIES":    必須先將 p/n 使用 IBUFDS_GTE2 緩衝,
  // - "ULTRASCALE": 必須先將 p/n 使用 IBUFDS_GTE4 緩衝,
  input  xcvr_gt_refclk_in,
  output xcvr_gt_powergood_out,
  // used when XCVR_QPLL_MASTER == 1
  output xcvr_qpll_lock_out,
  output xcvr_qpll_clk_out,
  output xcvr_qpll_refclk_out,
  // used when XCVR_QPLL_MASTER == 0
  input  xcvr_qpll_lock_in,
  input  xcvr_qpll_clk_in,
  input  xcvr_qpll_refclk_in,
  output xcvr_qpll_reset_out,
  // ------------------------
  output xcvr_txusrclk_to_slave,
  output xcvr_txusrclk2_to_slave,
  input  xcvr_txusrclk_from_master,
  input  xcvr_txusrclk2_from_master,

  // from SFP.
  input  xcvr_rx_p,
  input  xcvr_rx_n,
  output xcvr_tx_p,
  output xcvr_tx_n,

  // to led: 1=ready; = rx_status & rx_block_lock;
  output st_xcvr_ready,
  output xcvr_rx_high_ber,
  input  dont_cnt_bad_block,
  input  dont_cnt_high_ber,

  output                         rx_axis_rst_out,
  output                         rx_axis_clk_out,
  output                         rx_axis_tvalid,
  output[AXIS_DATA_WIDTH-1:0]    rx_axis_tdata,
  output[AXIS_KEEP_WIDTH-1:0]    rx_axis_tkeep,
  output                         rx_axis_tlast,

  // 來自 src SFP rx 的內容, 直接丟給 this SFP tx 轉發;
  input                          tx_axis_rst_in,
  input                          tx_axis_clk_in,
  input                          tx_axis_tvalid,
  input [AXIS_DATA_WIDTH-1:0]    tx_axis_tdata,
  input [AXIS_KEEP_WIDTH-1:0]    tx_axis_tkeep,
  input                          tx_axis_tlast
);
//////////////////////////////////////////////////////////////////////////////////
//
// tx_axis_*         => src_tx_axis_*_cdc    cross clock domain: tx_axis_clk_in => dst_tx_axis_clk
// src_tx_axis_*_cdc => src_tx_axis_*_b      buffered, 緩衝數量足夠時才開始傳送, 避免 TXSEQUENCE_PAUSE(來源端也有類似的暫停);
// src_tx_axis_*_b   => dst_tx_axis_*
//
wire                       dst_tx_axis_rst;
wire                       dst_tx_axis_clk;
reg                        dst_tx_axis_tvalid;
wire                       dst_tx_axis_tready;
wire[AXIS_DATA_WIDTH-1:0]  dst_tx_axis_tdata;
wire[AXIS_KEEP_WIDTH-1:0]  dst_tx_axis_tkeep;
wire                       dst_tx_axis_tlast;
// -------------------------------------------------------------------------------
tgbaser_axis #(
  .XCVR_QPLL_MASTER     (XCVR_QPLL_MASTER     ),
  .AXIS_DATA_WIDTH      (AXIS_DATA_WIDTH      ),
  .AXIS_KEEP_WIDTH      (AXIS_KEEP_WIDTH      ),
  .COUNT_125US          (COUNT_125US          ),
  .ENABLE_PADDING       (0                    ),
  .EXAMPLE_SIMULATION   (EXAMPLE_SIMULATION   ),
  .TXSEQUENCE_PAUSE     (TXSEQUENCE_PAUSE     ),
  .TXSEQUENCE_ODD_PAUSE (TXSEQUENCE_ODD_PAUSE )
)
tgbaser_axis_i (
  .xcvr_ctrl_clk              (xcvr_ctrl_clk              ),
  .xcvr_ctrl_rst              (xcvr_ctrl_rst              ),
  .xcvr_gt_refclk_in          (xcvr_gt_refclk_in          ),
  .xcvr_gt_powergood_out      (xcvr_gt_powergood_out      ),
  .xcvr_qpll_lock_out         (xcvr_qpll_lock_out         ),
  .xcvr_qpll_clk_out          (xcvr_qpll_clk_out          ),
  .xcvr_qpll_refclk_out       (xcvr_qpll_refclk_out       ),
  .xcvr_qpll_lock_in          (xcvr_qpll_lock_in          ),
  .xcvr_qpll_clk_in           (xcvr_qpll_clk_in           ),
  .xcvr_qpll_refclk_in        (xcvr_qpll_refclk_in        ),
  .xcvr_qpll_reset_out        (xcvr_qpll_reset_out        ),
  .xcvr_txusrclk_to_slave     (xcvr_txusrclk_to_slave     ),
  .xcvr_txusrclk2_to_slave    (xcvr_txusrclk2_to_slave    ),
  .xcvr_txusrclk_from_master  (xcvr_txusrclk_from_master  ),
  .xcvr_txusrclk2_from_master (xcvr_txusrclk2_from_master ),
  .xcvr_rx_p                  (xcvr_rx_p                  ),
  .xcvr_rx_n                  (xcvr_rx_n                  ),
  .xcvr_tx_p                  (xcvr_tx_p                  ),
  .xcvr_tx_n                  (xcvr_tx_n                  ),
  .st_xcvr_ready              (st_xcvr_ready              ),
  .xcvr_rx_high_ber           (xcvr_rx_high_ber           ),
  .dont_cnt_bad_block         (dont_cnt_bad_block         ),
  .dont_cnt_high_ber          (dont_cnt_high_ber          ),
  .rx_axis_rst                (rx_axis_rst_out            ),
  .rx_axis_clk                (rx_axis_clk_out            ),
  .rx_axis_tvalid             (rx_axis_tvalid             ),
  .rx_axis_tdata              (rx_axis_tdata              ),
  .rx_axis_tkeep              (rx_axis_tkeep              ),
  .rx_axis_tlast              (rx_axis_tlast              ),
  .rx_axis_tuser              (                           ),
  .tx_axis_rst                (dst_tx_axis_rst            ),
  .tx_axis_clk                (dst_tx_axis_clk            ),
  .tx_axis_tready             (dst_tx_axis_tready         ),
  .tx_axis_tvalid             (dst_tx_axis_tvalid         ),
  .tx_axis_tdata              (dst_tx_axis_tdata          ),
  .tx_axis_tkeep              (dst_tx_axis_tkeep          ),
  .tx_axis_tlast              (dst_tx_axis_tlast          ),
  .tx_axis_tuser              (                           )
);
//////////////////////////////////////////////////////////////////////////////////
wire                        src_tx_axis_rst = tx_axis_rst_in;
wire                        src_tx_axis_clk = tx_axis_clk_in;
wire                        src_tx_axis_rst_cdc;
wire                        src_tx_axis_valid_cdc;
wire[AXIS_DATA_WIDTH-1:0]   src_tx_axis_tdata_cdc;
wire[AXIS_KEEP_WIDTH-1:0]   src_tx_axis_tkeep_cdc;
wire                        src_tx_axis_tlast_cdc;
cdc_fifo #(
  .DATA_WIDTH (AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH + 1 ),
  .FIFO_DEPTH (16                                    )
)
fwd_cdc_i(
  .rst           (src_tx_axis_rst       ),
  .wr_rst_out    (                      ),
  .wr_clk        (src_tx_axis_clk       ),
  .wr_din_push   (tx_axis_tvalid & (|tx_axis_tkeep) ),
  .wr_din_data   ({tx_axis_tdata,         tx_axis_tkeep,         tx_axis_tlast}         ),
  .rd_dout_data  ({src_tx_axis_tdata_cdc, src_tx_axis_tkeep_cdc, src_tx_axis_tlast_cdc} ),
  .rd_dout_valid (src_tx_axis_valid_cdc ),
  .rd_rst_out    (src_tx_axis_rst_cdc   ),
  .rd_clk        (dst_tx_axis_clk       )
);
// -------------------------------------------------
localparam  FWD_FIFO_DCOUNT = 8;
localparam  FWD_FIFO_DWIDTH = $clog2(FWD_FIFO_DCOUNT+1);
wire                       fwd_tx_fifo_pop = dst_tx_axis_tvalid & dst_tx_axis_tready;
wire                       fwd_tx_fifo_empty;
wire[FWD_FIFO_DWIDTH-1:0]  fwd_tx_fifo_count;
f9fifo #(
  .DATA_WIDTH    (AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH + 1 ),
  .COUNT         (FWD_FIFO_DCOUNT                       ),
  .EN_DATA_COUNT (1                                     )
)
fwd_fifo_i(
  .aclk          (dst_tx_axis_clk       ),
  .rstn          (~src_tx_axis_rst_cdc  ),
  .wr_push       (src_tx_axis_valid_cdc ),
  .wr_data       ({src_tx_axis_tdata_cdc, src_tx_axis_tkeep_cdc, src_tx_axis_tlast_cdc} ),
  .rd_data       ({dst_tx_axis_tdata,     dst_tx_axis_tkeep,     dst_tx_axis_tlast}     ),
  .rd_pop        (fwd_tx_fifo_pop       ),
  .is_empty      (fwd_tx_fifo_empty     ),
  .is_full       (                      ),
  .data_count    (fwd_tx_fifo_count     )
);
// -------------------------------------------------
always @(posedge dst_tx_axis_clk) begin
  dst_tx_axis_tvalid <= dst_tx_axis_tvalid;
  if (dst_tx_axis_tvalid) begin
    if (dst_tx_axis_tlast && dst_tx_axis_tready) begin
      dst_tx_axis_tvalid <= 0;
    end
  end else if (fwd_tx_fifo_count > 3) begin
    dst_tx_axis_tvalid <= 1;
  end
  //-----
  if (fwd_tx_fifo_empty) begin
    dst_tx_axis_tvalid <= 0;
  end
end
//////////////////////////////////////////////////////////////////////////////////
endmodule
