`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
module f9pcap_sfp_to_temac_tb #(
  `include "eth_ip_localparam.vh"

  parameter FRAME_MAX_LENGTH        = 1600,
//parameter F9HDR_BUFFER_LENGTH     = FRAME_MAX_LENGTH * 2,
//parameter TEMAC_OUT_BUFFER_LENGTH = FRAME_MAX_LENGTH * 32
  parameter F9HDR_BUFFER_LENGTH     = 512       * 64 / BYTE_WIDTH,
  parameter TEMAC_OUT_BUFFER_LENGTH = 16 * 1024 * 64 / BYTE_WIDTH
);
//================================================================================
reg         sys_rst = 1;
// -------------------------------------
reg         sys_clk = 1;
always #5   sys_clk = ~sys_clk;
// -------------------------------------
reg         sfpcore_clk = 1;
always #3.2 sfpcore_clk = ~sfpcore_clk;
// -------------------------------------
reg         common_sfp_rx_clk = 1;
always #3.1 common_sfp_rx_clk = ~common_sfp_rx_clk;
// -------------------------------------
reg         common_phy_tx_clk = 1;
always #4   common_phy_tx_clk = ~common_phy_tx_clk;
//================================================================================
localparam TTS_WIDTH  = 7 * BYTE_WIDTH;
localparam GRAY_WIDTH = TTS_WIDTH;
`include "func_gray.vh"

reg[TTS_WIDTH-1:0]   tts_uint = 0;
reg[GRAY_WIDTH-1:0]  tts_gray = 0;
always @(posedge sfpcore_clk) begin
  tts_uint <= tts_uint + 1;
  tts_gray <= int2gray(tts_uint);
  if (sys_rst) begin
    tts_uint <= 0;
    tts_gray <= 0;
  end
end
//--------------------------------------------------------------------------------
localparam PHY_COUNT        = 2;
localparam TEMAC_DATA_WIDTH = BYTE_WIDTH;
localparam SFP_COUNT        = 2;
localparam SFP_DATA_LENGTH  = 8;
localparam SFP_DATA_WIDTH   = SFP_DATA_LENGTH * BYTE_WIDTH;
localparam SFP_KEEP_WIDTH   = (SFP_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH;
localparam SGAP_WIDTH       = 16;
genvar sfpL;
genvar phyL;
//--------------------------------------------------------------------------------
wire                       is_f9pcap_en        = 1;
wire[IP_ADDR_WIDTH -1:0]   f9pcap_mcgroup_addr = 32'h01020304;
wire[IP_PORT_WIDTH -1:0]   f9pcap_mcgroup_port = 16'h0506;
wire[MAC_ADDR_WIDTH-1:0]   f9pcap_src_mac_addr = 48'hf1f2f3f4f5f6;
wire[IP_ADDR_WIDTH -1:0]   f9pcap_src_ip_addr  = 32'h0708090a;
wire[IP_PORT_WIDTH -1:0]   f9pcap_src_port     = 16'h0b0c;
wire[SGAP_WIDTH    -1:0]   sgap_cfg            = 1000;
//--------------------------------------------------------------------------------
wire                       sfp_rx_rst    [SFP_COUNT-1:0];
wire                       sfp_rx_clk    [SFP_COUNT-1:0];
wire                       sfp_rx_valid  [SFP_COUNT-1:0];
wire [SFP_DATA_WIDTH-1:0]  sfp_rx_data   [SFP_COUNT-1:0];
wire [SFP_KEEP_WIDTH-1:0]  sfp_rx_keep   [SFP_COUNT-1:0];
wire                       sfp_rx_last   [SFP_COUNT-1:0];
wire                       sfp_rx_err    [SFP_COUNT-1:0];
for (sfpL = 0;  sfpL < SFP_COUNT;  sfpL = sfpL + 1) begin
 assign sfp_rx_rst[sfpL] = sys_rst;
 assign sfp_rx_clk[sfpL] = common_sfp_rx_clk;
 assign sfp_rx_err[sfpL] = 0;
end
//--------------------------------------------------------------------------------
wire                       temac_link_ready[PHY_COUNT-1:0];
wire                       temac_tx_rst    [PHY_COUNT-1:0];
wire                       temac_tx_clk    [PHY_COUNT-1:0];
wire                       temac_tx_valid  [PHY_COUNT-1:0];
wire                       temac_tx_ready  [PHY_COUNT-1:0];
wire[TEMAC_DATA_WIDTH-1:0] temac_tx_data   [PHY_COUNT-1:0];
wire                       temac_tx_last   [PHY_COUNT-1:0];
for (phyL = 0;  phyL < PHY_COUNT;  phyL = phyL + 1) begin
 assign temac_tx_rst    [phyL] = sys_rst;
 assign temac_tx_clk    [phyL] = common_phy_tx_clk;
 assign temac_tx_ready  [phyL] = 1;
 assign temac_link_ready[phyL] = 1;
 if (phyL != 0) begin
   always @(posedge common_phy_tx_clk) begin
     if (temac_tx_valid[phyL] && temac_tx_ready[phyL]) begin
       if (temac_tx_data[phyL] != temac_tx_data[0]) begin
         $display("PHY data should be equal.");
         $stop;
       end
     end
   end
 end
end
//--------------------------------------------------------------------------------
f9pcap_sfp_to_temac #(
  .PHY_COUNT               (PHY_COUNT               ),
  .TEMAC_DATA_WIDTH        (TEMAC_DATA_WIDTH        ),
  .SFP_COUNT               (SFP_COUNT               ),
  .SFP_DATA_WIDTH          (SFP_DATA_WIDTH          ),
  .TTS_WIDTH               (TTS_WIDTH               ),
  .SGAP_WIDTH              (SGAP_WIDTH              ),
  .FRAME_MAX_LENGTH        (FRAME_MAX_LENGTH        ),
  .F9HDR_BUFFER_LENGTH     (F9HDR_BUFFER_LENGTH     ),
  .TEMAC_OUT_BUFFER_LENGTH (TEMAC_OUT_BUFFER_LENGTH )
)
f9pcap_sfp_to_temac_dut(
  .sys_rst_in          (sys_rst             ),
  .tts_uint_in         (tts_uint            ),
  .tts_gray_in         (tts_gray            ),
  .is_f9pcap_en        (is_f9pcap_en        ),
  .f9pcap_mcgroup_addr (f9pcap_mcgroup_addr ),
  .f9pcap_mcgroup_port (f9pcap_mcgroup_port ),
  .f9pcap_src_mac_addr (f9pcap_src_mac_addr ),
  .f9pcap_src_ip_addr  (f9pcap_src_ip_addr  ),
  .f9pcap_src_port     (f9pcap_src_port     ),
  .sgap_cfg_in         (sgap_cfg            ),
  .sfp_rx_rst_in       (sfp_rx_rst          ),
  .sfp_rx_clk_in       (sfp_rx_clk          ),
  .sfp_rx_valid_in     (sfp_rx_valid        ),
  .sfp_rx_data_in      (sfp_rx_data         ),
  .sfp_rx_keep_in      (sfp_rx_keep         ),
  .sfp_rx_last_in      (sfp_rx_last         ),
  .sfp_rx_err_in       (sfp_rx_err          ),
  .temac_tx_rst_in     (temac_tx_rst        ),
  .temac_tx_clk_in     (temac_tx_clk        ),
  .temac_tx_valid_out  (temac_tx_valid      ),
  .temac_tx_ready_in   (temac_tx_ready      ),
  .temac_tx_data_out   (temac_tx_data       ),
  .temac_tx_last_out   (temac_tx_last       ),
  .temac_link_ready    (temac_link_ready    )
);
//================================================================================
localparam           DATIN_LENGTH = 64;
localparam           DATIN_WIDTH  = DATIN_LENGTH * BYTE_WIDTH;
reg[DATIN_WIDTH-1:0] datin_pat_0 = {
  64'h3f_3e_3d_3c_3b_3a_39_38,  64'h37_36_35_34_33_32_31_30,
  64'h2f_2e_2d_2c_2b_2a_29_28,  64'h27_26_25_24_23_22_21_20,
  64'h1f_1e_1d_1c_1b_1a_19_18,  64'h17_16_15_14_13_12_11_10,
  64'h0f_0e_0d_0c_0b_0a_09_08,  64'h07_06_05_04_03_02_01_00
};
reg[DATIN_WIDTH-1:0] datin_pat_1 = {
  64'h7f_7e_7d_7c_7b_7a_79_78,  64'h77_76_75_74_73_72_71_70,
  64'h6f_6e_6d_6c_6b_6a_69_68,  64'h67_66_65_64_63_62_61_60,
  64'h5f_5e_5d_5c_5b_5a_59_58,  64'h57_56_55_54_53_52_51_50,
  64'h4f_4e_4d_4c_4b_4a_49_48,  64'h47_46_45_44_43_42_41_40
};
reg[DATIN_WIDTH-1:0] datin_pat_x[SFP_COUNT-1:0] = { datin_pat_1, datin_pat_0 };
reg[SFP_COUNT-1:0]   start_test;
localparam[SFP_COUNT-1:0]  START_TX_SFP_ALL = {SFP_COUNT{1'b1}};
localparam[SFP_COUNT-1:0]  START_TX_SFP_0   = 2'b01;
localparam[SFP_COUNT-1:0]  START_TX_SFP_1   = 2'b10;
localparam[SFP_COUNT-1:0]  STOP_TX_SFP_ALL  = {SFP_COUNT{1'b0}};

for(sfpL = 0;  sfpL < SFP_COUNT;  sfpL = sfpL + 1) begin
  axis_tx_buffer #(
    .TX_BUF_LENGTH  (DATIN_LENGTH     ),
    .OUT_DATA_WIDTH (SFP_DATA_WIDTH   )
  )
  axis_tx_buf_i(
    .rst_in       (sfp_rx_rst  [sfpL] ),
    .clk_in       (sfp_rx_clk  [sfpL] ),
    .tx_valid_out (sfp_rx_valid[sfpL] ),
    .tx_ready_in  (1'b1               ),
    .tx_data_out  (sfp_rx_data [sfpL] ),
    .tx_keep_out  (sfp_rx_keep [sfpL] ),
    .tx_last_out  (sfp_rx_last [sfpL] ),
    .tx_buf_in    (datin_pat_x [sfpL] ),
    .tx_start_in  (start_test  [sfpL] )
  );
end
//================================================================================
localparam CHK_LENGTH = DATIN_LENGTH + 128;
localparam CHK_WIDTH  = CHK_LENGTH * TEMAC_DATA_WIDTH;
localparam CHK_ADDR_W = $clog2(CHK_LENGTH);
localparam F9PCAP_A_HDR_LENGTH = 42 + 16; // eth:14 + ip:20 + udp:8 + f9pcap:16;
localparam F9PCAP_A_HDR_WIDTH  = F9PCAP_A_HDR_LENGTH * BYTE_WIDTH;
reg [CHK_ADDR_W-1:0]   temac_chk_addr;
reg [CHK_WIDTH -1:0]   temac_chk_data;
reg                    temac_chk_cycle;
wire[F9PCAP_A_HDR_WIDTH-1 :0] temac_chk_hdrin = temac_chk_data[CHK_WIDTH-1 -: F9PCAP_A_HDR_WIDTH];
wire[DATIN_WIDTH-1        :0] temac_chk_datin = temac_chk_data[CHK_WIDTH-1 -  F9PCAP_A_HDR_WIDTH -: DATIN_WIDTH];
always @(posedge temac_tx_clk[0]) begin
  temac_chk_cycle <= 0;
  if (temac_chk_cycle) begin
    $display("HEADER : %x", temac_chk_hdrin);
    $display("PAYLOAD: %x", temac_chk_datin);
    if (temac_chk_datin != datin_pat_0  &&  temac_chk_datin != datin_pat_1) begin
      $display("eth/ip/udp + f9pcap payload was unexpected.");
      $stop;
    end
  end
  // -----
  if(temac_tx_valid[0] && temac_tx_ready[0]) begin
    temac_chk_data[temac_chk_addr*TEMAC_DATA_WIDTH +: TEMAC_DATA_WIDTH] <= temac_tx_data[0];
    temac_chk_addr <= temac_chk_addr - 1;
    if (temac_tx_last[0]) begin
      temac_chk_cycle <= 1;
      temac_chk_addr  <= CHK_LENGTH-1;
      if ((CHK_LENGTH - temac_chk_addr) - F9PCAP_A_HDR_LENGTH != DATIN_LENGTH) begin
        $display("f9pcap + eth/ip/udp length(%d) was unexpected(%d).", DATIN_LENGTH, CHK_LENGTH - temac_chk_addr - F9PCAP_A_HDR_LENGTH);
        $stop;
      end
    end
  end
  // -----
  if (temac_tx_rst[0]) begin
    temac_chk_addr <= CHK_LENGTH-1;
  end
end
//================================================================================
task run_test_all;
  begin
    sys_rst    = 1;
    start_test = 0;
    repeat(10) @(posedge sys_clk);
    sys_rst    = 0;
    repeat(10) @(posedge sys_clk); // wait reset done.
    
    start_test = START_TX_SFP_ALL;  repeat(2) @(posedge common_sfp_rx_clk);   start_test = STOP_TX_SFP_ALL;
    @(posedge temac_tx_last[0]);
    @(posedge temac_tx_last[0]);

    repeat(1000) @(posedge sys_clk);
    start_test = START_TX_SFP_0;    repeat(2) @(posedge common_sfp_rx_clk);   start_test = STOP_TX_SFP_ALL;
    @(posedge temac_tx_last[0]);

    repeat(200) @(posedge sys_clk);
    start_test = START_TX_SFP_0;    repeat(2) @(posedge common_sfp_rx_clk);   start_test = STOP_TX_SFP_ALL;
    @(posedge temac_tx_last[0]);

    repeat(190) @(posedge sys_clk);
    start_test = START_TX_SFP_0;    repeat(2) @(posedge common_sfp_rx_clk);   start_test = STOP_TX_SFP_ALL;
    @(posedge temac_tx_last[0]);

    repeat(210) @(posedge sys_clk);
    start_test = START_TX_SFP_0;    repeat(2) @(posedge common_sfp_rx_clk);   start_test = STOP_TX_SFP_ALL;
    @(posedge temac_tx_last[0]);

    repeat(1000) @(posedge sys_clk);
  end
endtask
//--------------------------------------------------------------------------------
initial begin
  run_test_all;
  // -----
  $display("Test end.");
  $finish;
end
//================================================================================
endmodule
//////////////////////////////////////////////////////////////////////////////
