`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
///
/// sfp_rx 收到的 frame 透過 f9pcap_wrap_eth(加上 f9pcap header: Multicast): 打包成 f9pcap 抓到的封包;
/// 然後透過 temac_tx[] 送出;
///
module f9pcap_sfp_to_temac #(
  `include "eth_ip_localparam.vh"
  parameter  PHY_COUNT        = 2,
  parameter  TEMAC_DATA_WIDTH = BYTE_WIDTH,
  localparam TEMAC_KEEP_WIDTH = (TEMAC_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,

  parameter  SFP_COUNT        = 2,
  parameter  SFP_DATA_WIDTH   = 64,
  localparam SFP_KEEP_WIDTH   = (SFP_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,

  parameter  TTS_WIDTH        = 6 * BYTE_WIDTH,

  parameter  FRAME_MIN_LENGTH        = 58 + 32, // 58 = ETH:14 + IP:20 + UDP:8 + f9phdr:16;   32 = 抓到的封包大小;
  parameter  FRAME_MAX_LENGTH        = 1600,
  parameter  F9HDR_BUFFER_LENGTH     = FRAME_MAX_LENGTH * 2,
  parameter  TEMAC_OUT_BUFFER_LENGTH = FRAME_MAX_LENGTH * 64,

  parameter  DEV_ST_BUF_LENGTH = 64,
  localparam DEV_ST_BUF_WIDTH  = DEV_ST_BUF_LENGTH <= 0 ? 1 : (DEV_ST_BUF_LENGTH * BYTE_WIDTH),

  /// 若 SGAP_WIDTH <= 0 表示不支援 sgap pause 功能;
  parameter  SGAP_WIDTH       = 16,
  localparam SGAP_WIDTH_ADJ   = SGAP_WIDTH <= 0 ? 1 : SGAP_WIDTH
)(
  input  wire                       sys_rst_in,
  input  wire[TTS_WIDTH-1:0]        tts_uint_in,
  input  wire[TTS_WIDTH-1:0]        tts_gray_in,

  /// 抓包功能是否啟用?
  input  wire                       is_f9pcap_en,
  input  wire[IP_ADDR_WIDTH -1:0]   f9pcap_mcgroup_addr,
  input  wire[IP_PORT_WIDTH -1:0]   f9pcap_mcgroup_port,
  input  wire[MAC_ADDR_WIDTH-1:0]   f9pcap_src_mac_addr,
  input  wire[IP_ADDR_WIDTH -1:0]   f9pcap_src_ip_addr,
  input  wire[IP_PORT_WIDTH -1:0]   f9pcap_src_port,
  /// 每個 temac_tx 送出後, 間隔多久繼續送出下一個 temac_tx?
  /// 真實間隔時間 = sgap_cfg_in * temac_tx_clk_in(period);
  input  wire[SGAP_WIDTH_ADJ-1:0]   sgap_cfg_in,

  /// sfp_rx 沒有 ready 訊號, sfp_rx_valid_in 開始, 不接受用 ready 控制是否接收;
  input  wire                       sfp_rx_rst_in     [SFP_COUNT-1:0],
  input  wire                       sfp_rx_clk_in     [SFP_COUNT-1:0],
  input  wire                       sfp_rx_valid_in   [SFP_COUNT-1:0],
  input  wire[SFP_DATA_WIDTH-1:0]   sfp_rx_data_in    [SFP_COUNT-1:0],
  input  wire[SFP_KEEP_WIDTH-1:0]   sfp_rx_keep_in    [SFP_COUNT-1:0],
  input  wire                       sfp_rx_last_in    [SFP_COUNT-1:0],
  input  wire                       sfp_rx_err_in     [SFP_COUNT-1:0],

  /// temac_tx 沒有 keep 訊號, temac_tx_valid_out 開始, 所有資料都有效;
  input  wire                       temac_tx_rst_in   [PHY_COUNT-1:0],
  input  wire                       temac_tx_clk_in   [PHY_COUNT-1:0],
  output wire                       temac_tx_valid_out[PHY_COUNT-1:0],
  input  wire                       temac_tx_ready_in [PHY_COUNT-1:0],
  output wire[TEMAC_DATA_WIDTH-1:0] temac_tx_data_out [PHY_COUNT-1:0],
  output wire                       temac_tx_last_out [PHY_COUNT-1:0],
  input  wire                       temac_link_ready  [PHY_COUNT-1:0],

  /// 送出狀態訊息:
  /// dst = f9pcap_mcgroup_addr : f9pcap_mcgroup_port;
  /// src = f9pcap_src_ip_addr  : 16'hffff
  input  wire                       dev_st_rst_in,
  input  wire                       dev_st_clk_in,
  input  wire                       dev_st_valid_in,
  input  wire[DEV_ST_BUF_WIDTH-1:0] dev_st_buf_in
);
// ===============================================================================
genvar phyL;
genvar sfpL;
//--------------------------------------------------------------------------------
localparam                 DEV_ST_ENABLE = (DEV_ST_BUF_LENGTH > 0);
localparam                 DEV_ST_IDX    = SFP_COUNT;
localparam                 SRC_COUNT     = (SFP_COUNT + DEV_ST_ENABLE);
wire                       wrap_tx_rst  [PHY_COUNT-1:0] = temac_tx_rst_in;
wire                       wrap_tx_clk  [PHY_COUNT-1:0] = temac_tx_clk_in;
wire                       wrap_tx_valid[PHY_COUNT-1:0][SRC_COUNT-1:0];
wire                       wrap_tx_ready[PHY_COUNT-1:0][SRC_COUNT-1:0];
wire[TEMAC_DATA_WIDTH-1:0] wrap_tx_data [PHY_COUNT-1:0][SRC_COUNT-1:0];
wire                       wrap_tx_last [PHY_COUNT-1:0][SRC_COUNT-1:0];
//--------------------------------------------------------------------------------
if (DEV_ST_ENABLE) begin
  for (phyL = 0;  phyL < PHY_COUNT;  phyL = phyL + 1) begin : dev_st
    wire                       buf_tx_valid;
    wire                       buf_tx_ready;
    wire[SFP_DATA_WIDTH-1 :0]  buf_tx_data;
    wire[SFP_KEEP_WIDTH-1 :0]  buf_tx_keep;
    wire                       buf_tx_last;
    axis_tx_buffer #(
      .TX_BUF_LENGTH    (DEV_ST_BUF_LENGTH ),
      .OUT_DATA_WIDTH   (SFP_DATA_WIDTH    ),
      .OUT_BYTE_REVERSE (1                 )
    )
    buf_tx_i(
      .rst_in       (dev_st_rst_in   ),
      .clk_in       (dev_st_clk_in   ),
      .tx_start_in  (dev_st_valid_in ),
      .tx_buf_in    (dev_st_buf_in   ),
      .tx_valid_out (buf_tx_valid    ),
      .tx_ready_in  (buf_tx_ready    ),
      .tx_data_out  (buf_tx_data     ),
      .tx_keep_out  (buf_tx_keep     ),
      .tx_last_out  (buf_tx_last     )
    );
    // ------------------------------------------------
    wire                     udp_valid;
    wire[SFP_DATA_WIDTH-1:0] udp_data;
    wire[SFP_KEEP_WIDTH-1:0] udp_keep;
    wire                     udp_last;
    udp_eth_send #(
      .DATA_WIDTH (SFP_DATA_WIDTH )
    )
    to_udp_i (
      .rst_in        (dev_st_rst_in         ),
      .clk_in        (dev_st_clk_in         ),
      .i_valid_in    (buf_tx_valid          ),
      .i_ready_out   (buf_tx_ready          ),
      .i_data_in     (buf_tx_data           ),
      .i_data_len_in (DEV_ST_BUF_LENGTH     ),
      .o_valid_out   (udp_valid             ),
      .o_data_out    (udp_data              ),
      .o_keep_out    (udp_keep              ),
      .o_last_out    (udp_last              ),
      .EthSrcMAC     (f9pcap_src_mac_addr   ),
      .IpSrcAddr     (f9pcap_src_ip_addr    ),
      .IpDstAddr     (f9pcap_mcgroup_addr   ),
      .UdpSrcPort    ({IP_PORT_WIDTH{1'b1}} ),
      .UdpDstPort    (f9pcap_mcgroup_port   )
    );
    // ------------------------------------------------
    sfp_to_temac #(
      .FRAME_MAX_LENGTH  (FRAME_MAX_LENGTH        ),
      .FRAME_MIN_LENGTH  (FRAME_MIN_LENGTH        ),
      .BUFFER_LENGTH     (TEMAC_OUT_BUFFER_LENGTH ),
      .TEMAC_DATA_WIDTH  (TEMAC_DATA_WIDTH        ),
      .SFP_DATA_WIDTH    (SFP_DATA_WIDTH          )
    )
    to_temac_i (
      .sfp_rx_rst_in   (dev_st_rst_in                   ),
      .sfp_rx_clk      (dev_st_clk_in                   ),
      .sfp_rx_valid    (udp_valid                       ),
      .sfp_rx_data     (udp_data                        ),
      .sfp_rx_keep     (udp_keep                        ),
      .sfp_rx_last     (udp_last                        ),
      .is_buf_full_out (                                ),
      .temac_tx_rst_in (wrap_tx_rst  [phyL]             ),
      .temac_tx_clk    (wrap_tx_clk  [phyL]             ),
      .temac_tx_valid  (wrap_tx_valid[phyL][DEV_ST_IDX] ),
      .temac_tx_ready  (wrap_tx_ready[phyL][DEV_ST_IDX] ),
      .temac_tx_data   (wrap_tx_data [phyL][DEV_ST_IDX] ),
      .temac_tx_last   (wrap_tx_last [phyL][DEV_ST_IDX] )
    );
  end
end // if (DEV_ST_ENABLE)
//--------------------------------------------------------------------------------
for (sfpL = 0;  sfpL < SFP_COUNT;  sfpL = sfpL + 1) begin : wrap
  wire                       wrap_rx_rst = sfp_rx_rst_in[sfpL];
  wire                       wrap_rx_clk = sfp_rx_clk_in[sfpL];
  wire                       wrap_rx_valid;
  wire [SFP_DATA_WIDTH-1:0]  wrap_rx_data;
  wire [SFP_KEEP_WIDTH-1:0]  wrap_rx_keep;
  wire                       wrap_rx_last;
  wire[PHY_COUNT-1:0]        wrap_outbuf_full;
  f9pcap_wrap_eth #(
    .F9HDR_BUFFER_LENGTH (F9HDR_BUFFER_LENGTH ),
    .DATA_WIDTH          (SFP_DATA_WIDTH      ),
    .TTS_WIDTH           (TTS_WIDTH           )
  )
  f9pcap_wrap_i (
    .rst_in          (wrap_rx_rst            ),
    .clk_in          (wrap_rx_clk            ),
    .i_valid_in      (sfp_rx_valid_in[sfpL]  ),
    .i_data_in       (sfp_rx_data_in [sfpL]  ),
    .i_keep_in       (sfp_rx_keep_in [sfpL]  ),
    .i_last_in       (sfp_rx_last_in [sfpL]  ),
    .i_frame_err_in  (sfp_rx_err_in  [sfpL]  ),
    .outbuf_full_in  (|wrap_outbuf_full      ),
    .o_valid_out     (wrap_rx_valid          ),
    .o_data_out      (wrap_rx_data           ),
    .o_keep_out      (wrap_rx_keep           ),
    .o_last_out      (wrap_rx_last           ),

    .tts_gray_in     (tts_gray_in            ),
    .port_id_in      (sfpL[BYTE_WIDTH-1:0]   ),
    .EthSrcMAC       (f9pcap_src_mac_addr    ),
    .IpSrcAddr       (f9pcap_src_ip_addr     ),
    .IpDstAddr       (f9pcap_mcgroup_addr    ),
    .UdpSrcPort      (f9pcap_src_port        ),
    .UdpDstPort      (f9pcap_mcgroup_port    )
  );
  // -------------------------------------------------------
  for (phyL = 0;  phyL < PHY_COUNT;  phyL = phyL + 1) begin : cdc
    wire sfp_rx_rst_w;
    sync_reset sync_sfp_rx_rst_i(
      .clk     (wrap_rx_clk  ),
      .rst_in  (wrap_rx_rst | ~is_f9pcap_en | ~temac_link_ready[phyL]),
      .rst_out (sfp_rx_rst_w )
    );
    // -----
    sfp_to_temac #(
      .FRAME_MAX_LENGTH  (FRAME_MAX_LENGTH        ),
      .FRAME_MIN_LENGTH  (FRAME_MIN_LENGTH        ),
      .BUFFER_LENGTH     (TEMAC_OUT_BUFFER_LENGTH ),
      .TEMAC_DATA_WIDTH  (TEMAC_DATA_WIDTH        ),
      .SFP_DATA_WIDTH    (SFP_DATA_WIDTH          )
    )
    to_temac_i (
      .sfp_rx_rst_in   (sfp_rx_rst_w                  ),
      .sfp_rx_clk      (wrap_rx_clk                   ),
      .sfp_rx_valid    (wrap_rx_valid                 ),
      .sfp_rx_data     (wrap_rx_data                  ),
      .sfp_rx_keep     (wrap_rx_keep                  ),
      .sfp_rx_last     (wrap_rx_last                  ),
      .is_buf_full_out (wrap_outbuf_full [phyL]       ),
      .temac_tx_rst_in (wrap_tx_rst      [phyL]       ),
      .temac_tx_clk    (wrap_tx_clk      [phyL]       ),
      .temac_tx_valid  (wrap_tx_valid    [phyL][sfpL] ),
      .temac_tx_ready  (wrap_tx_ready    [phyL][sfpL] ),
      .temac_tx_data   (wrap_tx_data     [phyL][sfpL] ),
      .temac_tx_last   (wrap_tx_last     [phyL][sfpL] )
    );
  end
