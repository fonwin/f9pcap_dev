`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
module f9pcap_stlv_xc7k325t #(
  parameter[7:0]    PHY_COUNT = 2,
  parameter[7:0]    SFP_COUNT = 2,
  parameter integer GTREFCLK_COUNT = 1,
  parameter integer QUAD_COUNT     = 1,
  parameter integer QUAD_REFCLK_MAP[QUAD_COUNT-1 :0] = {    0 },
  parameter integer SFP_QUAD_MAP   [SFP_COUNT -1 :0] = { 0, 0 },
  parameter integer SFP_QPLL_MASTER[SFP_COUNT -1 :0] = { 0, 1 }
)(
  input                 clk_200M_p,
  input                 clk_200M_n,
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
    .TXSEQUENCE_PAUSE       (`TGBASER_XCVR_TXSEQUENCE_PAUSE )
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
    .PHY_link_st        (PHY_link_st         )
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
