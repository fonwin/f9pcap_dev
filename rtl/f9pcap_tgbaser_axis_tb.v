`timescale 1ns / 1ps
/*
set work_directory [get_property DIRECTORY [current_project]]; cd $work_directory; pwd
add_files ../rtl/f9pcap_tgbaser_axis_tb.v
set_property top f9pcap_tgbaser_axis_tb [get_filesets sim_1]
*/
module f9pcap_tgbaser_axis_tb();
//-///////////////////////////////////////////////////////////////////////////
`include "tgbaser_xcvr_7s32.vh"
localparam TXSEQUENCE_PAUSE     = `TGBASER_XCVR_TXSEQUENCE_PAUSE;
localparam TXSEQUENCE_WIDTH     = TXSEQUENCE_PAUSE==0 ? 1 : $clog2(TXSEQUENCE_PAUSE+1);
localparam TXSEQUENCE_ODD_PAUSE = `TGBASER_XCVR_TXSEQUENCE_ODD_PAUSE;
localparam COUNT_125US          = 100;//125000/6.4;
//-///////////////////////////////////////////////////////////////////////////
`define  SIM_FRAME_MIN_LENGTH    16
`include "./sim_tgemac_rx_include.v"
//-///////////////////////////////////////////////////////////////////////////
localparam DATA_WIDTH = BEAT_DATA_WIDTH;
localparam KEEP_WIDTH = DATA_WIDTH / 8;
//-///////////////////////////////////////////////////////////////////////////
reg sfp_gt_clk = 1;
always #3.2  sfp_gt_clk = ~sfp_gt_clk;
// ------------------------------------------------
reg ctrl_clk = 1;
always #4  ctrl_clk = ~ctrl_clk;
// ------------------------------------------------
reg   sys_reset = 1;
//-///////////////////////////////////////////////////////////////////////////
//
// sim_tgemac_rx => sim_rx_i(tx_axis) => sim_tx/sim_rx => sim_rx_i(rx_axis)
//
// sim_rx_i(rx_axis) => f9pcap_tgbaser_axis_dut(tx_axis) => sfp_tx/rx => rx_axis(sim_tgemac_chk)
//
//-///////////////////////////////////////////////////////////////////////////
wire                   sim_tx_p;
wire                   sim_tx_n;
wire                   sim_rx_p = sim_tx_p;
wire                   sim_rx_n = sim_tx_n;

wire                   sim_st_ready;
wire                   sim_rx_axis_rst;
wire                   sim_rx_axis_clk;
wire                   sim_rx_axis_tvalid;
wire[DATA_WIDTH-1:0]   sim_rx_axis_tdata;
wire[DATA_WIDTH/8-1:0] sim_rx_axis_tkeep;
wire                   sim_rx_axis_tlast;

tgbaser_axis #(
  .XCVR_QPLL_MASTER     (1                    ),
  .AXIS_DATA_WIDTH      (DATA_WIDTH           ),
  .AXIS_KEEP_WIDTH      (KEEP_WIDTH           ),
  .COUNT_125US          (COUNT_125US          ),
  .ENABLE_PADDING       (0                    ),
  .EXAMPLE_SIMULATION   (1                    ),
  .TXSEQUENCE_PAUSE     (TXSEQUENCE_PAUSE     ),
  .TXSEQUENCE_ODD_PAUSE (TXSEQUENCE_ODD_PAUSE )
)
sim_rx_i (
  .xcvr_ctrl_clk              (ctrl_clk            ),
  .xcvr_ctrl_rst              (sys_reset           ),
  .xcvr_gt_refclk_in          (sfp_gt_clk          ),
  .xcvr_gt_powergood_out      (                    ),
  .xcvr_qpll_lock_out         (                    ),
  .xcvr_qpll_clk_out          (                    ),
  .xcvr_qpll_refclk_out       (                    ),
  .xcvr_qpll_lock_in          (                    ),
  .xcvr_qpll_clk_in           (                    ),
  .xcvr_qpll_refclk_in        (                    ),
  .xcvr_qpll_reset_out        (                    ),
  .xcvr_txusrclk_to_slave     (                    ),
  .xcvr_txusrclk2_to_slave    (                    ),
  .xcvr_txusrclk_from_master  (                    ),
  .xcvr_txusrclk2_from_master (                    ),
  
  .tx_axis_rst                (                    ),
  .tx_axis_clk                (sim_tgemac_rx_clk   ),
  .tx_axis_tready             (sim_tgemac_rx_ready ),
  .tx_axis_tvalid             (sim_tgemac_rx_valid ),
  .tx_axis_tdata              (sim_tgemac_rx_data  ),
  .tx_axis_tkeep              (sim_tgemac_rx_keep  ),
  .tx_axis_tlast              (sim_tgemac_rx_last  ),
  .tx_axis_tuser              (                    ),
  .xcvr_tx_p                  (sim_tx_p            ),
  .xcvr_tx_n                  (sim_tx_n            ),

  .xcvr_rx_p                  (sim_rx_p            ),
  .xcvr_rx_n                  (sim_rx_n            ),
  .rx_axis_rst                (sim_rx_axis_rst     ),
  .rx_axis_clk                (sim_rx_axis_clk     ),
  .rx_axis_tvalid             (sim_rx_axis_tvalid  ),
  .rx_axis_tdata              (sim_rx_axis_tdata   ),
  .rx_axis_tkeep              (sim_rx_axis_tkeep   ),
  .rx_axis_tlast              (sim_rx_axis_tlast   ),
  .rx_axis_tuser              (                    ),

  .st_xcvr_ready              (sim_st_ready        ),
  .xcvr_rx_high_ber           (                    ),
  .dont_cnt_bad_block         (                    ),
  .dont_cnt_high_ber          (                    )
);
// ==================================================================
wire  sfp_tx_p;
wire  sfp_tx_n;
wire  sfp_rx_p = sfp_tx_p;
wire  sfp_rx_n = sfp_tx_n;
wire  sfp_st_ready;

