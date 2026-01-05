# ############################################################################
#
# build_f9pcap_si_xc7k480t_7s32x4_dram_4sfp.tcl
#
# 使用 dram buffer
# 使用 sfp * 4 版本
#
# ############################################################################
#
# 建立 [SFP+ 抓包] 設備 vivado project
#
# 卡片來源: [赛特凌威科技](https://world.taobao.com/item/6214809309.htm)
#  * SFP * 4 or 10;  RJ45 * 1;
#  * TriMode eth(100M,1G)網路:
#    * 使用 RTL8211E-VB-CG 晶片.
#    * https://datasheet.lcsc.com/lcsc/1810010421_Realtek-Semicon-RTL8211E-VB-CG_C90735.pdf
#
# ############################################################################
set  ::proj_name   f9pcap_si_xc7k480t_7s32_dram_4sfp
set  ::hw_part     xc7k480tffg901-2

set     srcpath    [file dirname [info script]]
source $srcpath/build_f9pcap_base.tcl

# ============================================================================
add_files ../f9hwlib/temac/rgmii_phy_if_si_0002.sv
add_files ../rtl/f9pcap_si_xc7k480t_dram_4sfp.sv
set_property top f9pcap_si_xc7k480t_dram_4sfp [current_fileset]

add_files -fileset constrs_1   ../rtl/f9pcap_dev_impl_7s32.xdc
add_files -fileset constrs_1   ../rtl/f9pcap_dev_impl_dram.xdc
set_property used_in_synthesis false [get_files *impl*.xdc]

add_files -fileset constrs_1              ../rtl/f9pcap_si_xc7k480t_4sfp.xdc
add_files -fileset constrs_1              ../rtl/f9pcap_si_xc7k480t_impl.xdc
set_property used_in_synthesis false [get_files *f9pcap_si_xc7k480t_*.xdc]
# ############################################################################
source ../f9hwlib/temac/sys_ctrl_i50m_single.tcl
source ../f9hwlib/tgemac/tgbaser_xcvr_7s32.tcl

# ############################################################################
set  ::ddr3_prj   stlv_xc7k480t_ddr3_mig_2g_a.prj
source ../f9hwlib/dram/stlv_xc7k480t_ddr3.tcl

# ############################################################################
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

# ############################################################################
launch_runs  impl_1 -to_step write_bitstream -jobs 12
# ############################################################################
