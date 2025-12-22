# ############################################################################
#
# build_f9pcap_si_xc7k325t_7s32_base.tcl
#
# ############################################################################
#
# 建立 [SFP+ 抓包] 設備 vivado project
#
# 卡片來源: [赛特凌威科技](https://item.taobao.com/item.htm?_u=535po35ob365&id=573888696513&spm=a1z09.2.0.0.cc9f2e8dJn0AYz)
#  * SFP * 2;  RJ45 * 2;
#  * TriMode eth(100M,1G)網路:
#    * 使用 RTL8211E-VB-CG 晶片.
#    * https://datasheet.lcsc.com/lcsc/1810010421_Realtek-Semicon-RTL8211E-VB-CG_C90735.pdf
#
# ############################################################################
set srcpath [file dirname [info script]]
create_project $proj_name  $srcpath/$::proj_name  -part $::hw_part

# ----------------------------------------------------------------------------
set proj_directory [get_property DIRECTORY [current_project]]; cd $proj_directory; pwd

# ############################################################################
# 因為有用 reg 直接當成 clk 驅動其他邏輯(breath_led、iic_ctrl、f9mg_ip_ident...),
# 所以需要底下設定:
set_property STEPS.SYNTH_DESIGN.ARGS.GATED_CLOCK_CONVERSION  auto  [get_runs synth_1]

# ----------------------------------------------------------------------------
# 直接建立 bin 燒錄檔.
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]

# ############################################################################
add_files ../f9hwlib/sync_signal.v
add_files ../f9hwlib/signal_counter.v
add_files ../f9hwlib/f9count_1_bits.v
add_files ../f9hwlib/breath_led.v
add_files ../f9hwlib/mdio_ctrl.v
add_files ../f9hwlib/mdio_ctrl_tb.v
add_files ../f9hwlib/ip_checksum.v
add_files ../f9hwlib/axis_tx_buffer.v
add_files ../f9hwlib/axis_n_to_one.sv
add_files ../f9hwlib/count_down.v
add_files ../f9hwlib/axis_len_keep_last.v
add_files ../f9hwlib/byte_reverse.v
add_files ../f9hwlib/vio_mon_buf.sv

add_files ../f9hwlib/frame_slow_to_fast.v
add_files ../f9hwlib/cdc_fifo.v
add_files ../f9hwlib/async_fifo.v
add_files ../f9hwlib/f9fifo.v

add_files ../f9hwlib/temac/gmii_temac_rx.v
add_files ../f9hwlib/temac/gmii_temac_tx.v
add_files ../f9hwlib/temac/rgmii_temac.v
add_files ../f9hwlib/temac/temac_rx_to_axis.v
add_files ../f9hwlib/temac/rgmii_phy_if_si_0002.sv

add_files ../f9hwlib/tgemac/axis_baser_rx_64.v
add_files ../f9hwlib/tgemac/axis_baser_tx_64_alex_20240213_baac.v
add_files ../f9hwlib/tgemac/axis_baser_tx_tb.v
add_files ../f9hwlib/tgemac/eth_mac_phy_10g.v
add_files ../f9hwlib/tgemac/eth_mac_phy_10g_rx.v
add_files ../f9hwlib/tgemac/eth_mac_phy_10g_tx.v
add_files ../f9hwlib/tgemac/eth_phy_10g_rx_if.v
add_files ../f9hwlib/tgemac/eth_phy_10g_rx_watchdog.v
add_files ../f9hwlib/tgemac/eth_phy_10g_rx_frame_sync.v
add_files ../f9hwlib/tgemac/eth_phy_10g_tx_if.v
add_files ../f9hwlib/tgemac/tgbaser_v_axis.sv

add_files ../f9hwlib/tgemac/tgbaser_axis.v
add_files ../rtl/f9pcap_tgbaser_axis.v
add_files ../rtl/f9pcap_tgbaser_axis_tb.v

