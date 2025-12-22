`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
///
/// sfp_rx 收到的 frame 透過 f9pcap_wrap_eth(加上 f9pcap header: Multicast): 打包成 f9pcap 抓到的封包;
/// 然後透過 temac_tx[] 送出;
///
module f9pcap_sfp_to_temac #(
  `include "eth_ip_localparam.vh"
  `include "localparam_recover.vh"

  parameter  PHY_COUNT        = 2,
  parameter  TEMAC_DATA_WIDTH = BYTE_WIDTH,
  localparam TEMAC_KEEP_WIDTH = (TEMAC_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,

  parameter  SFP_COUNT        = 2,
  parameter  SFP_DATA_WIDTH   = 64,
  localparam SFP_KEEP_WIDTH   = (SFP_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,

  parameter  TTS_WIDTH        = 7 * BYTE_WIDTH,

  parameter  FRAME_MIN_LENGTH        = 58 + 32, // 58 = ETH:14 + IP:20 + UDP:8 + f9phdr:16;   32 = 抓到的封包大小;
  parameter  FRAME_MAX_LENGTH        = 1600,
  parameter  F9HDR_BUFFER_LENGTH     = FRAME_MAX_LENGTH * 2,
  parameter  TEMAC_OUT_BUFFER_LENGTH = FRAME_MAX_LENGTH * 64,

  parameter  DEV_ST_BUF_LENGTH = 64,
  localparam DEV_ST_BUF_WIDTH  = DEV_ST_BUF_LENGTH <= 0 ? 1 : (DEV_ST_BUF_LENGTH * BYTE_WIDTH),

  /// 若 SGAP_WIDTH <= 0 表示不支援 sgap pause 功能;
  parameter  SGAP_WIDTH       = 16,
  localparam SGAP_WIDTH_ADJ   = SGAP_WIDTH <= 0 ? 1 : SGAP_WIDTH,

  parameter  DRAM_APP_CMD_WIDTH   = 3,
  parameter  DRAM_ADDR_WIDTH      = 0,
  parameter  DRAM_BURST_SIZE_BITS = 64,
  parameter  DRAM_APP_DATA_LENGTH = 64,
  localparam DRAM_APP_DATA_WIDTH  = DRAM_APP_DATA_LENGTH * BYTE_WIDTH,
  parameter  IS_USE_DRAM_BUFFER   = (DRAM_ADDR_WIDTH > 0 && DRAM_APP_DATA_WIDTH > 0),

  parameter  ILA_DEBUG = 0
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
  input  wire                             dev_st_rst_in,
  input  wire                             dev_st_clk_in,
  input  wire                             dev_st_valid_in,
  input  wire[DEV_ST_BUF_WIDTH-1:0]       dev_st_buf_in,
  output wire[DEV_ST_RECOVER_INFO_W-1:0]  dev_st_recover_info_out,
  output wire                             dev_st_force_resend_out,


  input  wire                           dram_rst,
  input  wire                           dram_clk,
  input  wire                           dram_init_calib_complete,
  output wire                           dram_test_err_out,
  output reg [DRAM_APP_CMD_WIDTH-1  :0] dram_app_cmd,
  output reg                            dram_app_en,
  input  wire                           dram_app_rdy,
  output reg [DRAM_ADDR_WIDTH-1     :0] dram_addr,
  output reg [DRAM_APP_DATA_WIDTH-1 :0] dram_app_wdf_data,
  output wire                           dram_app_wdf_end,
  output wire[DRAM_APP_DATA_LENGTH-1:0] dram_app_wdf_mask,
  output reg                            dram_app_wdf_wren,
  input  wire                           dram_app_wdf_rdy,
  input  wire[DRAM_APP_DATA_WIDTH-1 :0] dram_app_rd_data,
  input  wire                           dram_app_rd_data_end,
  input  wire                           dram_app_rd_data_valid,

  output wire                           f9mg_recover_req_pop_out,
  input  wire                           f9mg_recover_req_valid_in,
  input  wire[RECOVER_REQ_WIDTH-1:0]    f9mg_recover_req_data_in
);
// ===============================================================================
genvar phyL;
genvar sfpL;
//--------------------------------------------------------------------------------
localparam                 DEV_ST_ENABLE        = (DEV_ST_BUF_LENGTH > 0);
localparam                 DEV_ST_IDX           = IS_USE_DRAM_BUFFER ? 1 : SFP_COUNT;
localparam                 WRAP_TX_DRAM_OUT_IDX = IS_USE_DRAM_BUFFER ? 0 : -1;
localparam                 SRC_COUNT            =(IS_USE_DRAM_BUFFER ? 1 : SFP_COUNT) + DEV_ST_ENABLE;
wire                       wrap_tx_rst  [PHY_COUNT-1:0] = temac_tx_rst_in;
wire                       wrap_tx_clk  [PHY_COUNT-1:0] = temac_tx_clk_in;
wire                       wrap_tx_valid[PHY_COUNT-1:0][SRC_COUNT-1:0];
wire                       wrap_tx_ready[PHY_COUNT-1:0][SRC_COUNT-1:0];
wire[TEMAC_DATA_WIDTH-1:0] wrap_tx_data [PHY_COUNT-1:0][SRC_COUNT-1:0];
// wire                    wrap_tx_keep [PHY_COUNT-1:0][SRC_COUNT-1:0];// temac(phy) 的 data 只有 1 byte, 所以不需要 keep;
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
      .rst_in          (wrap_tx_rst  [phyL] | dev_st_rst_in ),
      .sfp_rx_clk      (dev_st_clk_in                   ),
      .sfp_rx_valid    (udp_valid                       ),
      .sfp_rx_data     (udp_data                        ),
      .sfp_rx_keep     (udp_keep                        ),
      .sfp_rx_last     (udp_last                        ),
      .is_buf_full_out (                                ),
      .temac_tx_rst_out(                                ),
      .temac_tx_clk    (wrap_tx_clk  [phyL]             ),
      .temac_tx_valid  (wrap_tx_valid[phyL][DEV_ST_IDX] ),
      .temac_tx_ready  (wrap_tx_ready[phyL][DEV_ST_IDX] ),
      .temac_tx_data   (wrap_tx_data [phyL][DEV_ST_IDX] ),
      .temac_tx_last   (wrap_tx_last [phyL][DEV_ST_IDX] )
    );
  end
end // if (DEV_ST_ENABLE)
//////////////////////////////////////////////////////////////////////////////////
if (!IS_USE_DRAM_BUFFER) begin
  assign dev_st_recover_info_out = 0;
  assign dev_st_force_resend_out = 0;
  //------------------------------------------------------------------------------
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
      .TTS_WIDTH           (TTS_WIDTH           ),
      .SAME_IO_CLK         (1                   ),
      .I_DATA_WIDTH        (SFP_DATA_WIDTH      ),
      .O_DATA_WIDTH        (SFP_DATA_WIDTH      )
    )
    f9pcap_wrap_i (
      .rst_in          (wrap_rx_rst            ),
      .i_clk_in        (wrap_rx_clk            ),
      .i_valid_in      (sfp_rx_valid_in[sfpL]  ),
      .i_data_in       (sfp_rx_data_in [sfpL]  ),
      .i_keep_in       (sfp_rx_keep_in [sfpL]  ),
      .i_last_in       (sfp_rx_last_in [sfpL]  ),
      .i_frame_err_in  (sfp_rx_err_in  [sfpL]  ),
      .outbuf_full_in  (|wrap_outbuf_full      ),
      .o_rst_out       (                       ),
      .o_clk_in        (wrap_rx_clk            ),
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
      sync_reset
      sync_sfp_rx_rst_i(
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
        .rst_in          (wrap_tx_rst      [phyL] | sfp_rx_rst_w ),
        .sfp_rx_clk      (wrap_rx_clk                   ),
        .sfp_rx_valid    (wrap_rx_valid                 ),
        .sfp_rx_data     (wrap_rx_data                  ),
        .sfp_rx_keep     (wrap_rx_keep                  ),
        .sfp_rx_last     (wrap_rx_last                  ),
        .is_buf_full_out (wrap_outbuf_full [phyL]       ),
        .temac_tx_rst_out(                              ),
        .temac_tx_clk    (wrap_tx_clk      [phyL]       ),
        .temac_tx_valid  (wrap_tx_valid    [phyL][sfpL] ),
        .temac_tx_ready  (wrap_tx_ready    [phyL][sfpL] ),
        .temac_tx_data   (wrap_tx_data     [phyL][sfpL] ),
        .temac_tx_last   (wrap_tx_last     [phyL][sfpL] )
      );
    end
  end
  //------------------------------------------------------------------------------
  for (phyL = 0;  phyL < PHY_COUNT;  phyL = phyL + 1) begin : to_temac
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
//////////////////////////////////////////////////////////////////////////////////
end else begin // DRAM_ADDR_WIDTH != 0: use dram buffer //////////////////////////
  assign dram_test_err_out = 0;
  // ----------------------------------------
  localparam F9PHDR_SPL_LENGTH = 8;
  localparam F9PHDR_SPL_WIDTH  = F9PHDR_SPL_LENGTH * BYTE_WIDTH;
  localparam F9PHDR_WIDTH      = F9PHDR_SPL_WIDTH * 2;
  localparam F9PHDR_LENGTH     = F9PHDR_WIDTH / BYTE_WIDTH;
  localparam F9P_LEN_WIDTH     = 16;
  localparam F9P_SRC_COUNT     = SFP_COUNT;
  localparam TO_DRAM_DATA_W    = DRAM_APP_DATA_WIDTH;
  localparam TO_DRAM_KEEP_W    = DRAM_APP_DATA_LENGTH;
  wire                     dram_buf_full;
  wire                     f9p_rx_valid[F9P_SRC_COUNT-1:0];
  wire                     f9p_rx_ready[F9P_SRC_COUNT-1:0];
  wire[TO_DRAM_DATA_W-1:0] f9p_rx_data [F9P_SRC_COUNT-1:0];
  wire[TO_DRAM_KEEP_W-1:0] f9p_rx_keep [F9P_SRC_COUNT-1:0];
  wire                     f9p_rx_last [F9P_SRC_COUNT-1:0];
  // ------------------------------------------------------------
  for (sfpL = 0;  sfpL < SFP_COUNT;  sfpL = sfpL + 1) begin : f9p
    f9phdr_wrap #(
      .F9HDR_BUFFER_LENGTH (F9HDR_BUFFER_LENGTH ),
      .TTS_WIDTH           (TTS_WIDTH           ),
      .SAME_IO_CLK         (0                   ),
      .I_DATA_WIDTH        (SFP_DATA_WIDTH      ),
      .O_DATA_WIDTH        (TO_DRAM_DATA_W      )
    )
    f9phdr_wrap_i (
      .rst_in          (sfp_rx_rst_in  [sfpL] | dram_rst ),
      .tts_gray_in     (tts_gray_in           ),
      .port_id_in      (sfpL[BYTE_WIDTH-1:0]  ),
      .i_clk_in        (sfp_rx_clk_in  [sfpL] ),
      .i_valid_in      (sfp_rx_valid_in[sfpL] ),
      .i_data_in       (sfp_rx_data_in [sfpL] ),
      .i_keep_in       (sfp_rx_keep_in [sfpL] ),
      .i_last_in       (sfp_rx_last_in [sfpL] ),
      .i_frame_err_in  (sfp_rx_err_in  [sfpL] ),
      .outbuf_full_in  (dram_buf_full         ),
      .o_clk_in        (dram_clk              ),
      .o_rst_out       (                      ),
      .o_valid_out     (f9p_rx_valid   [sfpL] ),
      .o_ready_in      (f9p_rx_ready   [sfpL] ),
      .o_data_out      (f9p_rx_data    [sfpL] ),
      .o_keep_out      (f9p_rx_keep    [sfpL] ),
      .o_last_out      (f9p_rx_last    [sfpL] ),
      .o_data_len_out  (                      )
    );
  end
  // -------------------------------------------------------------
  wire                     to_dram_valid;
  wire                     to_dram_ready;
  wire[TO_DRAM_DATA_W-1:0] to_dram_data;
  wire                     to_dram_last;
  axis_n_to_one #(
    .N_COUNT    (F9P_SRC_COUNT  ),
    .DATA_WIDTH (TO_DRAM_DATA_W ),
    .USE_PAUSE  (0              )
  )
  sfpN_to_temac_i (
    .clk_in           (dram_clk                ),
    .n_axis_valid_in  (f9p_rx_valid            ),
    .n_axis_ready_out (f9p_rx_ready            ),
    .n_axis_data_in   (f9p_rx_data             ),
    .n_axis_keep_in   (f9p_rx_keep             ),
    .n_axis_last_in   (f9p_rx_last             ),
    .o_pause_in       (                        ),
    .o_axis_valid_out (to_dram_valid           ),
    .o_axis_ready_in  (to_dram_ready           ),
    .o_axis_data_out  (to_dram_data            ),
    .o_axis_last_out  (to_dram_last            ),
    .o_axis_keep_out  (                        )
  );
  // =============================================================
  localparam DRAM_WR_IDX_L = DRAM_APP_DATA_WIDTH / TO_DRAM_DATA_W;
  localparam DRAM_WR_IDX_W = (DRAM_WR_IDX_L <= 1 ? 1 : $clog2(DRAM_WR_IDX_L));
  initial begin
    if (DRAM_APP_DATA_WIDTH < TO_DRAM_DATA_W) begin
      $error("DRAM_APP_DATA_WIDTH(%2d) must >= TO_DRAM_DATA_W(%2d)", DRAM_APP_DATA_WIDTH, TO_DRAM_DATA_W);
      $finish;
    end
    if (DRAM_APP_DATA_WIDTH % TO_DRAM_DATA_W != 0) begin
      $error("DRAM_APP_DATA_WIDTH(%2d) %% TO_DRAM_DATA_W(%2d) must == 0", DRAM_APP_DATA_WIDTH, TO_DRAM_DATA_W);
      $finish;
    end
  end
  // -------------------------------------
  /// 從哪裡讀取下一個封包的長度(PkBytes_)?
  localparam LEN_PREFETCH_ADR_OFS = (F9PHDR_WIDTH > DRAM_APP_DATA_WIDTH
                                    ? (F9PHDR_WIDTH / DRAM_APP_DATA_WIDTH) - 1
                                    : 0);
  localparam LEN_PREFETCH_BIT_OFS = (F9PHDR_WIDTH > DRAM_APP_DATA_WIDTH
                                    ? 0
                                    : F9PHDR_SPL_WIDTH);
  // -------------------------------------
  assign dram_buf_full = 0;
  // -------------------------------------
  wire[DRAM_ADDR_WIDTH-1:0]  dram_addr_a1 = dram_addr + 1;
  // -------------------------------------
  localparam[DRAM_APP_CMD_WIDTH-1:0] DRAM_APP_CMD_READ  = 1,
                                     DRAM_APP_CMD_WRITE = 0;
  localparam   DRAM_ST_IDLE          = 0,
               DRAM_ST_WRITE         = 1,
               DRAM_ST_START_READ    = 2,
               DRAM_ST_CONTINUE_READ = 3,
               DRAM_ST_RECOVER_REQ   = 4,
               DRAM_ST_COUNT         = 5;
  localparam   DRAM_ST_WIDTH = $clog2(DRAM_ST_COUNT);
  reg[DRAM_ST_WIDTH-1:0]   dram_state;
  // -------------------------------------
  reg [DRAM_WR_IDX_W-1  :0] dram_wr_idx_cur;
  wire[DRAM_WR_IDX_W-1  :0] dram_wr_idx_nxt = dram_wr_idx_cur + 1;
  reg [DRAM_ADDR_WIDTH-1:0] dram_wr_addr;

  reg    to_dram_prev_last;
  wire   is_cmd_done = (~dram_app_en || dram_app_rdy);           // [讀/寫] 要求(cmd,addr) 已完成?
  wire   is_wdf_done = (~dram_app_wdf_wren || dram_app_wdf_rdy); // 寫入資料(wdf_data)已完成;

  assign to_dram_ready = (  (dram_state == DRAM_ST_IDLE)
                         || (dram_state == DRAM_ST_WRITE
                              && (  (is_cmd_done && is_wdf_done && ~to_dram_prev_last)
                                 || (DRAM_WR_IDX_L > 1 && ~dram_app_en && ~dram_app_wdf_wren)
                                 )
                            )
                         );

  assign dram_app_wdf_mask = 0;
  assign dram_app_wdf_end  = 1;
  initial begin
    // 目前僅支援 MIG local interface data width(DRAM_APP_DATA_WIDTH) 與 DRAM 的 Burst size bits 相同,
    // 也就是 app interface 一個 beat = DRAM 一次 Burst;
    if (DRAM_APP_DATA_WIDTH != DRAM_BURST_SIZE_BITS) begin
      $error("DRAM_APP_DATA_WIDTH(%d) != DRAM_BURST_SIZE_BITS(%d)", DRAM_APP_DATA_WIDTH, DRAM_BURST_SIZE_BITS);
      $finish;
    end
  end
  // -------------------------------------
  wire                              dram_rd_rst;
  wire[F9P_LEN_WIDTH-1  :0]         dram_rd_len_get  = dram_app_rd_data[LEN_PREFETCH_BIT_OFS +: F9P_LEN_WIDTH] + F9PHDR_LENGTH;
  wire[F9P_LEN_WIDTH-1  :0]         dram_rd_beat_cnt = ((dram_rd_len_get + DRAM_APP_DATA_LENGTH - 1) >> $clog2(DRAM_APP_DATA_LENGTH));
  reg [F9P_LEN_WIDTH-1  :0]         dram_rd_addr_remain;
  reg [F9P_LEN_WIDTH-1  :0]         dram_rd_data_remain;
  reg [DRAM_ADDR_WIDTH-1:0]         dram_rd_next_addr;
  wire[DRAM_ADDR_WIDTH-1:0]         dram_rd_done_addr = dram_rd_next_addr + dram_rd_beat_cnt;
  reg                               dram_rd_done;
  wire                              dram_rd_pause;
  reg [RECOVER_REQ_ADDR_FROM_W-1:0] dram_rd_last_addr;
  reg [F9PCAP_SEQNO_WIDTH-1:0]      dram_rd_last_seqno;
  wire[F9PCAP_SEQNO_WIDTH-1:0]      dram_rd_next_seqno = dram_rd_last_seqno + 1;
  reg [F9PCAP_SEQNO_WIDTH-1:0]      dram_rd_cur_seqno;
  reg [RECOVER_REQ_ADDR_FROM_W-1:0] dram_rd_cur_addr_from;
  reg [F9P_LEN_WIDTH-1:0]           from_dram_f9p_len;
  wire                              from_dram_empty;
  wire                              from_dram_valid = (dram_rd_done  &&  ~from_dram_empty);
  wire                              from_dram_ready;
  wire[DRAM_APP_DATA_WIDTH -1:0]    from_dram_data;
  // -------------------------------------
  localparam RECOVER_REQ_ADDR_FROM_W = RECOVER_REQ_ADDR_FROM_L * BYTE_WIDTH,
             RECOVER_REQ_COUNT_W     = RECOVER_REQ_COUNT_L     * BYTE_WIDTH,
             RECOVER_REQ_CHECK_W     = RECOVER_REQ_CHECK_L     * BYTE_WIDTH;
  reg                               f9mg_is_recovering;
  reg                               f9mg_recover_checking;
  reg [DRAM_ADDR_WIDTH-1:0]         f9mg_recover_addr;
  wire[DRAM_ADDR_WIDTH-1:0]         f9mg_recover_next_addr = f9mg_recover_addr + dram_rd_beat_cnt;
  reg [RECOVER_REQ_COUNT_W    -1:0] f9mg_recover_remain; // 剩餘回補筆數;
  reg                               f9mg_recover_req_pop_reg;
  wire[RECOVER_REQ_ADDR_FROM_W-1:0] f9mg_recover_req_addr_from;
  wire[DRAM_ADDR_WIDTH-1:0]         f9mg_recover_req_addr_i = f9mg_recover_req_addr_from[DRAM_ADDR_WIDTH-1:0];
  wire[RECOVER_REQ_COUNT_W    -1:0] f9mg_recover_req_count;
  wire[RECOVER_REQ_CHECK_W    -1:0] f9mg_recover_req_check_i, f9mg_recover_req_check;
  wire[F9PCAP_SEQNO_WIDTH     -1:0] f9mg_recover_req_seqno_from;
  assign f9mg_recover_req_pop_out = f9mg_recover_req_pop_reg;
  assign {f9mg_recover_req_count, f9mg_recover_req_seqno_from, f9mg_recover_req_addr_from, f9mg_recover_req_check_i} = f9mg_recover_req_data_in;
  byte_reverse #(
    .DATA_LENGTH(RECOVER_REQ_CHECK_L ),
    .STEP_LENGTH(F9PHDR_SPL_LENGTH   )
  )
  rev_recover_req_check_i(
    .data_in  (f9mg_recover_req_check_i ),
    .data_out (f9mg_recover_req_check   )
  );
  // -------------------------------------
  localparam[BYTE_WIDTH-1:0]        RECOVER_RESULT_EMPTY     = 8'h00,
                                    RECOVER_RESULT_RUNNING   = 8'h01,
                                    RECOVER_RESULT_DONE      = 8'h02,
                                    RECOVER_RESULT_BAD_COUNT = 8'h81,
                                    RECOVER_RESULT_BAD_CHECK = 8'h82,
                                    RECOVER_RESULT_BAD_ADDR  = 8'h83;
  reg [BYTE_WIDTH-1             :0] last_recover_result;
  reg [F9PCAP_SEQNO_WIDTH-1     :0] last_recover_req_seqno;
  reg [RECOVER_REQ_ADDR_FROM_W-1:0] last_recover_req_addr;
  reg                               is_ack_recover_result;
  wire[DEV_ST_RECOVER_INFO_W-1:0]   dev_st_recover_info_w = {
         dram_rd_last_seqno,
         dram_rd_last_addr,
         last_recover_req_seqno,
         last_recover_req_addr,
         last_recover_result
      };
  // -----
  sync_signal #(
    .WIDTH (DEV_ST_RECOVER_INFO_W)
  )
  sync_dev_st_recover_i (
    .clk (dev_st_clk_in           ),
    .in  (dev_st_recover_info_w   ),
    .out (dev_st_recover_info_out )
  );
  // -----
  sync_reset
  sync_ack_recover_result_i(
    .clk     (dev_st_clk_in           ),
    .rst_in  (is_ack_recover_result   ),
    .rst_out (dev_st_force_resend_out )
  );
  // -------------------------------------
  f9fifo #(
    .DATA_WIDTH (DRAM_APP_DATA_WIDTH ),
    .COUNT      ((FRAME_MAX_LENGTH + DRAM_APP_DATA_LENGTH - 1) / DRAM_APP_DATA_LENGTH )
  )
  dram_rd_fifo_i (
    .aclk       (dram_clk                   ),
    .rstn       (~(dram_rst || dram_rd_rst) ),
    .wr_push    (dram_app_rd_data_valid && ~f9mg_recover_checking ),
    .wr_data    (dram_app_rd_data           ),
    .rd_pop     (from_dram_valid && from_dram_ready ),
    .rd_data    (from_dram_data             ),
    .is_empty   (from_dram_empty            ),
    .is_full    (                           ),
    .data_count (                           )
  );
  // -------------------------------------
  reg [DRAM_APP_DATA_WIDTH-1:0]  ila_dram_wr_first;
  reg [DRAM_APP_DATA_WIDTH-1:0]  ila_dram_rd_first;
  reg [F9P_LEN_WIDTH-1:0]        ila_dram_rd_beat_cnt;
  reg                            ila_err_debug = 0;
  // 檢查讀完 dram_rd_beat_cnt 之後是否會 overflow?
  wire chk_rd_1  = dram_rd_next_addr < dram_wr_addr;
  wire chk_rd_2  = dram_wr_addr < dram_rd_done_addr;
  wire is_rd_err = (dram_rd_next_addr < dram_rd_done_addr
                   ? (chk_rd_1 && chk_rd_2)
                   : (chk_rd_1 || chk_rd_2) );
  // -------------------------------------
  always @(posedge dram_clk) begin
    dram_state          <= dram_state;
    dram_app_en         <= dram_app_en;
    dram_app_wdf_wren   <= dram_app_wdf_wren;
    // -----
    dram_wr_idx_cur <= dram_wr_idx_cur;
    if (is_wdf_done) begin
      // 底下情況之一可使用現在的 to_dram_data;
      // (1) ~dram_app_wdf_wren: 尚未啟動 wdf_data 寫入, 或上次的 wdf_data 已完成;
      // (2) dram_app_wdf_wren: 已啟動寫入要求且此時已完成(dram_app_wdf_rdy);
      to_dram_prev_last <= to_dram_last;
      if (DRAM_WR_IDX_L <= 1) begin
        dram_app_wdf_data <= to_dram_data;
      end else begin
        dram_app_wdf_data[(dram_wr_idx_cur * TO_DRAM_DATA_W) +: TO_DRAM_DATA_W] <= to_dram_data;
      end
    end else begin
      to_dram_prev_last <= to_dram_prev_last;
      dram_app_wdf_data <= dram_app_wdf_data;
    end
    // -----
    from_dram_f9p_len   <= from_dram_f9p_len;
    dram_rd_done        <= from_dram_empty ? 0 : dram_rd_done;
    dram_rd_last_seqno  <= dram_rd_last_seqno;
    dram_rd_addr_remain <= dram_rd_addr_remain;
    dram_rd_data_remain <= dram_rd_data_remain;
    if (dram_app_rd_data_valid) begin     // 讀取要求的資料已送達;
      dram_rd_data_remain <= dram_rd_data_remain - 1;
      if (dram_rd_data_remain == 0) begin //   已是最後一個讀取的資料: 已取得全部的讀取資料;
        dram_rd_done <= 1;
      end
    end
    // -----
    f9mg_recover_req_pop_reg <= 0;
    f9mg_recover_remain      <= f9mg_recover_remain;
    f9mg_is_recovering       <= f9mg_is_recovering;
    f9mg_recover_checking    <= f9mg_recover_checking;
    f9mg_recover_addr        <= f9mg_recover_addr;
    is_ack_recover_result    <= 0;
    last_recover_req_seqno   <= last_recover_req_seqno;
    last_recover_req_addr    <= last_recover_req_addr;
    last_recover_result      <= last_recover_result;
    dram_rd_cur_seqno        <= dram_rd_cur_seqno;
    dram_rd_cur_addr_from    <= dram_rd_cur_addr_from;
    dram_rd_last_addr        <= dram_rd_last_addr;
    // -----
    case (dram_state)
    default: ;
    DRAM_ST_IDLE: begin
            dram_wr_idx_cur <= 0;
            if (~ila_err_debug) begin
              if (to_dram_valid) begin
                dram_state   <= DRAM_ST_WRITE;
                dram_addr    <= dram_wr_addr;
                dram_app_cmd <= DRAM_APP_CMD_WRITE;
                if (DRAM_WR_IDX_L <= 1) begin           //
                  dram_app_en       <= 1;               //
                  dram_app_wdf_wren <= 1;               //
                end else begin                          //
                  dram_wr_idx_cur   <= dram_wr_idx_nxt; //
                end
              end else begin
                // if (dram_rd_rst)
                //   // 為了正確計算 dram_rd_last_seqno, 所以將 dram_rd_rst 的處理移到 DRAM_ST_START_READ;
                //   dram_rd_next_addr <= dram_wr_addr;
                // else
                if (~dram_rd_pause && from_dram_empty) begin
                  if (f9mg_recover_req_valid_in && ~f9mg_recover_req_pop_out && ~f9mg_is_recovering && ~f9mg_recover_checking) begin
                    dram_state <= DRAM_ST_RECOVER_REQ;
                  end else if (dram_rd_next_addr != dram_wr_addr || f9mg_is_recovering) begin
                    dram_state   <= DRAM_ST_START_READ;
                    dram_app_en  <= 1;
                    if (f9mg_is_recovering) begin
                      dram_addr          <= f9mg_recover_addr;
                      dram_rd_cur_seqno  <= dram_rd_cur_seqno + 1;
                    end else begin
                      dram_addr          <= dram_rd_next_addr;
                      dram_rd_last_addr  <= dram_rd_next_addr;
                      dram_rd_last_seqno <= dram_rd_next_seqno;
                      dram_rd_cur_seqno  <= dram_rd_next_seqno;
                    end
                    dram_app_cmd <= DRAM_APP_CMD_READ;
                  end
                end
              end
            end
          end
    DRAM_ST_WRITE: begin
            if (dram_app_rdy) begin // dram_addr 已被接受;
              dram_app_en <= 0;     // 此時需要停止 dram_addr 的傳遞;
            end
            // -----
            if (dram_app_wdf_rdy) begin // 寫入資料(wdf_data)已被接受;
              dram_app_wdf_wren <= 0;   // 此時需要停止 wdf_data 的傳遞;
            end
            // ---------------------------------------------
            if (is_cmd_done && is_wdf_done) begin
              if (dram_addr == dram_wr_addr) begin
                ila_dram_wr_first <= dram_app_wdf_data;
              end
              if (dram_addr_a1 == dram_rd_next_addr) begin
                // dram full?
              end
              // -----
              dram_app_en       <= 0;
              dram_app_wdf_wren <= 0;
              dram_addr         <= dram_addr_a1;
              if (to_dram_prev_last || ~to_dram_valid) begin // 上次的寫入要求已是最後一次;
                dram_wr_addr  <= dram_addr_a1;
                dram_state    <= DRAM_ST_IDLE;
              end else begin
                if (DRAM_WR_IDX_L <= 1) begin           //
                  dram_app_en       <= 1;               //
                  dram_app_wdf_wren <= 1;               //
                end else begin                          //
                  dram_wr_idx_cur   <= dram_wr_idx_nxt; //
                end
              end
            end else begin
              if (dram_app_en || dram_app_wdf_wren) begin
                // 寫入要求尚未完成;
              end else begin
                if (DRAM_WR_IDX_L > 1) begin
                  if ((dram_wr_idx_cur == DRAM_WR_IDX_L - 1) || to_dram_last) begin
                    dram_wr_idx_cur   <= 0;
                    dram_app_en       <= 1;
                    dram_app_wdf_wren <= 1;
                  end else begin
                    dram_wr_idx_cur   <= dram_wr_idx_nxt;
                  end
                end
              end
            end
          end
    DRAM_ST_START_READ: begin
            dram_rd_cur_addr_from <= dram_addr;
            // -----
            if (dram_app_rdy) begin
              dram_app_en <= 0;
            end
            // -----
            from_dram_f9p_len   <= dram_rd_len_get;
            dram_rd_addr_remain <= dram_rd_beat_cnt - 2;
            dram_rd_data_remain <= dram_rd_beat_cnt - 2;
            if (dram_app_rd_data_valid) begin
              f9mg_recover_checking <= 0;
              f9mg_recover_addr     <= f9mg_recover_next_addr;
              if (f9mg_recover_checking) begin
                dram_state               <= DRAM_ST_IDLE;
                f9mg_recover_req_pop_reg <= 1;
                if (f9mg_recover_next_addr == dram_rd_next_addr) begin
                  // (回補位置 == 下次要傳送的位置)
                  // 所以此位置必定[尚未讀取送出], 因此[位置錯誤];
                  last_recover_result   <= RECOVER_RESULT_BAD_ADDR;
                  is_ack_recover_result <= 1;
                end else if (f9mg_recover_req_check == dram_app_rd_data[RECOVER_REQ_CHECK_W-1:0]) begin
                  // 檢查結果正確: 開始回補;
                  f9mg_is_recovering    <= 1;
                end else begin
                  last_recover_result   <= RECOVER_RESULT_BAD_CHECK;
                  is_ack_recover_result <= 1;
                end
              end else begin
                f9mg_recover_remain <= f9mg_recover_remain - 1;
                dram_state          <= DRAM_ST_IDLE;
                if (dram_rd_rst) begin
                  // 為了正確計算 dram_rd_last_seqno, 所以即使在 dram_rd_rst 時:
                  // 仍需讀入每個 frame 的長度, 為了逐個 frame 增加 dram_rd_next_addr 及 dram_rd_last_seqno;
                  // 雖然此舉略占資源, 但因 dram_rd_rst 的機率不高, 所以為了正確性, 仍執行此操作;
                  // 否則放在 DRAM_ST_IDLE 時執行 if (dram_rd_rst) dram_rd_next_addr <= dram_wr_addr; 會更簡單且省資源;
                  dram_rd_next_addr <= dram_rd_done_addr;
                end else if (dram_rd_beat_cnt == 1) begin
                  dram_rd_done <= 1;
                  if (f9mg_is_recovering) begin
                    if (f9mg_recover_remain == 1 || f9mg_recover_addr == dram_wr_addr) begin
                      f9mg_is_recovering    <= 0;
                      last_recover_result   <= RECOVER_RESULT_DONE;
                      is_ack_recover_result <= 1;
                    end
                  end else begin
                    dram_rd_next_addr <= dram_addr_a1;
                  end
                end else begin
                  dram_rd_done <= 0;
                  dram_app_en  <= 1;
                  dram_addr    <= dram_addr_a1;
                  dram_state   <= DRAM_ST_CONTINUE_READ;
                end
              end
              // -----
              if (ILA_DEBUG) begin
                ila_dram_rd_beat_cnt <= dram_rd_beat_cnt;
                ila_dram_rd_first    <= dram_app_rd_data;
                if (~f9mg_is_recovering && ~f9mg_recover_checking && is_rd_err) begin
                  ila_err_debug <= 1;
                  dram_state    <= DRAM_ST_IDLE;
                  dram_addr     <= dram_addr;
                  dram_app_en   <= 0;
                end
              end
            end
          end
    DRAM_ST_CONTINUE_READ: begin
            if (dram_app_rdy) begin               // 上次的讀取要求成功;
              if (dram_rd_addr_remain == 0) begin //   全部的讀取要求已做完:
                dram_app_en <= 0;                 //     結束讀取要求;
                dram_state  <= DRAM_ST_IDLE;
                if (f9mg_is_recovering) begin
                  if (f9mg_recover_remain == 0 || f9mg_recover_addr == dram_wr_addr) begin
                    f9mg_is_recovering    <= 0;
                    last_recover_result   <= RECOVER_RESULT_DONE;
                    is_ack_recover_result <= 1;
                  end
                end else begin
                  dram_rd_next_addr <= dram_addr_a1;
                end
              end else begin                      //   還有讀取要求尚未做完:
                dram_app_en         <= 1;         //     繼續送出下一個讀取要求;
                dram_addr           <= dram_addr_a1;
                dram_rd_addr_remain <= dram_rd_addr_remain - 1;
              end
            end
          end
    DRAM_ST_RECOVER_REQ: begin
            f9mg_recover_remain    <= f9mg_recover_req_count;
            f9mg_recover_addr      <= f9mg_recover_req_addr_i;
            dram_rd_cur_seqno      <= f9mg_recover_req_seqno_from;
            last_recover_req_seqno <= f9mg_recover_req_seqno_from;
            last_recover_req_addr  <= f9mg_recover_req_addr_from;
            // -----
            dram_state               <= DRAM_ST_IDLE; // --+ 預設回補要求有誤,
            f9mg_recover_req_pop_reg <= 1;            //   | 若接下來檢查回補要求正確,
            is_ack_recover_result    <= 1;            // --/ 則會覆蓋這些的內容;
            if (f9mg_recover_req_count == 0) begin
              // 不合理的回補[筆數], 不理會, 直接排除;
              last_recover_result <= RECOVER_RESULT_BAD_COUNT;
            end else if (f9mg_recover_req_addr_i == dram_rd_last_addr) begin
              last_recover_result <= RECOVER_RESULT_BAD_ADDR;
            end else begin
              // 因為 f9mg_recover_req_check 需保留檢查,
              // 所以必須等到 check 完成後才可 pop;
              f9mg_recover_req_pop_reg <= 0;
              f9mg_recover_checking    <= 1;
              dram_state               <= DRAM_ST_START_READ;
              dram_app_en              <= 1;
              dram_addr                <= f9mg_recover_req_addr_i;
              dram_app_cmd             <= DRAM_APP_CMD_READ;
              last_recover_result      <= RECOVER_RESULT_RUNNING;
              // 回補要求端直接收到回補的內容即可,
              // 所以沒必要立即回覆 Recover RUNNING 狀態;
              is_ack_recover_result    <= 0;
            end
          end
    endcase
    // -----
    if (dram_rst || ~dram_init_calib_complete) begin
      dram_state             <= DRAM_ST_IDLE;
      dram_app_en            <= 0;
      dram_app_wdf_wren      <= 0;
      dram_wr_addr           <= 0;
      dram_wr_idx_cur        <= 0;
      dram_rd_next_addr      <= 0;
      dram_rd_last_addr      <= 0;
      dram_rd_last_seqno     <= 0;
      ila_err_debug          <= 0;
      f9mg_is_recovering     <= 0;
      f9mg_recover_checking  <= 0;
      dram_rd_cur_seqno      <= 0;
      dram_rd_cur_addr_from  <= 0;
      last_recover_req_seqno <= 0;
      last_recover_req_addr  <= 0;
      last_recover_result    <= RECOVER_RESULT_EMPTY;
    end
  end
  // =============================================================
  wire   dram_to_rst;
  assign dram_rd_rst = dram_to_rst;
  // ----------
  wire[F9PCAP_EXT_HDR_WIDTH-1:0] f9pcap_ext_hdr = {
    dram_rd_cur_seqno,
    dram_rd_cur_addr_from
  };
  // ----------
  sync_reset
  sync_dram_to_rst_i(
    .clk     (dram_clk    ),
    .rst_in  (~is_f9pcap_en || ~temac_link_ready[0]),
    .rst_out (dram_to_rst )
  );
  reg                            udp_out_valid;
  reg [DRAM_APP_DATA_LENGTH-1:0] udp_out_keep;
  reg [DRAM_APP_DATA_WIDTH-1:0]  udp_out_data;
  reg                            udp_out_last;
  udp_eth_send #(
    .DATA_WIDTH                (DRAM_APP_DATA_WIDTH   ),
    .EXT_PAYLOAD_HEADER_LENGTH (F9PCAP_EXT_HDR_LENGTH )
  )
  udp_eth_send_i(
    .rst_in        (dram_to_rst         ),
    .clk_in        (dram_clk            ),
    .i_valid_in    (from_dram_valid     ),
    .i_ready_out   (from_dram_ready     ),
    .i_data_in     (from_dram_data      ),
  //.i_keep_in     (from_dram_keep      ),
  //.i_last_in     (from_dram_last      ),
    .i_data_len_in (from_dram_f9p_len   ),
    .o_valid_out   (udp_out_valid       ),
    .o_data_out    (udp_out_data        ),
    .o_keep_out    (udp_out_keep        ),
    .o_last_out    (udp_out_last        ),
    .EthSrcMAC     (f9pcap_src_mac_addr ),
    .IpSrcAddr     (f9pcap_src_ip_addr  ),
    .IpDstAddr     (f9pcap_mcgroup_addr ),
    .UdpSrcPort    (f9pcap_src_port     ),
    .UdpDstPort    (f9pcap_mcgroup_port ),
    .ext_payload_header_in (f9pcap_ext_hdr )
  );
  // -------------------------------------
  for (phyL = 0;  phyL < PHY_COUNT;  phyL = phyL + 1) begin : to_temac
    wire temac_clk = temac_tx_clk_in[phyL];
    wire temac_rst = temac_tx_rst_in[phyL] || ~is_f9pcap_en || ~temac_link_ready[phyL];
    axis_store_fwd #(
      .FRAME_MAX_LENGTH (FRAME_MAX_LENGTH    ),
      .IN_DATA_WIDTH    (DRAM_APP_DATA_WIDTH ),
      .OUT_DATA_WIDTH   (TEMAC_DATA_WIDTH    )
    )
    dram_to_phy_i(
      .rst_in          (dram_to_rst | temac_rst ),
      .i_clk_in        (dram_clk           ),
      .i_valid_in      (udp_out_valid      ),
      .i_data_in       (udp_out_data       ),
      .i_keep_in       (udp_out_keep       ),
      .i_last_in       (udp_out_last       ),
      .is_buf_full_out (                   ),
      .o_rst_out       (                   ),
      .o_clk_in        (temac_clk          ),
      .o_valid_out     (wrap_tx_valid[phyL][WRAP_TX_DRAM_OUT_IDX] ),
      .o_ready_in      (wrap_tx_ready[phyL][WRAP_TX_DRAM_OUT_IDX] ),
      .o_data_out      (wrap_tx_data [phyL][WRAP_TX_DRAM_OUT_IDX] ),
      .o_keep_out      (                                          ),
      .o_last_out      (wrap_tx_last [phyL][WRAP_TX_DRAM_OUT_IDX] )
    );
    // -----
    axis_n_to_one #(
      .N_COUNT    (2                ),
      .DATA_WIDTH (TEMAC_DATA_WIDTH ),
      .USE_PAUSE  (0                )
    )
    sfpN_to_temac_i (
      .clk_in           (temac_clk                ),
      .n_axis_valid_in  (wrap_tx_valid     [phyL] ),
      .n_axis_ready_out (wrap_tx_ready     [phyL] ),
      .n_axis_data_in   (wrap_tx_data      [phyL] ),
      .n_axis_last_in   (wrap_tx_last      [phyL] ),
      .n_axis_keep_in   (                         ),
      .o_pause_in       (                         ),
      .o_axis_valid_out (temac_tx_valid_out[phyL] ),
      .o_axis_ready_in  (temac_tx_ready_in [phyL] ),
      .o_axis_data_out  (temac_tx_data_out [phyL] ),
      .o_axis_last_out  (temac_tx_last_out [phyL] ),
      .o_axis_keep_out  (                         )
    );
  end
  // -------------------------------------
  wire sgap_pause;
  if (SGAP_WIDTH <= 0) begin
    assign sgap_pause = 0;
  end else begin
    count_down #(
      .COUNTER_WIDTH (SGAP_WIDTH )
    )
    count_down_i(
      .rst_in          (wrap_tx_rst       [0] ),
      .clk_in          (wrap_tx_clk       [0] ),
      .count_start_in  (temac_tx_last_out [0] ),
      .counter_init_in (sgap_cfg_in           ),
      .counter_out     (                      ),
      .trigger_out     (sgap_pause            )
    );
  end
  // -----
  sync_signal
  sync_dram_rd_pause_i(
    .clk (dram_clk      ),
    .in  (sgap_pause | udp_out_valid | temac_tx_valid_out[0]),
    .out (dram_rd_pause )
  );
  // -------------------------------------
  if (ILA_DEBUG != 0) begin
    wire[TTS_WIDTH-1:0] tts_uint_syn;
    sync_signal #(
      .WIDTH (TTS_WIDTH)
    )
    sync_tts_i (
      .clk (dram_clk     ),
      .in  (tts_uint_in  ),
      .out (tts_uint_syn )
    );
    // ----------
    wire temac_tx_valid_syn;
    wire temac_tx_last_syn;
    sync_signal #(
      .WIDTH(2)
    )
    sync_temac_tx_valid_i(
      .clk (dram_clk              ),
      .in  ({temac_tx_valid_out[0], temac_tx_last_out[0]} ),
      .out ({temac_tx_valid_syn,    temac_tx_last_syn   } )
    );
    wire[15:0] ila_sig = { dram_rd_pause,   temac_tx_valid_syn, temac_tx_last_syn,  udp_out_valid,
                           dram_rd_done,    from_dram_empty,    from_dram_valid,    from_dram_ready,
                           to_dram_valid,   to_dram_ready,      to_dram_last,       to_dram_prev_last,
                           f9p_rx_valid[0], f9p_rx_ready[0],    f9p_rx_valid[1],    f9p_rx_ready[1]
                         };
/*
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_dram
set_property -dict [list \
  CONFIG.C_PROBE0_WIDTH {25} \
  CONFIG.C_PROBE1_WIDTH {3} \
  CONFIG.C_PROBE6_WIDTH {64} \
  CONFIG.C_PROBE7_WIDTH {512} \
  CONFIG.C_PROBE10_WIDTH {512} \
  CONFIG.C_PROBE12_WIDTH {3} \
  CONFIG.C_PROBE13_WIDTH {25} \
  CONFIG.C_PROBE14_WIDTH {25} \
  CONFIG.C_PROBE15_WIDTH {16} \
  CONFIG.C_PROBE16_WIDTH {16} \
  CONFIG.C_PROBE17_WIDTH {16} \
  CONFIG.C_PROBE18_WIDTH {16} \
  CONFIG.C_PROBE19_WIDTH {512} \
  CONFIG.C_PROBE20_WIDTH {512} \
  CONFIG.C_PROBE24_WIDTH {64} \
  CONFIG.C_PROBE25_WIDTH {25} \
  CONFIG.C_PROBE26_WIDTH {16} \
  CONFIG.C_NUM_OF_PROBES {27} \
] [get_ips ila_dram]
*/
    ila_dram
    ila_dram_i(
      .clk    (dram_clk               ),
      .probe0 (dram_addr              ),
      .probe1 (dram_app_cmd           ),
      .probe2 (dram_app_en            ),
      .probe3 (dram_app_rdy           ),
      .probe4 (dram_app_wdf_rdy       ),
      .probe5 (dram_app_wdf_wren      ),
      .probe6 (tts_uint_syn           ),
      .probe7 (dram_app_wdf_data      ),
      .probe8 (dram_app_wdf_end       ),
      .probe9 (dram_app_rd_data_valid ),
      .probe10(dram_app_rd_data       ),
      .probe11(dram_app_rd_data_end   ),

      .probe12(dram_state             ),
      .probe13(dram_wr_addr           ),
      .probe14(dram_rd_next_addr      ),
      .probe15(from_dram_f9p_len      ),
      .probe16(ila_dram_rd_beat_cnt   ),
      .probe17(dram_rd_addr_remain    ),
      .probe18(ila_sig                ),
      .probe19(from_dram_data         ),
      .probe20(udp_out_data           ),
      .probe21(ila_err_debug          ),
      .probe22(f9mg_is_recovering     ),
      .probe23(f9mg_recover_checking  ),
      .probe24(f9mg_recover_req_check ),
      .probe25(f9mg_recover_addr      ),
      .probe26(f9mg_recover_remain    )
    );
  end
end
// ===============================================================================
endmodule
//////////////////////////////////////////////////////////////////////////////////
