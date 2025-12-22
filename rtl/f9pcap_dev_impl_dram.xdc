#######################################################################################
#
# f9pcap_dev_impl_dram.xdc
#
# 使用 dram buffer
#
#######################################################################################

#######################################################################################
# ----- [rgmii_rx <=> sfp_tx] CDC path for [handshake or sync]
# -------------------------------------------------------------------------------------
set SFP_TO_TEMAC_INST f9pcap_dev_i/f9pcap_i/to_temac*.dram_to_phy_i
set_false_path -to   [get_pins "$SFP_TO_TEMAC_INST/sync_*/*q1*/D"]
set_false_path -to   [get_pins "$SFP_TO_TEMAC_INST/*sync_*/sync_reg*/PRE"]
set_false_path -to   [get_pins "$SFP_TO_TEMAC_INST/frame_len_fifo_i/sync_*/*q1*/D"]
set_false_path -from [get_pins "$SFP_TO_TEMAC_INST/frame_len_fifo_i/fifomem/mem*/*/CLK"]
# ----- sync_temac_rst
# set_false_path -to   [get_pins "f9pcap_dev_i/f9pcap_i/to_temac*.dram_to_phy_i/*sync_*/sync_reg*/PRE"]
# ----- pause/reset signal;
set_false_path -to   [get_pins "f9pcap_dev_i/f9pcap_i/sync_*/sync_reg*/D"]
set_false_path -to   [get_pins "f9pcap_dev_i/f9pcap_i/sync_*/sync_reg*/PRE"]
# ----- f9phdr: sync rst/addr/tts;
set_false_path -to   [get_pins "f9pcap_dev_i/f9pcap_i/f9p*.f9phdr_wrap_i/*sync_*/sync_reg*/PRE"]
set_false_path -to   [get_pins "f9pcap_dev_i/f9pcap_i/f9p*.f9phdr_wrap_i/*sync_*/sync_reg*/D"]

#######################################################################################
# ----- Calc [Ip ChkSum] for [f9pcap frame]
set  SEND_ETH_UDP_I  f9pcap_dev_i/f9pcap_i/udp_eth_send_i
set_multicycle_path 2 -setup -from    [get_pins "$SEND_ETH_UDP_I/*/C"]               \
                             -through [get_pins "$SEND_ETH_UDP_I/ip_hdr_chksum_i/*"] \
                             -to      [get_pins "$SEND_ETH_UDP_I/*/D"           -filter {NAME !~ "*/ip_hdr_chksum_i/*" && NAME !~ "*/len_keep_i/*"}]
set_multicycle_path 1 -hold  -from    [get_pins "$SEND_ETH_UDP_I/*/C"]               \
                             -through [get_pins "$SEND_ETH_UDP_I/ip_hdr_chksum_i/*"] \
                             -to      [get_pins "$SEND_ETH_UDP_I/*/D"           -filter {NAME !~ "*/ip_hdr_chksum_i/*" && NAME !~ "*/len_keep_i/*"}]

#######################################################################################
# ----- f9mg recover request
set_false_path -to   [get_pins "f9pcap_dev_i/f9mg_i/sync_*/sync_reg*/PRE"]
set_false_path -to   [get_pins "f9pcap_dev_i/f9mg_i/async_fifo_*/sync_*/*q1*/D"]
set_false_path -from [get_pins "f9pcap_dev_i/f9mg_i/async_fifo_*/fifomem/mem*/*/CLK"]

#######################################################################################
