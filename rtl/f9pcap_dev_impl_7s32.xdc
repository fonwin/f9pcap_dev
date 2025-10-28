#######################################################################################
#
# f9pcap_dev_impl_7s32.xdc
#
#######################################################################################
#
# 使用 tgbaser_xcvr_7s32.v 時, xcvr 為 32 bits, 轉成 64 bits 之後處理,
# 因 xcvr 32 bits, clk 僅為 3.1 ns; 有些地方處理時間不足以在 1 cycle 完成,
# 所以必須允許 2 cycles, 才有足夠的處理時間;
#
#######################################################################################
# ----- sfp rx crc
set  AXIS_BASER_RX_INST  f9pcap_dev_i/xcvr[*].tgbaser_axis_i/tgbaser_axis_i/alex_eth_mac_phy_10g_inst/eth_mac_phy_10g_rx_inst/axis_baser_rx_inst
set_multicycle_path 2 -setup -from    [get_pins "$AXIS_BASER_RX_INST/*/C"]       \
                             -through [get_nets "$AXIS_BASER_RX_INST/eth_crc/*"] \
                             -to      [get_pins "$AXIS_BASER_RX_INST/*/D"       -filter  {NAME !~ "*/eth_crc/*"}]
set_multicycle_path 1 -hold  -from    [get_pins "$AXIS_BASER_RX_INST/*/C"]       \
                             -through [get_nets "$AXIS_BASER_RX_INST/eth_crc/*"] \
                             -to      [get_pins "$AXIS_BASER_RX_INST/*/D"       -filter  {NAME !~ "*/eth_crc/*"}]

# ----- sfp tx crc
set  AXIS_BASER_TX_INST  f9pcap_dev_i/xcvr[*].tgbaser_axis_i/tgbaser_axis_i/alex_eth_mac_phy_10g_inst/eth_mac_phy_10g_tx_inst/axis_baser_tx_inst
set_multicycle_path 2 -setup -from    [get_pins "$AXIS_BASER_TX_INST/*/C"]            \
                             -through [get_nets "$AXIS_BASER_TX_INST/crc*.eth_crc/*"] \
                             -to      [get_pins "$AXIS_BASER_TX_INST/*/D"            -filter {NAME !~ "*/crc*.eth_crc/*"}]
set_multicycle_path 1 -hold  -from    [get_pins "$AXIS_BASER_TX_INST/*/C"]            \
                             -through [get_nets "$AXIS_BASER_TX_INST/crc*.eth_crc/*"] \
                             -to      [get_pins "$AXIS_BASER_TX_INST/*/D"            -filter {NAME !~ "*/crc*.eth_crc/*"}]

#######################################################################################
#######################################################################################
# ----- f9phdr.buf_ram[] wr => rd
set  F9PHDR_WRAP_I  f9pcap_dev_i/f9pcap_i/wrap[*].f9pcap_wrap_i/f9phdr_wrap_i
set_multicycle_path 2 -setup -from    [get_pins "$F9PHDR_WRAP_I/buf_ram*/CLKBWRCLK"] \
                             -to      [get_pins "$F9PHDR_WRAP_I/o_data_len_out*/D"]
set_multicycle_path 1 -hold  -from    [get_pins "$F9PHDR_WRAP_I/buf_ram*/CLKBWRCLK"] \
                             -to      [get_pins "$F9PHDR_WRAP_I/o_data_len_out*/D"]

#######################################################################################
# ----- Calc [Ip ChkSum] for [f9pcap frame]
set  SEND_ETH_UDP_I  f9pcap_dev_i/f9pcap_i/wrap[*].f9pcap_wrap_i/udp_eth_send_i
set_multicycle_path 2 -setup -from    [get_pins "$SEND_ETH_UDP_I/*/C"]               \
                             -through [get_pins "$SEND_ETH_UDP_I/ip_hdr_chksum_i/*"] \
                             -to      [get_pins "$SEND_ETH_UDP_I/*/D"               -filter {NAME !~ "*/ip_hdr_chksum_i/*"}]
set_multicycle_path 1 -hold  -from    [get_pins "$SEND_ETH_UDP_I/*/C"]               \
                             -through [get_pins "$SEND_ETH_UDP_I/ip_hdr_chksum_i/*"] \
                             -to      [get_pins "$SEND_ETH_UDP_I/*/D"               -filter {NAME !~ "*/ip_hdr_chksum_i/*"}]

#######################################################################################
