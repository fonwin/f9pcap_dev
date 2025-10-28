#
# Program Flash Type: N25Q256-3.3V QSPI X 4 (s25fl256sxxxxxx0)
#
# [Open Hardware Manager]/[Open Target] 連線卡片, 然後執行底下指令:
#
# ----------
# [Flow Navigator]/[Open Hardware Manager]/[Add Configuration Memory Device]
set hwdev [lindex [get_hw_devices xc7k325t_*] 0]
create_hw_cfgmem -hw_device $hwdev [lindex [get_cfgmem_parts {s25fl256sxxxxxx0-spi-x1_x2_x4}] 0]
set_property PROGRAM.BLANK_CHECK  0 [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.ERASE        1 [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.CFG_PROGRAM  1 [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.VERIFY       1 [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.CHECKSUM     0 [ get_property PROGRAM.HW_CFGMEM $hwdev]
refresh_hw_device $hwdev
# ----------
# 燒錄
set proj_directory [get_property DIRECTORY [current_project]]; cd $proj_directory; pwd
set proj_name      [get_property NAME      [current_project]]
set top_name       [get_property TOP       [current_fileset]]
set_property PROGRAM.ADDRESS_RANGE  {use_file} [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.FILES          [list "$proj_directory/$proj_name.runs/impl_1/$top_name.bin" ] [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.PRM_FILE {}    [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.BLANK_CHECK  0 [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.ERASE        1 [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.CFG_PROGRAM  1 [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.VERIFY       1 [ get_property PROGRAM.HW_CFGMEM $hwdev]
set_property PROGRAM.CHECKSUM     0 [ get_property PROGRAM.HW_CFGMEM $hwdev]
startgroup 
create_hw_bitstream -hw_device $hwdev [get_property PROGRAM.HW_CFGMEM_BITFILE $hwdev]; program_hw_devices $hwdev; refresh_hw_device $hwdev;
program_hw_cfgmem -hw_cfgmem [ get_property PROGRAM.HW_CFGMEM $hwdev]
endgroup
# ----------
