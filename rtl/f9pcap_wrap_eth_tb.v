`timescale 1ns / 1ps
module f9pcap_wrap_eth_tb #(
  `include "eth_ip_localparam.vh"
  localparam THIS_IS_DUMMY=0
)(
);
//-///////////////////////////////////////////////////////////////////////////
`include "tgbaser_xcvr_7s32.vh"
localparam TXSEQUENCE_PAUSE     = `TGBASER_XCVR_TXSEQUENCE_PAUSE;
localparam TXSEQUENCE_WIDTH     = TXSEQUENCE_PAUSE==0 ? 1 : $clog2(TXSEQUENCE_PAUSE+1);
localparam TXSEQUENCE_ODD_PAUSE = `TGBASER_XCVR_TXSEQUENCE_ODD_PAUSE;
//-///////////////////////////////////////////////////////////////////////////
`define SIM_FRAME_MIN_LENGTH  32
`include "./sim_tgemac_rx_include.v"
//-///////////////////////////////////////////////////////////////////////////
reg sys_reset = 1;
reg ctrl_clk = 1;
always #4  ctrl_clk = ~ctrl_clk;
// ------------------------------------------------
reg sfp_coreclk = 1;
always #3.2  sfp_coreclk = ~sfp_coreclk;
// ------------------------------------------------
reg sfp_rxclk = 1;
initial begin
  #0.456;
  forever #1.551  sfp_rxclk = ~sfp_rxclk;
end
// ------------------------------------------------
wire sfp_txclk = sfp_rxclk;
//reg sfp_txclk = 1; // period = 3.103
//initial begin
//  #0.123;
//  forever #1.551  sfp_txclk = ~sfp_txclk;
//end
//-///////////////////////////////////////////////////////////////////////////
localparam TTS_WIDTH  = 64;
localparam GRAY_WIDTH = TTS_WIDTH;
`include "./func_gray.vh"

reg[TTS_WIDTH-1:0]   tts_uint = 0;
reg[GRAY_WIDTH-1:0]  tts_gray = 0;
always @(posedge sfp_coreclk) begin
  tts_uint <= tts_uint + 1;
  tts_gray <= int2gray(tts_uint);
  if (sys_reset) begin
    tts_uint <= 0;
    tts_gray <= 0;
  end
end
//-///////////////////////////////////////////////////////////////////////////
localparam DATA_WIDTH = BEAT_DATA_WIDTH;
localparam KEEP_WIDTH = BEAT_KEEP_WIDTH;
// ------------------------------------------------
reg[1:0] sim_rx_busy_cnt    = 0;
reg      sim_rx_ready       = 0;
reg      sim_rx_delay_valid = 0;
assign sim_tgemac_rx_clk   = sfp_rxclk;
assign sim_tgemac_rx_ready = sim_rx_delay_valid & sim_rx_ready;
always @(posedge sim_tgemac_rx_clk) begin
  sim_rx_ready       <= ~sim_rx_ready;
  sim_rx_busy_cnt    <= sim_rx_delay_valid ? sim_rx_busy_cnt : (sim_rx_busy_cnt + 1);
  sim_rx_delay_valid <= (sim_rx_busy_cnt == 1) ? 1'b1 : sim_rx_delay_valid; // valid 間隔 (sim_rx_busy_cnt + 1) cycles; 最少須 2 cycles 填入 f9phdr;
  // -----
  if (sim_tgemac_rx_last & sim_tgemac_rx_ready) begin
    sim_rx_busy_cnt    <= 0;
    sim_rx_delay_valid <= 0;
  end
end
// ------------------------------------------------
assign sim_tgemac_chk_clk  = sfp_txclk;
// ------------------------------------------------
wire                 eth_udp_axis_valid;
wire[DATA_WIDTH-1:0] eth_udp_axis_data;
wire[KEEP_WIDTH-1:0] eth_udp_axis_keep;
wire                 eth_udp_axis_last;