f9pcap_tgbaser_axis #(
  .XCVR_QPLL_MASTER     (1                    ),
  .AXIS_DATA_WIDTH      (DATA_WIDTH           ),
  .AXIS_KEEP_WIDTH      (KEEP_WIDTH           ),
  .COUNT_125US          (COUNT_125US          ),
  .EXAMPLE_SIMULATION   (1                    ),
  .TXSEQUENCE_PAUSE     (TXSEQUENCE_PAUSE     ),
  .TXSEQUENCE_ODD_PAUSE (TXSEQUENCE_ODD_PAUSE )
)
f9pcap_tgbaser_axis_dut (
  .xcvr_ctrl_clk              (ctrl_clk            ),
  .xcvr_ctrl_rst              (sys_reset           ),
  .xcvr_gt_refclk_in          (sfp_gt_clk          ),
  .xcvr_gt_powergood_out      (                    ),
  .xcvr_qpll_lock_out         (                    ),
  .xcvr_qpll_clk_out          (                    ),
  .xcvr_qpll_refclk_out       (                    ),
  .xcvr_qpll_lock_in          (                    ),
  .xcvr_qpll_clk_in           (                    ),
  .xcvr_qpll_refclk_in        (                    ),
  .xcvr_qpll_reset_out        (                    ),
  .xcvr_txusrclk_to_slave     (                    ),
  .xcvr_txusrclk2_to_slave    (                    ),
  .xcvr_txusrclk_from_master  (                    ),
  .xcvr_txusrclk2_from_master (                    ),

  .tx_axis_rst_in             (sim_rx_axis_rst     ),
  .tx_axis_clk_in             (sim_rx_axis_clk     ),
  .tx_axis_tvalid             (sim_rx_axis_tvalid  ),
  .tx_axis_tdata              (sim_rx_axis_tdata   ),
  .tx_axis_tkeep              (sim_rx_axis_tkeep   ),
  .tx_axis_tlast              (sim_rx_axis_tlast   ),
  .xcvr_tx_p                  (sfp_tx_p            ),
  .xcvr_tx_n                  (sfp_tx_n            ),

  .xcvr_rx_p                  (sfp_rx_p            ),
  .xcvr_rx_n                  (sfp_rx_n            ),
  .rx_axis_rst_out            (                    ),
  .rx_axis_clk_out            (sim_tgemac_chk_clk  ),
  .rx_axis_tvalid             (sim_tgemac_chk_valid),
  .rx_axis_tdata              (sim_tgemac_chk_data ),
  .rx_axis_tkeep              (sim_tgemac_chk_keep ),
  .rx_axis_tlast              (sim_tgemac_chk_last ),

  .st_xcvr_ready              (sfp_st_ready        ),
  .xcvr_rx_high_ber           (                    ),
  .dont_cnt_bad_block         (                    ),
  .dont_cnt_high_ber          (                    )
);
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
reg [TXSEQUENCE_WIDTH-1:0] serdes_tx_sequence = 0;
reg                        serdes_tx_pause;
// ------------------------------------------------
reg [TXSEQUENCE_WIDTH-1:0] wait_tx_sequence = 0;
reg                        test_sequence_ok = 0;
always @(posedge sim_tgemac_rx_clk) begin
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
      run_sim_tgemac_rx_and_chk2(test_pattern, pattern_length);
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
  // ----- 大約需要 40 ms, (sfp_st_ready & sim_st_ready) 才會成立;
  wait(sfp_st_ready & sim_st_ready);
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
//////////////////////////////////////////////////////////////////////////////////
endmodule
//////////////////////////////////////////////////////////////////////////////
