`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
module f9pcap_dev_f9mg #(
  `include "eth_ip_localparam.vh"

  /// 用來計算 eeprom_scl_out;
  parameter  SYS_CLK_IN_HZ = 100_000_000,

  parameter  DATA_WIDTH  = 64,
  localparam DATA_LENGTH = (DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,
  localparam KEEP_WIDTH  = (DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,

  parameter[IP_ADDR_WIDTH-1:0] F9MG_DST_IP_ADDRESS = 32'hee_f9_de_ce, // 238.249.222.206
  parameter[IP_PORT_WIDTH-1:0] F9MG_DST_PORT       = 16'hf9_de,       // 63966

  parameter  F9DEV_SN_LENGTH = 8,
  localparam F9DEV_SN_WIDTH  = F9DEV_SN_LENGTH * BYTE_WIDTH,

  /// LOCAL_CMD_SGAP_WIDTH<=0: 不支援 sgap;
  parameter  LOCAL_CMD_SGAP_WIDTH  = 32,
  localparam LOCAL_CMD_SGAP_LENGTH = (LOCAL_CMD_SGAP_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,
  localparam CMD_SGAP_WIDTH        = (LOCAL_CMD_SGAP_WIDTH <= 0 ? 1 : LOCAL_CMD_SGAP_WIDTH),
  
  parameter  LOCAL_CMD_RECOVER_REQ_DEPTH = 16,
  `include "localparam_recover.vh"

  parameter  VIO_DEBUG = 0
)(
  input  wire                        axis_rst_in,
  input  wire                        axis_clk_in,
  input  wire                        axis_valid_in,
  input  wire                        axis_ready_in,
  input  wire [DATA_WIDTH-1:0]       axis_data_in,
  input  wire [KEEP_WIDTH-1:0]       axis_keep_in,
  input  wire                        axis_last_in,

  output reg                         is_f9pcap_en_out,
  output wire[F9DEV_SN_WIDTH-1:0]    f9dev_sn_out,
  output wire[CMD_SGAP_WIDTH-1:0]    local_sgap_out,
  output wire                        f9mg_rx_join_out,

  input  wire                        f9mg_recover_req_clk_in,
  input  wire                        f9mg_recover_req_pop_in,
  output wire                        f9mg_recover_req_valid_out,
  output wire[RECOVER_REQ_WIDTH-1:0] f9mg_recover_req_data_out,

  input  wire                        sys_rst_in,
  input  wire                        sys_clk_in,
  output wire                        eeprom_scl_out,
  inout  wire                        eeprom_sda_io,

  output wire[IP_ADDR_WIDTH -1:0]    f9pcap_mcgroup_addr_out,
  output wire[IP_PORT_WIDTH -1:0]    f9pcap_mcgroup_port_out,
  output wire[MAC_ADDR_WIDTH-1:0]    f9pcap_src_mac_addr_out,
  output wire[IP_ADDR_WIDTH -1:0]    f9pcap_src_ip_addr_out,
  output wire[IP_PORT_WIDTH -1:0]    f9pcap_src_port_out
);
// ===============================================================================
// f9mg command format
// -------------------------------------------------------------------------------
// CMD[F9MG_CMD_LENGTH] | f9dev_name | args[F9MG_CMD_ARG_MAX_LENGTH]
// ---------------------|------------|--------------------------------------------
// "fonwin:resn:"       | "f9pcap"   | f9dev_sn[F9DEV_SN_LENGTH],
//                      |            |                  mcgroup_addr[4], mcgroup_port[2], // \ for send f9pcap
//                      |            | src_mac_addr[6], src_ip_addr[4],  src_port[2]      // / multicase frame;
// ===============================================================================
localparam F9MG_CMD_LENGTH         = 12;
localparam F9MG_CMD_WIDTH          = F9MG_CMD_LENGTH * BYTE_WIDTH;
localparam F9MG_CMD_ARG_MAX_LENGTH = 64;
localparam F9MG_CMD_ARG_MAX_WIDTH  = F9MG_CMD_ARG_MAX_LENGTH * BYTE_WIDTH;
// -------------------------------------------------------------------------------
localparam                         F9DEV_NAME_LENGTH = 6;
localparam                         F9DEV_NAME_WIDTH  = F9DEV_NAME_LENGTH * BYTE_WIDTH;
localparam[F9DEV_NAME_WIDTH-1 :0]  F9DEV_NAME_STRING = "f9pcap";
// -------------------------------------------------------------------------------
localparam F9MG_BUF_LENGTH = F9MG_CMD_LENGTH + F9DEV_NAME_LENGTH + F9MG_CMD_ARG_MAX_LENGTH;
localparam F9MG_BUF_WIDTH  = F9MG_BUF_LENGTH * BYTE_WIDTH;
localparam W_F9MG_BUF_LEN  = $clog2(F9MG_BUF_LENGTH+1);

wire                       f9mg_buf_valid;
wire                       f9mg_buf_last;
wire[F9MG_BUF_WIDTH-1:0]   f9mg_buf_rx_all;
wire[W_F9MG_BUF_LEN-1:0]   f9mg_buf_rx_len;
wire[F9MG_CMD_WIDTH-1:0]   f9mg_buf_rx_cmd_str   = f9mg_buf_rx_all[F9MG_BUF_WIDTH-1 -: F9MG_CMD_WIDTH];
wire                       f9mg_buf_rx_cmd_valid = (f9mg_buf_valid & f9mg_buf_last);
// -------------------------------------------------------------------------------
wire                       eth_valid;
wire[IP_2BYTES_WIDTH-1:0]  eth_type;
wire[MAC_ADDR_WIDTH-1:0]   eth_dst_mac_addr;
wire[MAC_ADDR_WIDTH-1:0]   eth_src_mac_addr;
wire                       eth_vlan_valid;
wire[VLAN_TAG_WIDTH-1:0]   eth_vlan_tag;

wire                       ipv4_hdr_valid;
wire[IP_2BYTES_WIDTH-1:0]  ipv4_hdr_tot_len;
wire[IP_ADDR_WIDTH  -1:0]  ipv4_hdr_src_ip_addr;
wire[IP_ADDR_WIDTH  -1:0]  ipv4_hdr_dst_ip_addr;
wire[BYTE_WIDTH     -1:0]  ipv4_hdr_protocol;

wire                       ipv4_payload_valid;
wire[DATA_WIDTH-1:0]       ipv4_payload_data;
wire[KEEP_WIDTH-1:0]       ipv4_payload_keep;
wire                       ipv4_payload_last;
wire[DATA_WIDTH-1:0]       swap_payload_data;

wire                       udp_hdr_valid;
wire[IP_PORT_WIDTH  -1:0]  udp_src_port;
wire[IP_PORT_WIDTH  -1:0]  udp_dst_port;
wire[IP_2BYTES_WIDTH-1:0]  udp_len;
wire[IP_2BYTES_WIDTH-1:0]  udp_chk_sum;

f9mg_eth_receiver #(
  .DATA_WIDTH          (DATA_WIDTH          ),
  .BYTE_REVERSE        (1                   ),
  .F9DEV_NAME_OFFSET   (F9MG_CMD_LENGTH     ),
  .F9DEV_NAME_LENGTH   (F9DEV_NAME_LENGTH   ),
  .F9DEV_NAME_STRING   (F9DEV_NAME_STRING   ),
  .F9MG_BUF_LENGTH     (F9MG_BUF_LENGTH     ),
  .F9MG_DST_IP_ADDRESS (F9MG_DST_IP_ADDRESS ),
  .F9MG_DST_PORT       (F9MG_DST_PORT       )
)
f9mg_rx_i(
  .rst_in                   (axis_rst_in          ),
  .clk_in                   (axis_clk_in          ),
  .axis_valid_in            (axis_valid_in        ),
  .axis_ready_in            (axis_ready_in        ),
  .axis_data_in             (axis_data_in         ),
  .axis_keep_in             (axis_keep_in         ),
  .axis_last_in             (axis_last_in         ),

  .eth_valid_out            (eth_valid            ),
  .eth_type_out             (eth_type             ),
  .eth_dst_mac_addr_out     (eth_dst_mac_addr     ),
  .eth_src_mac_addr_out     (eth_src_mac_addr     ),
  .eth_vlan_valid_out       (eth_vlan_valid       ),
  .eth_vlan_tag_out         (eth_vlan_tag         ),

  .ipv4_hdr_valid_out       (ipv4_hdr_valid       ),
  .ipv4_hdr_tot_len_out     (ipv4_hdr_tot_len     ),
  .ipv4_hdr_src_ip_addr_out (ipv4_hdr_src_ip_addr ),
  .ipv4_hdr_dst_ip_addr_out (ipv4_hdr_dst_ip_addr ),
  .ipv4_hdr_protocol_out    (ipv4_hdr_protocol    ),

  .ipv4_payload_valid_out   (ipv4_payload_valid   ),
  .ipv4_payload_data_out    (ipv4_payload_data    ),
  .ipv4_payload_keep_out    (ipv4_payload_keep    ),
  .ipv4_payload_last_out    (ipv4_payload_last    ),
  .swap_payload_data_out    (swap_payload_data    ),

  .udp_hdr_valid_out        (udp_hdr_valid        ),
  .udp_src_port_out         (udp_src_port         ),
  .udp_dst_port_out         (udp_dst_port         ),
  .udp_len_out              (udp_len              ),
  .udp_chk_sum_out          (udp_chk_sum          ),

  .f9mg_local_ip_in         (f9pcap_mcgroup_addr_out ),
  .f9mg_local_port_in       (f9pcap_mcgroup_port_out ),

  .f9mg_buf_valid_out       (f9mg_buf_valid       ),
  .f9mg_buf_last_out        (f9mg_buf_last        ),
  .f9mg_buf_out             (f9mg_buf_rx_all      ),
  .f9mg_buf_len_out         (f9mg_buf_rx_len      )
);
// -------------------------------------------------------------------------------
localparam                       IGMP_ACT_WIDTH = 2;
localparam[IGMP_ACT_WIDTH-1:0]   IGMP_ACT_IDLE  = 0,
                                 IGMP_ACT_JOIN  = 1,
                                 IGMP_ACT_LEAVE = 2,
                                 IGMP_ACT_QUERY = 3;
wire[IGMP_ACT_WIDTH-1:0]         igmp_act;
wire[IP_ADDR_WIDTH -1:0]         igmp_group_addr;
wire                             igmp_valid;
igmp_ipv4_parser #(
  .DATA_WIDTH   (DATA_WIDTH ),
  .BYTE_REVERSE (1          )
)
igmp_rx_i(
  .rst_in                (axis_rst_in        ),
  .clk_in                (axis_clk_in        ),
  .ipv4_hdr_protocol_in  (ipv4_hdr_protocol  ),
  .ipv4_payload_valid_in (ipv4_payload_valid ),
  .ipv4_payload_ready_in (1'b1               ),
  .ipv4_payload_data_in  (ipv4_payload_data  ),
  .ipv4_payload_keep_in  (ipv4_payload_keep  ),
  .ipv4_payload_last_in  (ipv4_payload_last  ),

  .is_igmp_protocol_out  (                   ),
  .igmp_valid_out        (igmp_valid         ),
  .igmp_last_out         (                   ),
  .igmp_max_response_out (                   ),
  .igmp_act_out          (igmp_act           ),
  .igmp_group_addr_out   (igmp_group_addr    )
);

reg    f9mg_rx_join_int;
assign f9mg_rx_join_out = f9mg_rx_join_int;
always @(posedge axis_clk_in) begin
  f9mg_rx_join_int <= 0;
  if (igmp_valid & igmp_act == IGMP_ACT_JOIN) begin
    f9mg_rx_join_int <= (igmp_group_addr == f9pcap_mcgroup_addr_out);
  end
end
//////////////////////////////////////////////////////////////////////////////////
localparam[F9MG_CMD_WIDTH  -1 :0]  F9MG_CMD_resn = "fonwin:resn:";

localparam F9MG_SN_BUF_LENGTH = F9DEV_NAME_LENGTH + F9DEV_SN_LENGTH
                              + MAC_ADDR_LENGTH + (IP_ADDR_LENGTH + IP_PORT_LENGTH) * 2;
localparam F9MG_SN_BUF_WIDTH  = F9MG_SN_BUF_LENGTH * BYTE_WIDTH;

reg                         f9mg_resn_valid;
wire[F9MG_SN_BUF_WIDTH-1:0] f9mg_resn_buf = f9mg_buf_rx_all[F9MG_BUF_WIDTH-1 - F9MG_CMD_WIDTH -: F9MG_SN_BUF_WIDTH];
wire                        f9mg_sn_valid;
wire[F9MG_SN_BUF_WIDTH-1:0] f9mg_sn_buf;
wire[F9DEV_NAME_WIDTH -1:0] f9mg_sn_dev_name;
assign { f9mg_sn_dev_name, f9dev_sn_out,
         f9pcap_mcgroup_addr_out, f9pcap_mcgroup_port_out,
         f9pcap_src_mac_addr_out, f9pcap_src_ip_addr_out, f9pcap_src_port_out
} = f9mg_sn_buf;

f9mg_cmd_sn #(
  /// EEPROM 前端的空間, 偶爾會因經常寫入(使用回收的EEPROM?)造成失效,
  /// 所以這裡改 IIC_DEVICE_ADDR, 用較高位址的空間來儲存 f9mg_sn;
  .IIC_DEVICE_ADDR    (1                  ),
  .F9MG_SN_BUF_LENGTH (F9MG_SN_BUF_LENGTH ),
  .CLK_IN_HZ          (SYS_CLK_IN_HZ      )
)
f9mg_cmd_sn_i(
  .rst_in             (sys_rst_in      ),
  .clk_in             (sys_clk_in      ),
  .eeprom_scl_out     (eeprom_scl_out  ),
  .eeprom_sda_io      (eeprom_sda_io   ),
  .f9mg_sn_valid_out  (f9mg_sn_valid   ),
  .f9mg_sn_out        (f9mg_sn_buf     ),
  .f9mg_resn_valid_in (f9mg_resn_valid ),
  .f9mg_resn_in       (f9mg_resn_buf   )
);

reg  resn_valid_axis_domain;
wire resn_valid_sys_domain;
sync_reset
sync_rst_resn_i(
  .clk     (sys_clk_in             ),
  .rst_in  (resn_valid_axis_domain ),
  .rst_out (resn_valid_sys_domain  )
);
always @(posedge sys_clk_in) begin
  f9mg_resn_valid <= resn_valid_sys_domain;
end
// --------------------------------------------------------------
always @(posedge axis_clk_in) begin
  is_f9pcap_en_out       <= (f9mg_sn_dev_name == F9DEV_NAME_STRING);
  resn_valid_axis_domain <= 0;
  if (f9mg_buf_rx_cmd_valid) begin
    if (f9mg_buf_rx_cmd_str == F9MG_CMD_resn) begin
      if (f9mg_buf_rx_len == F9MG_CMD_LENGTH + F9MG_SN_BUF_LENGTH) begin
        resn_valid_axis_domain <= 1;
      end
    end
  end
end
//////////////////////////////////////////////////////////////////////////////////
//  sn[8]       | Local CMD    | f9dev_name | local args
// -------------|--------------|------------|--------------------------------------
//  f9dev_sn[8] | local_cmd[4] | "f9pcap"   |
// -------------|--------------|------------|--------------------------------------
//              | "sgap"       |            | CDC_local_sgap
// -------------------------------------------------------------------------------
localparam F9MG_LOCAL_CMD_LENGTH = F9MG_CMD_LENGTH - F9DEV_SN_LENGTH;
localparam F9MG_LOCAL_CMD_WIDTH  = F9MG_LOCAL_CMD_LENGTH * BYTE_WIDTH;
localparam F9MG_LOCAL_ARG_LENGTH = F9MG_CMD_ARG_MAX_LENGTH;
localparam F9MG_LOCAL_ARG_WIDTH  = F9MG_LOCAL_ARG_LENGTH * BYTE_WIDTH;
wire[F9DEV_SN_WIDTH      -1:0]   local_rx_sn_w;
wire[F9MG_LOCAL_CMD_WIDTH-1:0]   local_cmd_s_w;
reg [F9MG_LOCAL_CMD_WIDTH-1:0]   local_cmd_str;
wire                             local_cmd_valid_w = f9mg_buf_rx_cmd_valid & (local_rx_sn_w == f9dev_sn_out);
reg                              local_cmd_valid;
reg [W_F9MG_BUF_LEN      -1:0]   local_cmd_arg_len;
wire[F9MG_LOCAL_ARG_WIDTH-1:0]   local_cmd_arg_buf = f9mg_buf_rx_all[F9MG_LOCAL_ARG_WIDTH-1:0];
assign {local_rx_sn_w, local_cmd_s_w} = f9mg_buf_rx_cmd_str;

always @(posedge axis_clk_in) begin
   local_cmd_valid   <= local_cmd_valid_w;
   local_cmd_str     <= local_cmd_s_w;
   local_cmd_arg_len <= f9mg_buf_rx_len - (F9MG_CMD_LENGTH + F9DEV_NAME_LENGTH);
end
// ===============================================================================
if (LOCAL_CMD_SGAP_WIDTH > 0) begin
  localparam[F9MG_LOCAL_CMD_WIDTH-1:0] F9MG_LOCAL_CMD_sgap = "sgap";
  localparam                           W_LOCAL_CMD_SGAP_ALIGN = LOCAL_CMD_SGAP_LENGTH * BYTE_WIDTH;
  (* dont_touch="yes" *)
  reg[LOCAL_CMD_SGAP_WIDTH-1:0] CDC_local_sgap;
  assign       local_sgap_out = CDC_local_sgap;

  always @(posedge axis_clk_in) begin
    if (local_cmd_valid  &&  local_cmd_str == F9MG_LOCAL_CMD_sgap  &&  local_cmd_arg_len == LOCAL_CMD_SGAP_LENGTH) begin
      CDC_local_sgap <= local_cmd_arg_buf[F9MG_LOCAL_ARG_WIDTH-W_LOCAL_CMD_SGAP_ALIGN +: LOCAL_CMD_SGAP_WIDTH];
    end
    // -----
    if (axis_rst_in) begin
      CDC_local_sgap <= 0;
    end
  end
end
// -------------------------------------------------------------------------------
if (LOCAL_CMD_RECOVER_REQ_DEPTH <= 0) begin
  assign f9mg_recover_req_valid_out = 0;
  assign f9mg_recover_req_data_out  = 0;
end else begin
  localparam[F9MG_LOCAL_CMD_WIDTH-1:0] F9MG_LOCAL_CMD_recover_req = "rcvr";
  wire[RECOVER_REQ_WIDTH-1:0] recover_req_data = local_cmd_arg_buf[F9MG_LOCAL_ARG_WIDTH-RECOVER_REQ_WIDTH +: RECOVER_REQ_WIDTH];
  wire                        recover_req_push = (local_cmd_valid  &&  local_cmd_str == F9MG_LOCAL_CMD_recover_req  &&  local_cmd_arg_len == RECOVER_REQ_LENGTH);
  wire                        recover_req_empty;
  wire                        recover_req_rst;
  // -----
  sync_reset
  sync_rst_rcvr_i(
    .clk     (f9mg_recover_req_clk_in ),
    .rst_in  (axis_rst_in             ),
    .rst_out (recover_req_rst         )
  );
  // -----
  async_fifo #(
    .DATA_WIDTH (RECOVER_REQ_WIDTH                   ),
    .ADDR_WIDTH ($clog2(LOCAL_CMD_RECOVER_REQ_DEPTH) )
  )
  async_fifo_rcvr_req_i(
    .wclk   (axis_clk_in               ),
    .wrst_n (~axis_rst_in              ),
    .wdata  (recover_req_data          ),
    .winc   (recover_req_push          ),
    .wfull  (                          ),
    .rclk   (f9mg_recover_req_clk_in   ),
    .rrst_n (~recover_req_rst          ),
    .rdata  (f9mg_recover_req_data_out ),
    .rempty (recover_req_empty         ),
    .rinc   (f9mg_recover_req_pop_in   )
  );
  assign f9mg_recover_req_valid_out = ~recover_req_empty;
end
//////////////////////////////////////////////////////////////////////////////////
if (VIO_DEBUG) begin
  localparam VIO_WIDTH = 256;
  // ----------------------------------------------------------------------
  localparam F9MG_BUF_VIO_CNT = (F9MG_BUF_WIDTH + VIO_WIDTH-1) / VIO_WIDTH;
  (* dont_touch="yes" *)
  reg [VIO_WIDTH-1:0] f9mg_buf_vio[F9MG_BUF_VIO_CNT-1:0];
  for(genvar iL = 0;  iL < F9MG_BUF_WIDTH;  iL = iL + VIO_WIDTH) begin
    localparam W_REMAIN  = F9MG_BUF_WIDTH - iL;
    localparam W_CURRENT = (W_REMAIN <= VIO_WIDTH ? W_REMAIN : VIO_WIDTH);
    if (W_CURRENT > 0) begin
      always @(posedge axis_clk_in) begin
        if (f9mg_buf_rx_cmd_valid) begin
          f9mg_buf_vio[iL/VIO_WIDTH] <= f9mg_buf_rx_all[iL +: W_CURRENT];
        end
      end
    end
  end
  // ----------------------------------------------------------------------
  (* dont_touch="yes" *)
  reg [15:0] f9mg_buf_rx_len_vio  = 0;
  reg [15:0] f9mg_resn_valid_cnt  = 0;
  reg [15:0] f9mg_resn_axis_cnt   = 0;
  reg [15:0] f9mg_resn_last_cnt_a = 0;
  reg [15:0] f9mg_resn_last_cnt_k = 0;
  reg [15:0] f9mg_resn_last_cnt_n = 0;
  (* dont_touch="yes" *)
  wire[VIO_WIDTH-1:0] f9mg_cnt  = { f9mg_buf_rx_len_vio, f9mg_resn_valid_cnt,
                                    f9mg_resn_axis_cnt, f9mg_resn_last_cnt_a, f9mg_resn_last_cnt_k, f9mg_resn_last_cnt_n
                                  };
  (* dont_touch="yes" *)
  reg [VIO_WIDTH-1:0]   f9mg_sn_buf_vio;

  always @(posedge axis_clk_in) begin
    if (f9mg_buf_rx_cmd_valid) begin
      f9mg_buf_rx_len_vio <= f9mg_buf_rx_len;
    end
    // -----
    if (resn_valid_axis_domain) begin
      f9mg_resn_valid_cnt <= f9mg_resn_valid_cnt + 1;
    end
    // -----
    f9mg_sn_buf_vio      <= f9mg_sn_buf;
    f9mg_resn_axis_cnt   <= f9mg_resn_axis_cnt   +  axis_valid_in;
    f9mg_resn_last_cnt_a <= f9mg_resn_last_cnt_a + (axis_valid_in & axis_ready_in & axis_last_in);
    f9mg_resn_last_cnt_k <= f9mg_resn_last_cnt_k + (axis_valid_in & axis_ready_in & axis_last_in &  |axis_keep_in);
    f9mg_resn_last_cnt_n <= f9mg_resn_last_cnt_n + (axis_valid_in & axis_ready_in & axis_last_in & ~|axis_keep_in);
  end
  // ----------------------------------------------------------------------
  reg [31:0] local_sgap_vio;
  reg [31:0] local_sgap_123_vio;
  reg [15:0] local_cmd_arg_len_vio;
  reg [15:0] local_cmd_cnt_vio;
  reg [F9DEV_SN_WIDTH-1:0]   local_rx_sn_vio;
  (* dont_touch="yes" *)
  wire[VIO_WIDTH-1:0] f9mg_local_cmd_vio = { local_cmd_cnt_vio, local_cmd_arg_len_vio, local_cmd_str,
                                             local_sgap_vio, local_sgap_123_vio};
  (* dont_touch="yes" *)
  reg [VIO_WIDTH-1:0] f9mg_local_cmd_arg_vio;
  always @(posedge axis_clk_in) begin
    local_cmd_cnt_vio      <= local_cmd_cnt_vio + local_cmd_valid;
    f9mg_local_cmd_arg_vio <= local_cmd_arg_buf[F9MG_LOCAL_ARG_WIDTH-1 -: VIO_WIDTH];
    local_sgap_vio         <= local_sgap_out;
    local_sgap_123_vio     <= local_sgap_out + 123;
    if (local_cmd_valid) begin
      local_rx_sn_vio       <= local_rx_sn_w;
      local_cmd_arg_len_vio <= local_cmd_arg_len;
    end
  end
  // ----------------------------------------------------------------------
  (* dont_touch="yes" *)
  wire[VIO_WIDTH-1:0] f9mg_recover_req_vio = {f9mg_recover_req_valid_out, 16'heeee, f9mg_recover_req_data_out };
  // ----------------------------------------------------------------------
  /*
  create_ip -name vio -vendor xilinx.com -library ip -module_name vio_mg
  set_property -dict [list \
    CONFIG.C_NUM_PROBE_OUT {0} \
    CONFIG.C_PROBE_IN0_WIDTH {256} \
    CONFIG.C_PROBE_IN1_WIDTH {256} \
    CONFIG.C_PROBE_IN2_WIDTH {256} \
    CONFIG.C_PROBE_IN3_WIDTH {256} \
    CONFIG.C_PROBE_IN4_WIDTH {256} \
    CONFIG.C_PROBE_IN5_WIDTH {256} \
    CONFIG.C_PROBE_IN6_WIDTH {256} \
    CONFIG.C_PROBE_IN7_WIDTH {256} \
    CONFIG.C_NUM_PROBE_IN {8} \
  ] [get_ips vio_mg]
  */
  vio_mg  vio_mg_i(
    .probe_in0 (f9mg_buf_vio[0]        ),
    .probe_in1 (f9mg_buf_vio[1]        ),
    .probe_in2 (f9mg_buf_vio[2]        ),
    .probe_in3 (f9mg_sn_buf_vio        ),
    .probe_in4 (f9mg_local_cmd_vio     ),
    .probe_in5 (f9mg_local_cmd_arg_vio ),
    .probe_in6 (f9mg_cnt               ),
    .probe_in7 (f9mg_recover_req_vio   ),
    .clk       (sys_clk_in             )
  );
end // if (VIO_DEBUG)
// ===============================================================================
endmodule
//////////////////////////////////////////////////////////////////////////////////