f9pcap_wrap_eth #(
  .FRAME_MAX_LENGTH (FRAME_MAX_LENGTH ),
  .DATA_WIDTH       (DATA_WIDTH       ),
  .TTS_WIDTH        (TTS_WIDTH        )
)
f9pcap_wrap_i(
  .rst_in      (sys_reset           ),
  .clk_in      (sfp_rxclk           ),
  .tts_gray_in (tts_gray            ),

  .i_valid_in  (sim_tgemac_rx_valid & sim_rx_delay_valid),
  .i_data_in   (sim_tgemac_rx_data  ),
  .i_keep_in   (sim_tgemac_rx_ready ? sim_tgemac_rx_keep : {KEEP_WIDTH{1'b0}} ),
  .i_last_in   (sim_tgemac_rx_last  ),
  .i_frame_err (0                   ),

  .o_valid_out (eth_udp_axis_valid  ),
  .o_data_out  (eth_udp_axis_data   ),
  .o_keep_out  (eth_udp_axis_keep   ),
  .o_last_out  (eth_udp_axis_last   ),

  .EthSrcMAC   (48'h010203040506    ),
  .IpSrcAddr   (32'h0a0b0c0d        ),
  .IpDstAddr   (32'hee123456        ),
  .UdpSrcPort  (16'd2000            ),
  .UdpDstPort  (16'h789a            )
);
assign sim_tgemac_chk_valid = eth_udp_axis_valid;
assign sim_tgemac_chk_data  = eth_udp_axis_data;
assign sim_tgemac_chk_keep  = eth_udp_axis_keep;
assign sim_tgemac_chk_last  = eth_udp_axis_last;
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
reg [TXSEQUENCE_WIDTH-1:0] serdes_tx_sequence = 0;
reg                        serdes_tx_pause;
// ------------------------------------------------
reg [TXSEQUENCE_WIDTH-1:0] wait_tx_sequence = 0;
reg                        test_sequence_ok = 0;
always @(posedge sfp_txclk) begin
  test_sequence_ok <= (serdes_tx_sequence == wait_tx_sequence);
  // -----
  if (TXSEQUENCE_ODD_PAUSE) begin // 0..64: pause=1,3,5...63,64,65
    serdes_tx_pause <= (serdes_tx_sequence[TXSEQUENCE_WIDTH-1:1] == TXSEQUENCE_PAUSE/2 - 1) | (~serdes_tx_sequence[0]);
  end else begin // 0..32: pause=32
    serdes_tx_pause <= (serdes_tx_sequence == TXSEQUENCE_PAUSE - 1);
  end
  // -----
  serdes_tx_sequence <= serdes_tx_sequence + 1;
  if (serdes_tx_sequence == TXSEQUENCE_PAUSE) begin
    serdes_tx_sequence <= 0;
  end
end
// ------------------------------------------------
task run_test;
  input[FRAME_MAX_WIDTH-1:0]  test_pattern;
  input[15:0]                 pattern_length;
  begin
    sim_tgemac_chk_id = 0;
    wait_tx_sequence  = 0;
    //repeat(TXSEQUENCE_PAUSE+1) begin
    repeat(1) begin
      wait(test_sequence_ok);
      run_sim_tgemac_rx_and_chk3(test_pattern, pattern_length, 16 + 42);
      wait_tx_sequence = wait_tx_sequence + 1;
    end
  end
endtask
//////////////////////////////////////////////////////////////////////////////////
integer                   datin_pat_size = 32;
reg[FRAME_MAX_WIDTH-1:0]  datin_pat = {
//                              {FRAME_MAX_WIDTH{1'b0}} };
//64'hff_fe_fd_fc_fb_fa_f9_f8,  64'hf7_f6_f5_f4_f3_f2_f1_f0,
//64'hef_ee_ed_ec_eb_ea_e9_e8,  64'he7_e6_e5_e4_e3_e2_e1_e0,
//64'hdf_de_dd_dc_db_da_d9_d8,  64'hd7_d6_d5_d4_d3_d2_d1_d0,
//64'hcf_ce_cd_cc_cb_ca_c9_c8,  64'hc7_c6_c5_c4_c3_c2_c1_c0,
//64'hbf_be_bd_bc_bb_ba_b9_b8,  64'hb7_b6_b5_b4_b3_b2_b1_b0,
//64'haf_ae_ad_ac_ab_aa_a9_a8,  64'ha7_a6_a5_a4_a3_a2_a1_a0,
//64'h9f_9e_9d_9c_9b_9a_99_98,  64'h97_96_95_94_93_92_91_90,
//64'h8f_8e_8d_8c_8b_8a_89_88,  64'h87_86_85_84_83_82_81_80,
//64'h7f_7e_7d_7c_7b_7a_79_78,  64'h77_76_75_74_73_72_71_70,
//64'h6f_6e_6d_6c_6b_6a_69_68,  64'h67_66_65_64_63_62_61_60,
//64'h5f_5e_5d_5c_5b_5a_59_58,  64'h57_56_55_54_53_52_51_50,
//64'h4f_4e_4d_4c_4b_4a_49_48,  64'h47_46_45_44_43_42_41_40,
//64'h3f_3e_3d_3c_3b_3a_39_38,  64'h37_36_35_34_33_32_31_30,
//64'h2f_2e_2d_2c_2b_2a_29_28,  64'h27_26_25_24_23_22_21_20,
  64'h1f_1e_1d_1c_1b_1a_19_18,  64'h17_16_15_14_13_12_11_10,
  64'h0f_0e_0d_0c_0b_0a_09_08,  64'h07_06_05_04_03_02_01_00
};
// ------------------------------------------------
initial begin
  sys_reset = 1;
  repeat(100) @(posedge ctrl_clk);
  sys_reset = 0;
  repeat(10) @(posedge ctrl_clk);
  // -----
  repeat(FRAME_MAX_LENGTH-32) begin
    $display("Start test: frame size=%d", datin_pat_size);
    run_test(datin_pat & ({FRAME_MAX_WIDTH{1'b1}} >> (FRAME_MAX_WIDTH - datin_pat_size*8)), datin_pat_size);
    datin_pat_size = datin_pat_size + 1;
    datin_pat      = (datin_pat << 8) | datin_pat_size[7:0];
  end
  // -----
  $display("Test end!");
  repeat(100) @(posedge ctrl_clk);
  $finish; 
end
//////////////////////////////////////////////////////////////////////////////
endmodule
//////////////////////////////////////////////////////////////////////////////
