`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
module f9pcap_stlv_xc7k325t_dram #(
  parameter[7:0]    PHY_COUNT = 2,
  parameter[7:0]    SFP_COUNT = 2,
  parameter integer GTREFCLK_COUNT = 1,
  parameter integer QUAD_COUNT     = 1,
  parameter integer QUAD_REFCLK_MAP[QUAD_COUNT-1 :0] = {    0 },
  parameter integer SFP_QUAD_MAP   [SFP_COUNT -1 :0] = { 0, 0 },
  parameter integer SFP_QPLL_MASTER[SFP_COUNT -1 :0] = { 0, 1 },
  
  localparam USE_DRAM_BUFFER = 1
)(
  /// 這裡的 ddr3_* 在 xdc 裡面不必逐個設定(已在 .prj 設定),
  /// 僅需增加底下設定即可:
  /// set_property DCI_CASCADE {32 34} [get_iobanks 33]
  input                 ddr3_sys_clk_p,
  input                 ddr3_sys_clk_n,
  inout  [63 : 0]       ddr3_dq,
  inout  [7  : 0]       ddr3_dqs_p,
  inout  [7  : 0]       ddr3_dqs_n,
  output [14 : 0]       ddr3_addr,
  output [2  : 0]       ddr3_ba,
  output                ddr3_ras_n,
  output                ddr3_reset_n,
  output                ddr3_cas_n,
  output                ddr3_we_n,
  output [0 : 0]        ddr3_ck_p,
  output [0 : 0]        ddr3_ck_n,
  output [0 : 0]        ddr3_cke,
  output [0 : 0]        ddr3_cs_n,
  output [7 : 0]        ddr3_dm,
  output [0 : 0]        ddr3_odt,

//input                 clk_200M_p,
//input                 clk_200M_n,
  input                 clk_50M,
  output                eeprom_scl,
  inout                 eeprom_sda,

  input                 sfp_gt_refclk_p,
  input                 sfp_gt_refclk_n,
  input [SFP_COUNT-1:0] sfp_rx_p,
  input [SFP_COUNT-1:0] sfp_rx_n,
  output[SFP_COUNT-1:0] sfp_tx_p,
  output[SFP_COUNT-1:0] sfp_tx_n,
  output[7:0]           led,
//input                 key2,
//input                 key3,

  output                PHY_rgmii_reset  [PHY_COUNT-1:0],
//output                PHY_rgmii_mdc    [PHY_COUNT-1:0],
//inout                 PHY_rgmii_mdio   [PHY_COUNT-1:0],

  input                 PHY_rgmii_rxc    [PHY_COUNT-1:0],
  input                 PHY_rgmii_rx_ctl [PHY_COUNT-1:0],
  input [3:0]           PHY_rgmii_rxd    [PHY_COUNT-1:0],
  output                PHY_rgmii_txc    [PHY_COUNT-1:0],
  output                PHY_rgmii_tx_ctl [PHY_COUNT-1:0],
  output[3:0]           PHY_rgmii_txd    [PHY_COUNT-1:0]
);
// ===========================================================================
  localparam IDELAYCTRL_SIM_DEVICE = `TGBASER_XCVR_FAMILY;
  // ---------------------------------------------------------
  wire sys_reset;
  wire sysclk_100m;
  sys_ctrl #(
    .RESET_COUNT_NS        (15_000_000           ),
    .IDELAYCTRL_SIM_DEVICE (IDELAYCTRL_SIM_DEVICE)
  )
  sys_ctrl_inst(
    .sysclk_single_in (clk_50M         ),
    .sysclk_100m_out  (sysclk_100m     ),
    .user_reset_in    (1'b0            ),
    .sys_reset_out    (sys_reset       )
  );
//////////////////////////////////////////////////////////////////////////////
  wire[SFP_COUNT-1:0] tunnel_led;
  // ----------------------------------------------
  genvar sfpL;
  for (sfpL = 0;  sfpL < SFP_COUNT;  sfpL = sfpL + 1) begin
    assign led[sfpL*2] = ~tunnel_led[sfpL];
  end
//////////////////////////////////////////////////////////////////////////////
  localparam BYTE_WIDTH           = 8;
  localparam DRAM_BYTE_WIDTH      = BYTE_WIDTH;
  /// 2G, 每個 addr 對應 8 bytes (DRAM_PAYLOAD_WIDTH);
  /// 所以若用 byte 來定位 = DRAM_APP_ADDR_WIDTH + $clog2(DRAM_PAYLOAD_WIDTH / DRAM_BYTE_WIDTH) = 31 bits = 2G;
  localparam DRAM_APP_ADDR_WIDTH  = 28;
  /// 数据从内存控制器传输到系统接口时的总宽度;
  localparam DRAM_PAYLOAD_WIDTH   = 64;
  /// (4:1) = 1 ui_clk cycle = 4 DRAM clk cycles;
  localparam DRAM_nCK_PER_CLK     = 4;
  /// 一個 ui_clk cycle, DRAM 可以傳輸幾個 DRAM_PAYLOAD_WIDTH?
  /// 2 = double data rate: DRAM 在一個完整的時脈週期(上升沿和下降沿), 可傳輸 2 次;
  localparam DRAM_UI_PAYLOAD_CNT  = 2 * DRAM_nCK_PER_CLK;
  /// 一次有效的 wr/rd cmd (1 ui_clk cycle), 可傳輸的資料量 = 512 bits = 64 bytes;
  localparam DRAM_APP_DATA_WIDTH  = DRAM_UI_PAYLOAD_CNT * DRAM_PAYLOAD_WIDTH;
  localparam DRAM_APP_DATA_LENGTH = DRAM_APP_DATA_WIDTH / DRAM_BYTE_WIDTH;
  /// app_wdf_data 裡面, 哪些 byte 不用寫入: 0=要寫, 1=不寫;
  localparam DRAM_APP_MASK_WIDTH  = DRAM_APP_DATA_WIDTH / DRAM_BYTE_WIDTH;
  localparam DRAM_APP_CMD_WIDTH   = 3;
  localparam DRAM_BURST_LENGTH    = 8;
  localparam DRAM_BURST_SIZE_BITS = DRAM_BURST_LENGTH * DRAM_PAYLOAD_WIDTH;

  wire[DRAM_APP_ADDR_WIDTH-1:0]  dram_app_addr;
  wire[DRAM_APP_CMD_WIDTH-1 :0]  dram_app_cmd;
  wire                           dram_app_en;
  wire                           dram_app_rdy; // 由 MIG 提供, 類似 axis_ready 訊號, 告知已接受: app_en、app_addr、app_cmd;
  wire[DRAM_APP_DATA_WIDTH-1:0]  dram_app_rd_data;
  wire                           dram_app_rd_data_end;
  wire                           dram_app_rd_data_valid;
  wire[DRAM_APP_DATA_WIDTH-1:0]  dram_app_wdf_data;
  wire                           dram_app_wdf_end;
  wire[DRAM_APP_MASK_WIDTH-1:0]  dram_app_wdf_mask;
  wire                           dram_app_wdf_rdy;
  wire                           dram_app_sr_active;
  wire                           dram_app_ref_ack;
  wire                           dram_app_zq_ack;
  wire                           dram_app_wdf_wren;
  wire                           dram_clk;
  wire                           dram_rst;
  wire                           dram_ip_rst = sys_reset;
  wire                           dram_init_calib_complete;

  localparam DRAM_BURST_ADDR_SHIFT = 3;
  localparam DRAM_BURST_ADDR_WIDTH = DRAM_APP_ADDR_WIDTH - DRAM_BURST_ADDR_SHIFT;
  localparam DRAM_ADDR_WIDTH       = DRAM_BURST_ADDR_WIDTH;
  wire[DRAM_ADDR_WIDTH-1:0] dram_addr;
  assign  dram_app_addr = { dram_addr, {DRAM_BURST_ADDR_SHIFT{1'b0}} };

if (USE_DRAM_BUFFER) begin
  ddr
  ddr_i(
    .sys_clk_p           (ddr3_sys_clk_p ),
    .sys_clk_n           (ddr3_sys_clk_n ),
    .sys_rst             (~dram_ip_rst   ),

    .ddr3_addr           (ddr3_addr      ),
    .ddr3_ba             (ddr3_ba        ),
    .ddr3_cas_n          (ddr3_cas_n     ),
    .ddr3_ck_n           (ddr3_ck_n      ),
    .ddr3_ck_p           (ddr3_ck_p      ),
    .ddr3_cke            (ddr3_cke       ),
    .ddr3_ras_n          (ddr3_ras_n     ),
    .ddr3_reset_n        (ddr3_reset_n   ),
    .ddr3_we_n           (ddr3_we_n      ),
    .ddr3_dq             (ddr3_dq        ),
    .ddr3_dqs_n          (ddr3_dqs_n     ),
    .ddr3_dqs_p          (ddr3_dqs_p     ),
    .ddr3_cs_n           (ddr3_cs_n      ),
    .ddr3_dm             (ddr3_dm        ),
    .ddr3_odt            (ddr3_odt       ),
    .device_temp         (               ),

    .init_calib_complete (dram_init_calib_complete ),
    .ui_clk              (dram_clk                 ),
    .ui_clk_sync_rst     (dram_rst                 ),

    .app_addr            (dram_app_addr            ),
    .app_cmd             (dram_app_cmd             ),
    .app_en              (dram_app_en              ),
    .app_rdy             (dram_app_rdy             ),

    .app_wdf_rdy         (dram_app_wdf_rdy         ),
    .app_wdf_data        (dram_app_wdf_data        ),
    .app_wdf_end         (dram_app_wdf_end         ),
    .app_wdf_wren        (dram_app_wdf_wren        ),
    .app_wdf_mask        (dram_app_wdf_mask        ),

    .app_rd_data         (dram_app_rd_data         ),
    .app_rd_data_end     (dram_app_rd_data_end     ),
    .app_rd_data_valid   (dram_app_rd_data_valid   ),

    .app_sr_req          (1'b0                     ),
    .app_ref_req         (1'b0                     ),
    .app_zq_req          (1'b0                     ),
    .app_sr_active       (dram_app_sr_active       ),
    .app_ref_ack         (dram_app_ref_ack         ),
    .app_zq_ack          (dram_app_zq_ack          )
  );
end
//////////////////////////////////////////////////////////////////////////////
  wire[1:0] PHY_link_st[PHY_COUNT-1:0]; // 2'b00:無連線; 2'b10:1G; 2'b01:100M; 2'b11:10M;
  // -----
  f9pcap_dev_top #(
    .SFP_COUNT              (SFP_COUNT                      ),
    .PHY_COUNT              (PHY_COUNT                      ),
    .GTREFCLK_COUNT         (GTREFCLK_COUNT                 ),
    .QUAD_COUNT             (QUAD_COUNT                     ),
    .QUAD_REFCLK_MAP        (QUAD_REFCLK_MAP                ),
    .SFP_QUAD_MAP           (SFP_QUAD_MAP                   ),
    .SFP_QPLL_MASTER        (SFP_QPLL_MASTER                ),
    .IDELAYCTRL_SIM_DEVICE  (IDELAYCTRL_SIM_DEVICE          ),
    .TXSEQUENCE_PAUSE       (`TGBASER_XCVR_TXSEQUENCE_PAUSE ),
    .DRAM_APP_CMD_WIDTH     (DRAM_APP_CMD_WIDTH             ),
    .DRAM_ADDR_WIDTH        (USE_DRAM_BUFFER ? DRAM_ADDR_WIDTH : 0),
    .DRAM_BURST_SIZE_BITS   (DRAM_BURST_SIZE_BITS           ),
    .DRAM_APP_DATA_LENGTH   (DRAM_APP_DATA_LENGTH           ),
    .F9HDR_BUFFER_LENGTH    ((USE_DRAM_BUFFER ? (2 * 1024 * 512) : (512       * 64)) / BYTE_WIDTH),
    .TEMAC_OUT_BUFFER_LENGTH((USE_DRAM_BUFFER ? (128      * 512) : (16 * 1024 * 64)) / BYTE_WIDTH)
  )
  f9pcap_dev_i(
    .sysclk_100m_in     (sysclk_100m         ),
    .sys_reset_in       (sys_reset           ),
    .eeprom_scl_out     (eeprom_scl          ),
    .eeprom_sda_io      (eeprom_sda          ),

    .sfp_gt_refclk_p    (sfp_gt_refclk_p     ),
    .sfp_gt_refclk_n    (sfp_gt_refclk_n     ),
    .sfp_rx_p           (sfp_rx_p            ),
    .sfp_rx_n           (sfp_rx_n            ),
    .sfp_tx_p           (sfp_tx_p            ),
    .sfp_tx_n           (sfp_tx_n            ),
    .sfp_tx_disable     (                    ),
    .led                (tunnel_led          ),

    .PHY_rgmii_rxc      (PHY_rgmii_rxc       ),
    .PHY_rgmii_rx_ctl   (PHY_rgmii_rx_ctl    ),
    .PHY_rgmii_rxd      (PHY_rgmii_rxd       ),
    .PHY_rgmii_txc      (PHY_rgmii_txc       ),
    .PHY_rgmii_tx_ctl   (PHY_rgmii_tx_ctl    ),
    .PHY_rgmii_txd      (PHY_rgmii_txd       ),
    .PHY_link_st        (PHY_link_st         ),

    .dram_rst                 (dram_rst                  ),
    .dram_clk                 (dram_clk                  ),
    .dram_init_calib_complete (dram_init_calib_complete  ),
    .dram_test_err_out        (dram_test_err             ),
    .dram_app_cmd             (dram_app_cmd              ),
    .dram_app_en              (dram_app_en               ),
    .dram_app_rdy             (dram_app_rdy              ),
    .dram_addr                (dram_addr                 ),
    .dram_app_wdf_data        (dram_app_wdf_data         ),
    .dram_app_wdf_end         (dram_app_wdf_end          ),
    .dram_app_wdf_mask        (dram_app_wdf_mask         ),
    .dram_app_wdf_wren        (dram_app_wdf_wren         ),
    .dram_app_wdf_rdy         (dram_app_wdf_rdy          ),
    .dram_app_rd_data         (dram_app_rd_data          ),
    .dram_app_rd_data_end     (dram_app_rd_data_end      ),
    .dram_app_rd_data_valid   (dram_app_rd_data_valid    )
  );
//////////////////////////////////////////////////////////////////////////////
  reg[25:0] flash_counter = 0;
  wire      flash_sig     = flash_counter[25]; // = 33554432*10 / (10^9) = 0.335544320 秒;
  always @(posedge sysclk_100m)  begin
    flash_counter <= flash_counter + 1;
    if (sys_reset) begin
      flash_counter <= 0;
    end
  end
  // --------------------------
  wire breath_led_w;
  breath_led #(
    .PWM_FULL  ( 2000       ),

    .PWM_MAX   ( 2000       ),
    .LV_ABOVE  (   50       ),
    .PWM_HIGH  (  500       ),

    .LV_MIDDLE (  200       ),

    .PWM_LOW   (   30       ),
    .LV_BELOW  (  150       ),
    .PWM_MIN   (    2       ),

    .LED_OUT_0_IS_DARK (0   )  // si_0001 的 led: 1=dark; 0=light;
  )
  breath_bleds_i(
   .sys_clk    (sysclk_100m   ),
   .sys_reset  (sys_reset     ),
   .led_out    (breath_led_w  )
  );
  // --------------------------
  // PHY: 呼吸:100M; 恆亮:1G; 閃爍:10M; 不亮:無連線;
  wire rj45_100m_led = breath_led_w;
  // --------------------------
  genvar phyL;
  for (phyL = 0;  phyL < PHY_COUNT;  phyL = phyL + 1) begin
    assign PHY_rgmii_reset[phyL] = ~sys_reset;
    assign led[phyL*2 + 1] = ( PHY_link_st[phyL] == 2'b01 ? rj45_100m_led // 100M
                             : PHY_link_st[phyL] == 2'b10 ? 1'b0          // 1G
                             : PHY_link_st[phyL] == 2'b11 ? flash_sig     // 10M
                             :                              1'b1 );
  end
// ===========================================================================
endmodule
//////////////////////////////////////////////////////////////////////////////
