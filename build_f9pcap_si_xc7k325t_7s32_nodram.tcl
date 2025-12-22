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
set  ::proj_name   f9pcap_stlv_xc7k325t_7s32_nodram
set  ::hw_part     xc7k325tffg676-2

set     srcpath    [file dirname [info script]]
source $srcpath/build_f9pcap_si_xc7k325t_7s32_base.tcl

# ============================================================================
add_files ../rtl/f9pcap_stlv_xc7k325t_nodram.sv

add_files -fileset constrs_1  ../rtl/f9pcap_dev_impl_nodram.xdc
set_property used_in_synthesis false [get_files *impl*.xdc]

# ############################################################################
launch_runs  impl_1 -to_step write_bitstream -jobs 12
# ############################################################################
