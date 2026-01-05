`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
module f9pcap_dev_top #(
  `include "eth_ip_localparam.vh"
  `include "localparam_recover.vh"

  parameter[7:0] SFP_COUNT      = 2,
  parameter[7:0] PHY_COUNT      = 2,

  /// f9mg 管理功能, 使用那個 port?
  /// 若 F9MG_PHY_ID 與 F9MG_SFP_ID 同時 >= 0, 則使用 PHY;
  parameter      F9MG_PHY_ID    = 0,
  parameter      F9MG_SFP_ID    = -1,

  parameter      FRAME_MAX_LENGTH        = 1600,
  /// 配合 BRAM 的特性來決定 BUFFER_LENGTH;
  /// 可從 Synth 的 log 來查看 Block RAM 的使用狀況, 然後調整適當的配置;
  parameter      F9HDR_BUFFER_LENGTH     = 512       * 64 / BYTE_WIDTH,
  parameter      TEMAC_OUT_BUFFER_LENGTH = 16 * 1024 * 64 / BYTE_WIDTH,

  /// 以 7SERIES(xc7k480t) 為例:
  ///  - GT(Gigabit Transceiver) 以 QUAD 為群組;
  ///  - 每個 QUAD 裡面包含: refclk*2, GT*4, QPLL*1;
  ///  - 一個 refclk 可以提供給上中下 3 個 QUAD.QPLL;
  ///  - 每個 QUAD 裡面的 GT*4, 必須使用該 QUAD 自己的 QPLL, 由 QUAD 的 MASTER 建立 QPLL;
  parameter integer GTREFCLK_COUNT = 1,
  parameter integer QUAD_COUNT     = 1,
  /// 設定各個 QUAD.QPLL 使用的 REFCLK(sfp_gt_refclk_p[]/n[])
  parameter integer QUAD_REFCLK_MAP[QUAD_COUNT-1 :0] = {    0 },
  /// 設定各個 sfp[] 所在的 QUAD_IDX:[0..QUAD_COUNT-1]
  parameter integer SFP_QUAD_MAP   [SFP_COUNT -1 :0] = { 0, 0 },
  /// 設定各個 sfp[] 是否為 QPLL.MASTER? 每個 QUAD 只能有一個 QPLL.MASTER;
  parameter integer SFP_QPLL_MASTER[SFP_COUNT -1 :0] = { 0, 1 },

  // "ULTRASCALE", "7SERIES", "NONE"
  parameter  IDELAYCTRL_SIM_DEVICE = "ULTRASCALE",
  parameter  TXSEQUENCE_PAUSE      = 0,
  parameter  COUNT_125US           = 125000/6.4,

  parameter  DRAM_APP_CMD_WIDTH    = 3,
  parameter  DRAM_ADDR_WIDTH       = 0,
  parameter  DRAM_BURST_SIZE_BITS  = 64,
  parameter  DRAM_APP_DATA_LENGTH  = 64,
  localparam DRAM_APP_DATA_WIDTH   = DRAM_APP_DATA_LENGTH * BYTE_WIDTH
)(
  input                       sysclk_100m_in,
  input                       sys_reset_in,

  output                      eeprom_scl_out,
  inout                       eeprom_sda_io,

  input [GTREFCLK_COUNT-1:0]  sfp_gt_refclk_p,
  input [GTREFCLK_COUNT-1:0]  sfp_gt_refclk_n,
  input [SFP_COUNT-1:0]       sfp_rx_p,
  input [SFP_COUNT-1:0]       sfp_rx_n,
  output[SFP_COUNT-1:0]       sfp_tx_p,
  output[SFP_COUNT-1:0]       sfp_tx_n,
  output[SFP_COUNT-1:0]       sfp_tx_disable,
  output[SFP_COUNT-1:0]       led,

  input                       PHY_rgmii_rxc    [PHY_COUNT-1:0],
  input                       PHY_rgmii_rx_ctl [PHY_COUNT-1:0],
  input [3:0]                 PHY_rgmii_rxd    [PHY_COUNT-1:0],
  output                      PHY_rgmii_txc    [PHY_COUNT-1:0],
  output                      PHY_rgmii_tx_ctl [PHY_COUNT-1:0],
  output[3:0]                 PHY_rgmii_txd    [PHY_COUNT-1:0],
  output reg[1:0]             PHY_link_st      [PHY_COUNT-1:0],

  input                            dram_rst,
  input                            dram_clk,
  input                            dram_init_calib_complete,
  output                           dram_test_err_out,
  output[DRAM_APP_CMD_WIDTH-1  :0] dram_app_cmd,
  output                           dram_app_en,
  input                            dram_app_rdy,
  output[DRAM_ADDR_WIDTH-1     :0] dram_addr,
  output[DRAM_APP_DATA_WIDTH-1 :0] dram_app_wdf_data,
  output                           dram_app_wdf_end,
  output[DRAM_APP_DATA_LENGTH-1:0] dram_app_wdf_mask,
  output                           dram_app_wdf_wren,
  input                            dram_app_wdf_rdy,
  input [DRAM_APP_DATA_WIDTH-1 :0] dram_app_rd_data,
  input                            dram_app_rd_data_end,
  input                            dram_app_rd_data_valid
);
// ===============================================================================
localparam TEMAC_TX_APPEND_FCS   = 1;
localparam TEMAC_DATA_WIDTH      = BYTE_WIDTH;
localparam TEMAC_KEEP_WIDTH      = (TEMAC_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH;
localparam SFP_DATA_WIDTH        = 64;
localparam SFP_KEEP_WIDTH        = (SFP_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH;
localparam IS_USE_DRAM_BUFFER    = (DRAM_ADDR_WIDTH > 0 && DRAM_APP_DATA_WIDTH > 0);
//////////////////////////////////////////////////////////////////////////////////
assign sfp_tx_disable = {SFP_COUNT{1'b0}};
// -------------------------------------------------------------------------------
wire   xcvr_ctrl_clk  = sysclk_100m_in;
wire   xcvr_ctrl_rst  = sys_reset_in;
//////////////////////////////////////////////////////////////////////////////////
localparam RUNNING_TTS_LENGTH = 8; // 固定 8 bytes, 用來檢查設備是否有重啟;
localparam RUNNING_TTS_WIDTH  = RUNNING_TTS_LENGTH * BYTE_WIDTH;
localparam F9PHDR_TTS_LENGTH  = 7;
localparam F9PHDR_TTS_WIDTH   = F9PHDR_TTS_LENGTH * BYTE_WIDTH;
localparam GRAY_WIDTH         = F9PHDR_TTS_WIDTH;
`include "func_gray.vh"

