# ############################################################################
#
# build_f9pcap_si_xc7k325t_7s32_dram.tcl
#
# 使用 dram buffer
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
set  ::proj_name   f9pcap_stlv_xc7k325t_7s32_dram
set  ::hw_part     xc7k325tffg676-2

set     srcpath    [file dirname [info script]]
source $srcpath/build_f9pcap_si_xc7k325t_7s32_base.tcl

# ============================================================================
add_files ../rtl/f9pcap_stlv_xc7k325t_dram.sv

add_files -fileset constrs_1  ../rtl/f9pcap_dev_impl_dram.xdc
set_property used_in_synthesis false [get_files *impl*.xdc]

# ############################################################################
set  ::ddr3_prj   stlv_xc7k325t_ddr3_mig_2g.prj
source ../f9hwlib/dram/stlv_xc7k325t_ddr3.tcl

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
