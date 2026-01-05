#
# Program Flash Type: N25Q256-3.3V QSPI X 4 (s25fl256sxxxxxx0)
#
# [Open Hardware Manager]/[Open Target] 連線卡片, 然後執行底下指令:
#
# ----------
# [Flow Navigator]/[Open Hardware Manager]/[Add Configuration Memory Device]
set     ::mem_part  s25fl256sxxxxxx0-spi-x1_x2_x4
set     srcpath     [file dirname [info script]]
source $srcpath/program_cfgmem.tcl