wire                       tts_clk;
reg[RUNNING_TTS_WIDTH-1:0] tts_uint = 0;
reg[GRAY_WIDTH-1:0]        tts_gray = 0;
always @(posedge tts_clk) begin
  tts_uint <= tts_uint + 1;
  tts_gray <= int2gray(tts_uint[F9PHDR_TTS_WIDTH-1:0]);
  if (sys_reset_in) begin
    tts_uint <= 0;
    tts_gray <= 0;
  end
end
//////////////////////////////////////////////////////////////////////////////////
localparam F9DEV_SN_LENGTH = 8;
localparam F9DEV_SN_WIDTH  = F9DEV_SN_LENGTH * BYTE_WIDTH;
wire[F9DEV_SN_WIDTH-1:0]   f9dev_sn;
// -------------------------------------------------------------------------------
wire                       is_f9pcap_en; // 抓包功能是否啟用?
wire[IP_ADDR_WIDTH -1:0]   f9pcap_mcgroup_addr;
wire[IP_PORT_WIDTH -1:0]   f9pcap_mcgroup_port;
wire[MAC_ADDR_WIDTH-1:0]   f9pcap_src_mac_addr;
wire[IP_ADDR_WIDTH -1:0]   f9pcap_src_ip_addr;
wire[IP_PORT_WIDTH -1:0]   f9pcap_src_port;
// -------------------------------------------------------------------------------
// 為了避免 Windows 在 [封包密集] 時, 會漏包、亂序, 所以設定封包之間的最小間隔;
localparam SGAP_MAX_NS  = 1_000_000_000;
localparam SGAP_CLK_NS  = 8;
localparam SGAP_MAX_CNT = SGAP_MAX_NS / SGAP_CLK_NS;
localparam SGAP_WIDTH   = $clog2(SGAP_MAX_CNT);
wire[SGAP_WIDTH-1:0]       sgap_cfg;
// -------------------------------------------------------------------------------
wire                       sfp_rx_rst  [SFP_COUNT-1:0];
wire                       sfp_rx_clk  [SFP_COUNT-1:0];
wire                       sfp_rx_valid[SFP_COUNT-1:0];
wire [SFP_DATA_WIDTH-1:0]  sfp_rx_data [SFP_COUNT-1:0];
wire [SFP_KEEP_WIDTH-1:0]  sfp_rx_keep [SFP_COUNT-1:0];
wire                       sfp_rx_last [SFP_COUNT-1:0];
wire                       sfp_rx_err  [SFP_COUNT-1:0];
// -------------------------------------------------------------------------------
wire                       temac_link_ready[PHY_COUNT-1:0];
wire                       temac_tx_rst    [PHY_COUNT-1:0];
wire                       temac_tx_clk    [PHY_COUNT-1:0];
wire                       temac_tx_valid  [PHY_COUNT-1:0];
wire                       temac_tx_ready  [PHY_COUNT-1:0];
wire[TEMAC_DATA_WIDTH-1:0] temac_tx_data   [PHY_COUNT-1:0];
wire                       temac_tx_last   [PHY_COUNT-1:0];
// ===============================================================================
wire  dev_st_rst;
wire  dev_st_clk = tts_clk;
sync_reset
sync_dev_st_rst_i(
  .clk    (dev_st_clk   ),
  .rst_in (sys_reset_in ),
  .rst_out(dev_st_rst   )
);
// ---------------------
localparam DEV_ST_BUF_LENGTH = 16*3 + DEV_ST_RECOVER_INFO_L;
localparam DEV_ST_BUF_WIDTH  = DEV_ST_BUF_LENGTH * BYTE_WIDTH;
wire[DEV_ST_RECOVER_INFO_W-1:0]  dev_st_recover_info;
wire[DEV_ST_BUF_WIDTH-1:0] dev_st_buffer = {
    DEV_ST_BUF_LENGTH[IP_2BYTES_WIDTH-1:0],  // --+[2]
    16'h0001,                                //   |[2] Ver;
    f9dev_sn,                                //   |[8]
    {(16-12){8'h00}},                        // --+ 此區共 16 bytes;
                                             //
    F9PHDR_TTS_LENGTH[BYTE_WIDTH-1:0],       // --+
    (IS_USE_DRAM_BUFFER ? F9PCAP_SEQNO_LENGTH    [BYTE_WIDTH-1:0] : 8'h00),
    (IS_USE_DRAM_BUFFER ? RECOVER_REQ_ADDR_FROM_L[BYTE_WIDTH-1:0] : 8'h00),
    (IS_USE_DRAM_BUFFER ? RECOVER_REQ_CHECK_L    [BYTE_WIDTH-1:0] : 8'h00),
    (IS_USE_DRAM_BUFFER ? RECOVER_REQ_COUNT_L    [BYTE_WIDTH-1:0] : 8'h00),
    {(16-5){8'h00}},                         // --+ 此區共 16 bytes;
                                             //
    tts_uint,                                // --+ [RUNNING_TTS_LENGTH]
    {(16-RUNNING_TTS_LENGTH){8'h00}},        // --+ 此區共 16 bytes
                                             //
    dev_st_recover_info                      // [DEV_ST_RECOVER_INFO_L]
  };                                         //= 16*3 + DEV_ST_RECOVER_INFO_L;
// ---------------------
localparam longint DEV_ST_INTERVAL_CNT = 30 * 1_000_000_000 * 10 / 64; // 約 30 秒;
localparam longint DEV_ST_DELAY_CNT    =  1 * 1_000_000_000 * 10 / 64; // 約  1 秒;
localparam longint DEV_ST_FORCE_CNT    = 10 *         1_000 * 10 / 64; // 約 10 us;
localparam         DEV_ST_CNT_WIDTH    = $clog2(DEV_ST_INTERVAL_CNT);
reg [DEV_ST_CNT_WIDTH-1:0] dev_st_cnt;
// ---------------------
// SystemVerilog packed & unpacked:
// https://www.consulting.amiq.com/2017/06/23/how-to-unpack-data-using-the-systemverilog-streaming-operators-2/
reg                  dev_st_resend_chkp[PHY_COUNT-1:0];
wire[PHY_COUNT-1:0]  dev_st_resend_chku = {>>{dev_st_resend_chkp}};
reg                  dev_st_delay_resend;
wire                 dev_st_force_resend;
reg                  dev_st_valid = 0;
// ---------------------
wire f9mg_rx_join;
wire SYN_f9mg_rx_join;
// 避免 f9mg_rx_join 的 clk domain 週期較 dev_st_clk 短,
// 可能造成在 dev_st_clk domain 擷取不到,
// 所以使用 sync_reset;
sync_reset
sync_f9mg_rx_join_i(
  .clk     (dev_st_clk       ),
  .rst_in  (f9mg_rx_join     ),
  .rst_out (SYN_f9mg_rx_join )
);
// ---------------------
always @(posedge dev_st_clk) begin
  dev_st_resend_chkp  <= temac_link_ready;
  dev_st_delay_resend <= (dev_st_resend_chkp != temac_link_ready);
  dev_st_cnt          <= dev_st_cnt - 1;
  dev_st_valid        <= (dev_st_cnt == 0) | SYN_f9mg_rx_join;
  // -----
  if (dev_st_force_resend) begin
    dev_st_cnt <= DEV_ST_FORCE_CNT[DEV_ST_CNT_WIDTH-1:0];
  end else if (dev_st_delay_resend) begin
    dev_st_cnt <= DEV_ST_DELAY_CNT[DEV_ST_CNT_WIDTH-1:0] - 2; // - 2 從 dev_st_valid 到實際送出的調整;
  end
  // -----
  if (dev_st_rst | dev_st_valid) begin
    dev_st_valid <= 0;
    dev_st_cnt   <= DEV_ST_INTERVAL_CNT[DEV_ST_CNT_WIDTH-1:0] - 2;
  end
end
// -----
reg is_dev_info_sent; // dev info 送出之前, 先不要送抓到的封包;
always @(posedge dev_st_clk) begin
  is_dev_info_sent <= is_dev_info_sent;
  if (dev_st_rst | dev_st_resend_chku == 0) begin
    is_dev_info_sent <= 0;
  end else if (dev_st_valid) begin
    is_dev_info_sent <= 1;
  end
end
// ===============================================================================
wire                        f9mg_recover_req_clk = dram_clk;
wire                        f9mg_recover_req_pop;
wire                        f9mg_recover_req_valid;
wire[RECOVER_REQ_WIDTH-1:0] f9mg_recover_req_data;
// ===============================================================================
f9pcap_sfp_to_temac #(
  .PHY_COUNT               (PHY_COUNT               ),
  .TEMAC_DATA_WIDTH        (TEMAC_DATA_WIDTH        ),
  .SFP_COUNT               (SFP_COUNT               ),
  .SFP_DATA_WIDTH          (SFP_DATA_WIDTH          ),
  .SGAP_WIDTH              (SGAP_WIDTH              ),
  .TTS_WIDTH               (F9PHDR_TTS_WIDTH        ),
  .FRAME_MAX_LENGTH        (FRAME_MAX_LENGTH        ),
  .F9HDR_BUFFER_LENGTH     (F9HDR_BUFFER_LENGTH     ),
  .TEMAC_OUT_BUFFER_LENGTH (TEMAC_OUT_BUFFER_LENGTH ),
  .DEV_ST_BUF_LENGTH       (DEV_ST_BUF_LENGTH       ),
  .DRAM_ADDR_WIDTH         (DRAM_ADDR_WIDTH         ),
  .DRAM_APP_DATA_LENGTH    (DRAM_APP_DATA_LENGTH    ),
  .DRAM_BURST_SIZE_BITS    (DRAM_BURST_SIZE_BITS    ),
  .IS_USE_DRAM_BUFFER      (IS_USE_DRAM_BUFFER      )
)
f9pcap_i(
  .sys_rst_in            (sys_reset_in                    ),
  .tts_uint_in           (tts_uint[F9PHDR_TTS_WIDTH-1:0]  ),
  .tts_gray_in           (tts_gray                        ),
  .is_f9pcap_en          (is_f9pcap_en & is_dev_info_sent ),
  .f9pcap_mcgroup_addr   (f9pcap_mcgroup_addr ),
  .f9pcap_mcgroup_port   (f9pcap_mcgroup_port ),
  .f9pcap_src_mac_addr   (f9pcap_src_mac_addr ),
  .f9pcap_src_ip_addr    (f9pcap_src_ip_addr  ),
  .f9pcap_src_port       (f9pcap_src_port     ),
  .sgap_cfg_in           (sgap_cfg            ),
  .sfp_rx_rst_in         (sfp_rx_rst          ),
  .sfp_rx_clk_in         (sfp_rx_clk          ),
  .sfp_rx_valid_in       (sfp_rx_valid        ),
  .sfp_rx_data_in        (sfp_rx_data         ),
  .sfp_rx_keep_in        (sfp_rx_keep         ),
  .sfp_rx_last_in        (sfp_rx_last         ),
  .sfp_rx_err_in         (sfp_rx_err          ),
  .temac_tx_rst_in       (temac_tx_rst        ),
  .temac_tx_clk_in       (temac_tx_clk        ),
  .temac_tx_valid_out    (temac_tx_valid      ),
  .temac_tx_ready_in     (temac_tx_ready      ),
  .temac_tx_data_out     (temac_tx_data       ),
  .temac_tx_last_out     (temac_tx_last       ),
  .temac_link_ready      (temac_link_ready    ),
  .dev_st_rst_in         (dev_st_rst          ),
  .dev_st_clk_in         (dev_st_clk          ),
  .dev_st_valid_in       (dev_st_valid        ),
  .dev_st_buf_in         (dev_st_buffer       ),
  .dev_st_recover_info_out(dev_st_recover_info),
  .dev_st_force_resend_out(dev_st_force_resend),

  .dram_rst                 (dram_rst                 ),
  .dram_clk                 (dram_clk                 ),
  .dram_init_calib_complete (dram_init_calib_complete ),
  .dram_test_err_out        (dram_test_err_out        ),
  .dram_app_cmd             (dram_app_cmd             ),
  .dram_app_en              (dram_app_en              ),
  .dram_app_rdy             (dram_app_rdy             ),
  .dram_addr                (dram_addr                ),
  .dram_app_wdf_data        (dram_app_wdf_data        ),
  .dram_app_wdf_end         (dram_app_wdf_end         ),
  .dram_app_wdf_mask        (dram_app_wdf_mask        ),
  .dram_app_wdf_wren        (dram_app_wdf_wren        ),
  .dram_app_wdf_rdy         (dram_app_wdf_rdy         ),
  .dram_app_rd_data         (dram_app_rd_data         ),
  .dram_app_rd_data_end     (dram_app_rd_data_end     ),
  .dram_app_rd_data_valid   (dram_app_rd_data_valid   ),

  .f9mg_recover_req_pop_out  (f9mg_recover_req_pop    ),
  .f9mg_recover_req_valid_in (f9mg_recover_req_valid  ),
  .f9mg_recover_req_data_in  (f9mg_recover_req_data   )
);
//////////////////////////////////////////////////////////////////////////////////
wire                       temac_rx_rst      [PHY_COUNT-1:0];
wire                       temac_rx_clk      [PHY_COUNT-1:0];
wire                       temac_rx_valid    [PHY_COUNT-1:0];
wire[TEMAC_DATA_WIDTH-1:0] temac_rx_data     [PHY_COUNT-1:0];
wire[TEMAC_KEEP_WIDTH-1:0] temac_rx_keep     [PHY_COUNT-1:0];
wire                       temac_rx_frame_end[PHY_COUNT-1:0];
wire                       temac_rx_bad_frame[PHY_COUNT-1:0];
wire                       temac_rx_bad_fcs  [PHY_COUNT-1:0];
wire                       temac_link_1g     [PHY_COUNT-1:0];
//--------------------------------------------------------------------------------
wire                       temac_rx_rst_f9mg;
reg                        temac_rx_clk_f9mg;
reg                        temac_rx_axis_valid_f9mg;
reg [TEMAC_DATA_WIDTH-1:0] temac_rx_axis_data_f9mg;
reg [TEMAC_KEEP_WIDTH-1:0] temac_rx_axis_keep_f9mg;
wire                       temac_rx_axis_last_f9mg;

if (F9MG_PHY_ID >= 0) begin
  assign temac_rx_rst_f9mg = temac_rx_rst[F9MG_PHY_ID];
  assign temac_rx_clk_f9mg = temac_rx_clk[F9MG_PHY_ID];
  temac_rx_to_axis #(
    .TEMAC_DATA_WIDTH (TEMAC_DATA_WIDTH )
  )
  temac_rx_to_axis_i(
    .clk_in                (temac_rx_clk_f9mg               ),
    .temac_rx_valid_in     (temac_rx_valid    [F9MG_PHY_ID] ),
    .temac_rx_data_in      (temac_rx_data     [F9MG_PHY_ID] ),
    .temac_rx_keep_in      (temac_rx_keep     [F9MG_PHY_ID] ),
    .temac_rx_frame_end_in (temac_rx_frame_end[F9MG_PHY_ID] ),
    .axis_valid_out        (temac_rx_axis_valid_f9mg        ),
    .axis_data_out         (temac_rx_axis_data_f9mg         ),
    .axis_keep_out         (temac_rx_axis_keep_f9mg         ),
    .axis_last_out         (temac_rx_axis_last_f9mg         )
  );
end
//////////////////////////////////////////////////////////////////////////////////
for (genvar phyL = 0;  phyL < PHY_COUNT;  phyL = phyL + 1) begin : phy
  wire   temac_duplex;
  wire   temac_link_100m;
  assign PHY_link_st[phyL] = (temac_link_ready[phyL]
                             ? ( temac_link_1g[phyL] ? 2'b10
                               : temac_link_100m     ? 2'b01
                               :                       2'b11 )
                             :                         2'b00);
  // -------------------------------------------------------
  sync_reset  sync_temac_rst_i( .clk(temac_rx_clk[phyL]),  .rst_in(xcvr_ctrl_rst),  .rst_out(temac_rx_rst[phyL]) );
  assign temac_tx_rst[phyL] = temac_rx_rst[phyL];
  assign temac_tx_clk[phyL] = temac_rx_clk[phyL];
  // -------------------------------------------------------
  wire                       mac_gmii_rx_dv;
  wire                       mac_gmii_rx_er;
  wire [7:0]                 mac_gmii_rxd;
  wire                       rgmii_rx_ctl_da;
  wire [3:0]                 rgmii_rxd_da;
  // -----
  rgmii_phy_if_rx
  rgmii_phy_rx_i (
    .rgmii_rxc          (PHY_rgmii_rxc   [phyL] ),
    .rgmii_rx_ctl       (PHY_rgmii_rx_ctl[phyL] ),
    .rgmii_rxd          (PHY_rgmii_rxd   [phyL] ),

    .refclk_out         (temac_rx_clk    [phyL] ),
    .rgmii_rx_ctl_da_out(rgmii_rx_ctl_da        ),
    .rgmii_rxd_da_out   (rgmii_rxd_da           ),

    .mac_gmii_rx_rst_in (temac_rx_rst    [phyL] ),
    .mac_gmii_rx_dv     (mac_gmii_rx_dv         ),
    .mac_gmii_rx_er     (mac_gmii_rx_er         ),
    .mac_gmii_rxd       (mac_gmii_rxd           ),

    .st_link_ready      (temac_link_ready[phyL] ),
    .st_link_1g         (temac_link_1g   [phyL] ),
    .st_link_100m       (temac_link_100m        ),
    .st_duplex          (temac_duplex           )
  );
  // -----
  gmii_temac_rx
  gmii_temac_rx_i (
    .gmii_rx_rst_in     (temac_rx_rst      [phyL] ),
    .gmii_rx_clk_in     (temac_rx_clk      [phyL] ),
    .gmii_rx_dv         (mac_gmii_rx_dv           ),
    .gmii_rx_er         (mac_gmii_rx_er           ),
    .gmii_rxd           (mac_gmii_rxd             ),

    .link_ready_in      (temac_link_ready  [phyL] ),
    .link_1g_in         (temac_link_1g     [phyL] ),
    .rgmii_rx_ctl_da_in (rgmii_rx_ctl_da          ),
    .rgmii_rxd_da_in    (rgmii_rxd_da             ),

    .temac_rx_valid     (temac_rx_valid    [phyL] ),
    .temac_rx_keep      (temac_rx_keep     [phyL] ),
    .temac_rx_data      (temac_rx_data     [phyL] ),
    .temac_rx_frame_end (temac_rx_frame_end[phyL] ),
    .temac_rx_bad_frame (temac_rx_bad_frame[phyL] ),
    .temac_rx_bad_fcs   (temac_rx_bad_fcs  [phyL] ),

    .cfg_rx_enable      (1                        )
  );
  // -------------------------------------
  wire         mac_gmii_tx_en;
  wire         mac_gmii_tx_er;
  wire [7:0]   mac_gmii_txd;
  // -----
  rgmii_phy_if_tx
  rgmii_phy_tx_i (
    .mac_gmii_tx_clk_in (temac_tx_clk    [phyL] ),
    .mac_gmii_tx_rst_in (temac_tx_rst    [phyL] ),
    .mac_gmii_tx_en     (mac_gmii_tx_en         ),
    .mac_gmii_tx_er     (mac_gmii_tx_er         ),
    .mac_gmii_txd       (mac_gmii_txd           ),
    .rgmii_txc          (PHY_rgmii_txc   [phyL] ),
    .rgmii_tx_ctl       (PHY_rgmii_tx_ctl[phyL] ),
    .rgmii_txd          (PHY_rgmii_txd   [phyL] )
  );
  // -----
  gmii_temac_tx #(
    .APPEND_FCS      (TEMAC_TX_APPEND_FCS)
  )
  gmii_temac_tx_i (
    .gmii_tx_rst_in  (temac_tx_rst    [phyL] ),
    .gmii_tx_clk_in  (temac_tx_clk    [phyL] ),
    .gmii_tx_en      (mac_gmii_tx_en         ),
    .gmii_tx_er      (mac_gmii_tx_er         ),
    .gmii_txd        (mac_gmii_txd           ),

    .link_1g_in      (temac_link_1g   [phyL] ),
    .link_ready_in   (temac_link_ready[phyL] ),

    .temac_tx_valid  (temac_tx_valid  [phyL] ),
    .temac_tx_ready  (temac_tx_ready  [phyL] ),
    .temac_tx_data   (temac_tx_data   [phyL] ),
    .temac_tx_last   (temac_tx_last   [phyL] ),

    .cfg_ifg         (8'd12                  ),
    .cfg_tx_enable   (1                      )
  );
end
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
// ----- gt clk: common all cores -----
wire[GTREFCLK_COUNT-1:0]  sfp_gt_refclk;

genvar iL;
for (iL = 0;  iL < GTREFCLK_COUNT;  iL = iL + 1) begin : gtrefclk
  if (IDELAYCTRL_SIM_DEVICE == "ULTRASCALE") begin
    IBUFDS_GTE4
    sfp_gt_refclk_i (
      .I     (sfp_gt_refclk_p[iL]),
      .IB    (sfp_gt_refclk_n[iL]),
      .CEB   (1'b0               ),
      .O     (sfp_gt_refclk  [iL]),
      .ODIV2 (                   )
    );
  end else begin // "7SERIES"
    IBUFDS_GTE2
    sfp_gt_refclk_i (
      .I     (sfp_gt_refclk_p[iL]),
      .IB    (sfp_gt_refclk_n[iL]),
      .CEB   (1'b0               ),
      .O     (sfp_gt_refclk  [iL]),
      .ODIV2 (                   )
    );
  end
end
// -------------------------------------------------------------------------------
wire   sfp_coreclk;
assign tts_clk = sfp_coreclk;
BUFG
coreclk_bufg_i(
  .I (sfp_gt_refclk[0] ),
  .O (sfp_coreclk      )
);
// -------------------------------------------------------------------------------
wire[QUAD_COUNT-1:0] sfp_gt_powergood;
wire[QUAD_COUNT-1:0] sfp_qpll_lock;
wire[QUAD_COUNT-1:0] sfp_qpll_clk;
wire[QUAD_COUNT-1:0] sfp_qpll_refclk;
wire[QUAD_COUNT-1:0] sfp_qpll_reset;
wire[QUAD_COUNT-1:0] sfp_txusrclk;
wire[QUAD_COUNT-1:0] sfp_txusrclk2;

wire[SFP_COUNT-1:0]  sfp_rx_high_ber;
wire[SFP_COUNT-1:0]  dont_cnt_bad_block = 1;
wire[SFP_COUNT-1:0]  dont_cnt_high_ber  = 1;
wire[SFP_COUNT-1:0]  sfp_st_ready;
assign         led = sfp_st_ready;
//////////////////////////////////////////////////////////////////////////////////
wire                       sfp_rx_axis_rst_f9mg;
wire                       sfp_rx_axis_clk_f9mg;
wire                       sfp_rx_axis_tvalid_f9mg;
wire [SFP_DATA_WIDTH-1:0]  sfp_rx_axis_tdata_f9mg;
wire [SFP_KEEP_WIDTH-1:0]  sfp_rx_axis_tkeep_f9mg;
wire                       sfp_rx_axis_tlast_f9mg;

wire                       sfp_tx_axis_rst   [SFP_COUNT-1:0];
wire                       sfp_tx_axis_clk   [SFP_COUNT-1:0];
wire                       sfp_tx_axis_tvalid[SFP_COUNT-1:0];
wire [SFP_DATA_WIDTH-1:0]  sfp_tx_axis_tdata [SFP_COUNT-1:0];
wire [SFP_KEEP_WIDTH-1:0]  sfp_tx_axis_tkeep [SFP_COUNT-1:0];
wire                       sfp_tx_axis_tlast [SFP_COUNT-1:0];

for (genvar sfpL = 0;  sfpL < SFP_COUNT;  sfpL = sfpL + 1) begin : xcvr
  localparam XCVR_QPLL_MASTER = SFP_QPLL_MASTER[sfpL];
  localparam XCVR_QUAD_IDX    = SFP_QUAD_MAP   [sfpL];
  localparam XCVR_REFCLK_IDX  = QUAD_REFCLK_MAP[XCVR_QUAD_IDX];
  // ------------------------------------------------------------------
  if (sfpL == F9MG_SFP_ID) begin
    assign sfp_rx_axis_rst_f9mg    = sfp_rx_rst  [sfpL];
    assign sfp_rx_axis_clk_f9mg    = sfp_rx_clk  [sfpL];
    assign sfp_rx_axis_tvalid_f9mg = sfp_rx_valid[sfpL];
    assign sfp_rx_axis_tdata_f9mg  = sfp_rx_data [sfpL];
    assign sfp_rx_axis_tkeep_f9mg  = sfp_rx_keep [sfpL];
    assign sfp_rx_axis_tlast_f9mg  = sfp_rx_last [sfpL];
  end
  // ------------------------------------------------------------------
  // SFP: 0/1互通; 2/3互通; 4/5互通; 6/7互通; ... 其餘類推;
  // [sfpL:rx] => [PEER_SFP_IDX:tx]
  localparam PEER_SFP_IDX = (sfpL % 2 == 0) ? (sfpL + 1) : (sfpL - 1);
  assign sfp_tx_axis_rst   [PEER_SFP_IDX] = sfp_rx_rst  [sfpL];
  assign sfp_tx_axis_clk   [PEER_SFP_IDX] = sfp_rx_clk  [sfpL];
  assign sfp_tx_axis_tvalid[PEER_SFP_IDX] = sfp_rx_valid[sfpL];
  assign sfp_tx_axis_tdata [PEER_SFP_IDX] = sfp_rx_data [sfpL];
  assign sfp_tx_axis_tkeep [PEER_SFP_IDX] = sfp_rx_keep [sfpL];
  assign sfp_tx_axis_tlast [PEER_SFP_IDX] = sfp_rx_last [sfpL];
  // ==================================================================
  f9pcap_tgbaser_axis #(
    .XCVR_QPLL_MASTER     (XCVR_QPLL_MASTER     ),
    .AXIS_DATA_WIDTH      (SFP_DATA_WIDTH       ),
    .AXIS_KEEP_WIDTH      (SFP_KEEP_WIDTH       ),
    .COUNT_125US          (COUNT_125US          ),
    .TXSEQUENCE_PAUSE     (TXSEQUENCE_PAUSE     )
  )
  tgbaser_axis_i (
    .xcvr_ctrl_clk                (xcvr_ctrl_clk                     ),
    .xcvr_ctrl_rst                (xcvr_ctrl_rst                     ),

    .xcvr_gt_refclk_in            (sfp_gt_refclk    [XCVR_REFCLK_IDX]),
    .xcvr_gt_powergood_out        (sfp_gt_powergood [XCVR_QUAD_IDX]  ),

    .xcvr_qpll_lock_out           (sfp_qpll_lock    [XCVR_QUAD_IDX]  ),
    .xcvr_qpll_clk_out            (sfp_qpll_clk     [XCVR_QUAD_IDX]  ),
    .xcvr_qpll_refclk_out         (sfp_qpll_refclk  [XCVR_QUAD_IDX]  ),
    .xcvr_qpll_lock_in            (sfp_qpll_lock    [XCVR_QUAD_IDX]  ),
    .xcvr_qpll_clk_in             (sfp_qpll_clk     [XCVR_QUAD_IDX]  ),
    .xcvr_qpll_refclk_in          (sfp_qpll_refclk  [XCVR_QUAD_IDX]  ),
    .xcvr_qpll_reset_out          (sfp_qpll_reset   [XCVR_QUAD_IDX]  ),

    .xcvr_txusrclk_to_slave       (sfp_txusrclk     [XCVR_QUAD_IDX]  ),
    .xcvr_txusrclk2_to_slave      (sfp_txusrclk2    [XCVR_QUAD_IDX]  ),
    .xcvr_txusrclk_from_master    (sfp_txusrclk     [XCVR_QUAD_IDX]  ),
    .xcvr_txusrclk2_from_master   (sfp_txusrclk2    [XCVR_QUAD_IDX]  ),

    .xcvr_rx_p                    (sfp_rx_p           [sfpL]         ),
    .xcvr_rx_n                    (sfp_rx_n           [sfpL]         ),
    .xcvr_tx_p                    (sfp_tx_p           [sfpL]         ),
    .xcvr_tx_n                    (sfp_tx_n           [sfpL]         ),

    .st_xcvr_ready                (sfp_st_ready       [sfpL]         ),
    .xcvr_rx_high_ber             (sfp_rx_err         [sfpL]         ),
    .dont_cnt_bad_block           (0                                 ),
    .dont_cnt_high_ber            (0                                 ),

    .rx_axis_rst_out              (sfp_rx_rst         [sfpL]         ),
    .rx_axis_clk_out              (sfp_rx_clk         [sfpL]         ),
    .rx_axis_tvalid               (sfp_rx_valid       [sfpL]         ),
    .rx_axis_tdata                (sfp_rx_data        [sfpL]         ),
    .rx_axis_tkeep                (sfp_rx_keep        [sfpL]         ),
    .rx_axis_tlast                (sfp_rx_last        [sfpL]         ),

    .tx_axis_rst_in               (sfp_tx_axis_rst    [sfpL]         ),
    .tx_axis_clk_in               (sfp_tx_axis_clk    [sfpL]         ),
    .tx_axis_tvalid               (sfp_tx_axis_tvalid [sfpL]         ),
    .tx_axis_tdata                (sfp_tx_axis_tdata  [sfpL]         ),
    .tx_axis_tkeep                (sfp_tx_axis_tkeep  [sfpL]         ),
    .tx_axis_tlast                (sfp_tx_axis_tlast  [sfpL]         )
  );
  // ==================================================================
end
//////////////////////////////////////////////////////////////////////////////////
if (F9MG_PHY_ID >= 0 | F9MG_SFP_ID >= 0) begin
  localparam F9MG_DATA_WIDTH  = (F9MG_PHY_ID < 0 ? SFP_DATA_WIDTH : TEMAC_DATA_WIDTH);
  localparam F9MG_KEEP_WIDTH  = (F9MG_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH;
  wire                       f9mg_axis_rst   = F9MG_PHY_ID < 0 ? sfp_rx_axis_rst_f9mg    : temac_rx_rst_f9mg;
  wire                       f9mg_axis_clk   = F9MG_PHY_ID < 0 ? sfp_rx_axis_clk_f9mg    : temac_rx_clk_f9mg;
  wire                       f9mg_axis_valid = F9MG_PHY_ID < 0 ? sfp_rx_axis_tvalid_f9mg : temac_rx_axis_valid_f9mg;
  wire [F9MG_DATA_WIDTH-1:0] f9mg_axis_data  = F9MG_PHY_ID < 0 ? sfp_rx_axis_tdata_f9mg  : temac_rx_axis_data_f9mg;
  wire [F9MG_KEEP_WIDTH-1:0] f9mg_axis_keep  = F9MG_PHY_ID < 0 ? sfp_rx_axis_tkeep_f9mg  : temac_rx_axis_keep_f9mg;
  wire                       f9mg_axis_last  = F9MG_PHY_ID < 0 ? sfp_rx_axis_tlast_f9mg  : temac_rx_axis_last_f9mg;
  wire                       f9mg_axis_ready = 1;

  f9pcap_dev_f9mg #(
    .DATA_WIDTH                  (F9MG_DATA_WIDTH            ),
    .SYS_CLK_IN_HZ               (100_000_000                ),
    .LOCAL_CMD_SGAP_WIDTH        (SGAP_WIDTH                 ),
    .LOCAL_CMD_RECOVER_REQ_DEPTH (IS_USE_DRAM_BUFFER ? 16 : 0)
  )
  f9mg_i (
    .sys_clk_in                 (sysclk_100m_in         ),
    .sys_rst_in                 (sys_reset_in           ),
    .eeprom_scl_out             (eeprom_scl_out         ),
    .eeprom_sda_io              (eeprom_sda_io          ),

    .is_f9pcap_en_out           (is_f9pcap_en           ),
    .f9mg_rx_join_out           (f9mg_rx_join           ),

    .f9dev_sn_out               (f9dev_sn               ),
    .local_sgap_out             (sgap_cfg               ),
    .f9mg_recover_req_clk_in    (f9mg_recover_req_clk   ),
    .f9mg_recover_req_pop_in    (f9mg_recover_req_pop   ),
    .f9mg_recover_req_valid_out (f9mg_recover_req_valid ),
    .f9mg_recover_req_data_out  (f9mg_recover_req_data  ),

    .axis_rst_in                (f9mg_axis_rst          ),
    .axis_clk_in                (f9mg_axis_clk          ),
    .axis_valid_in              (f9mg_axis_valid        ),
    .axis_ready_in              (f9mg_axis_ready        ),
    .axis_data_in               (f9mg_axis_data         ),
    .axis_keep_in               (f9mg_axis_keep         ),
    .axis_last_in               (f9mg_axis_last         ),

    .f9pcap_mcgroup_addr_out    (f9pcap_mcgroup_addr    ),
    .f9pcap_mcgroup_port_out    (f9pcap_mcgroup_port    ),
    .f9pcap_src_mac_addr_out    (f9pcap_src_mac_addr    ),
    .f9pcap_src_ip_addr_out     (f9pcap_src_ip_addr     ),
    .f9pcap_src_port_out        (f9pcap_src_port        )
  );
end
// ===============================================================================
endmodule
//////////////////////////////////////////////////////////////////////////////////