end
//////////////////////////////////////////////////////////////////////////////////
for (phyL = 0;  phyL < PHY_COUNT;  phyL = phyL + 1) begin : temac_out
  wire   sgap_pause;
  if (SGAP_WIDTH <= 0) begin
    assign sgap_pause = 0;
  end else begin
    count_down #(
      .COUNTER_WIDTH (SGAP_WIDTH )
    )
    count_down_i(
      .rst_in          (wrap_tx_rst       [phyL] ),
      .clk_in          (wrap_tx_clk       [phyL] ),
      .count_start_in  (temac_tx_last_out [phyL] ),
      .counter_init_in (sgap_cfg_in              ),
      .counter_out     (                         ),
      .trigger_out     (sgap_pause               )
    );
  end
  // -------------------------------------------------------
  axis_n_to_one #(
    .N_COUNT    (SRC_COUNT        ),
    .DATA_WIDTH (TEMAC_DATA_WIDTH ),
    .USE_PAUSE  (SGAP_WIDTH > 0   )
  )
  sfpN_to_temac_i (
    .clk_in           (wrap_tx_clk       [phyL] ),
    .n_axis_valid_in  (wrap_tx_valid     [phyL] ),
    .n_axis_ready_out (wrap_tx_ready     [phyL] ),
    .n_axis_data_in   (wrap_tx_data      [phyL] ),
    .n_axis_last_in   (wrap_tx_last      [phyL] ),
    .n_axis_keep_in   (                         ),
    .o_pause_in       (sgap_pause               ),
    .o_axis_valid_out (temac_tx_valid_out[phyL] ),
    .o_axis_ready_in  (temac_tx_ready_in [phyL] ),
    .o_axis_data_out  (temac_tx_data_out [phyL] ),
    .o_axis_last_out  (temac_tx_last_out [phyL] ),
    .o_axis_keep_out  (                         )
  );
end
// ===============================================================================
endmodule
//////////////////////////////////////////////////////////////////////////////////