# ----------------------------------------------------------------------------
add_files ../alex_eth_git/lib/axis/rtl/axis_async_fifo.v
add_files ../alex_eth_git/rtl/lfsr.v
add_files ../alex_eth_git/rtl/eth_phy_10g_rx_ber_mon.v

# ----------------------------------------------------------------------------
add_files ../f9hwlib/tunnel_simple/tunnel_temac_to_sfp_direct2.v
add_files ../f9hwlib/tunnel_simple/sfp_to_temac.v
add_files ../f9hwlib/axis_store_fwd.v
add_files ../f9hwlib/func_gray.vh
add_files ../f9hwlib/f9phdr_wrap.v
add_files ../rtl/f9pcap_wrap_eth.v
add_files ../rtl/f9pcap_wrap_eth_tb.v
add_files ../rtl/f9pcap_dev_top.sv
add_files ../rtl/f9pcap_sfp_to_temac.sv
add_files ../rtl/f9pcap_sfp_to_temac_tb.sv
add_files ../rtl/f9pcap_dev_f9mg.sv

# ----------------------------------------------------------------------------
add_files ../f9hwlib/axis_hdr_parser.v
add_files ../f9hwlib/axis_to_buffer.v
add_files ../f9hwlib/eth_tools/eth_axis_parser.v
add_files ../f9hwlib/eth_tools/ipv4_eth_axis_parser.v
add_files ../f9hwlib/eth_tools/ipv4_eth_axis_parser_tb.v
add_files ../f9hwlib/eth_tools/udp_eth_axis_parser.v
add_files ../f9hwlib/eth_tools/udp_ipv4_parser.v
add_files ../f9hwlib/eth_tools/udp_eth_axis_parser_tb.v
add_files ../f9hwlib/eth_tools/udp_eth_send.v
add_files ../f9hwlib/eth_tools/igmp_ipv4_parser.v
add_files ../f9hwlib/eth_tools/igmp_ipv4_parser_tb.v
add_files ../f9hwlib/eth_tools/f9mg_eth_receiver.v
add_files ../f9hwlib/eth_tools/f9mg_udp_receiver.v
add_files ../f9hwlib/eth_tools/f9mg_udp_receiver_tb.v
add_files ../f9hwlib/eth_tools/f9mg_cmd_sn.v
add_files ../f9hwlib/iic_ctrl.v

# ############################################################################
add_files -fileset constrs_1                    ../rtl/f9pcap_dev.xdc
add_files -fileset constrs_1                    ../rtl/f9pcap_dev_impl.xdc
add_files -fileset constrs_1                    ../rtl/f9pcap_dev_impl_7s32.xdc
set_property used_in_synthesis false [get_files *impl*.xdc]
add_files -fileset constrs_1                    ../rtl/f9pcap_stlv_xc7k325t.xdc
set_property used_in_synthesis false [get_files ../rtl/f9pcap_stlv_xc7k325t.xdc]

# ############################################################################
set_property used_in_simulation       false   [get_files *_top*.*v]
set_property used_in_synthesis        false   [get_files *_tb.*v ]
set_property used_in_implementation   false   [get_files *_tb.*v ]
set_property top f9pcap_stlv_xc7k325t         [current_fileset   ]
set_property top f9pcap_sfp_to_temac_tb       [get_filesets sim_1]

# ############################################################################
source ../f9hwlib/temac/sys_ctrl_i50m_single.tcl
source ../f9hwlib/tgemac/tgbaser_xcvr_7s32.tcl

# ############################################################################
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

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_f9phdr
set_property -dict [list \
  CONFIG.C_PROBE0_WIDTH {16} \
  CONFIG.C_PROBE1_WIDTH {16} \
  CONFIG.C_PROBE2_WIDTH {16} \
  CONFIG.C_PROBE3_WIDTH {16} \
  CONFIG.C_PROBE8_WIDTH {8} \
  CONFIG.C_NUM_OF_PROBES {9} \
] [get_ips ila_f9phdr]

# ############################################################################
