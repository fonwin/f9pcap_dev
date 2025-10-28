#
# Program Device for test.
#
# [Open Hardware Manager]/[Open Target] 連線卡片, 然後執行底下指令
#
# ############################################################################
set proj_directory [get_property DIRECTORY [current_project]]; cd $proj_directory; pwd
# ----------------------------------------------------------------------------
set hwdev          [lindex [get_hw_devices xc7k325t_*] 0]
set proj_name      [get_property NAME      [current_project]]
set top_name       [get_property TOP       [current_fileset]]

set_property PROBES.FILE      {}                                                      $hwdev
set_property FULL_PROBES.FILE {}                                                      $hwdev
set_property PROGRAM.FILE     "$proj_directory/$proj_name.runs/impl_1/$top_name.bin"  $hwdev

program_hw_devices   $hwdev
# ############################################################################
