#######################################################################################
#
# f9pcap_dev.xdc
#
#######################################################################################
  set_property BITSTREAM.GENERAL.COMPRESS true [current_design]

#######################################################################################
#
# 目前不是很理解 PHY 要如何設定 set_input_delay, set_output_delay;
# 若依照上一版的設定, 反而造成更多不理解的警告;
# 所以先拿掉, 等真正理解之後再來處理;
#
# 使用底下的設定, 設備已可正確運作;
#
# ----------------------------------------------------------------------------------------------
  set_property SLEW FAST  [get_ports {PHY_rgmii_txc[*]    \
                                      PHY_rgmii_tx_ctl[*] \
                                      PHY_rgmii_txd[*]} ]

  create_clock -period 8  [get_ports {PHY_rgmii_rxc[0]}]
  create_generated_clock -source [get_pins {f9pcap_dev_i/phy[0].rgmii_phy_tx_i/ODDR_rgmii_txc/C}] \
                         -divide_by 1 \
                         [get_ports PHY_rgmii_txc[0] ]

# 若有多個 PHY, 則須在卡片的 xdc 自行增加:
# create_clock -period 8  [get_ports {PHY_rgmii_rxc[1]}]
# create_generated_clock -source [get_pins {f9pcap_dev_i/phy[1].rgmii_phy_tx_i/ODDR_rgmii_txc/C}] \
#                        -divide_by 1 \
#                        [get_ports PHY_rgmii_txc[1] ]
#
#######################################################################################
