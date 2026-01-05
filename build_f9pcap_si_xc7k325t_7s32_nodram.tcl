# ############################################################################
#
# build_f9pcap_si_xc7k325t_7s32_nodram.tcl
#
# 不使用 dram buffer
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
set  ::proj_name   f9pcap_si_xc7k325t_7s32_nodram
set  ::hw_part     xc7k325tffg676-2

set     srcpath    [file dirname [info script]]
source $srcpath/build_f9pcap_base.tcl

# ============================================================================
add_files ../f9hwlib/temac/rgmii_phy_if_si_0002.sv
add_files ../rtl/f9pcap_si_xc7k325t_nodram.sv
set_property top f9pcap_si_xc7k325t_nodram [current_fileset]

add_files -fileset constrs_1  ../rtl/f9pcap_dev_impl_7s32.xdc
add_files -fileset constrs_1  ../rtl/f9pcap_dev_impl_nodram.xdc
set_property used_in_synthesis false [get_files *impl*.xdc]

add_files -fileset constrs_1                    ../rtl/f9pcap_si_xc7k325t.xdc
set_property used_in_synthesis false [get_files ../rtl/f9pcap_si_xc7k325t.xdc]

# ############################################################################
source ../f9hwlib/temac/sys_ctrl_i50m_single.tcl
source ../f9hwlib/tgemac/tgbaser_xcvr_7s32.tcl

# ############################################################################
launch_runs  impl_1 -to_step write_bitstream -jobs 12
# ############################################################################
