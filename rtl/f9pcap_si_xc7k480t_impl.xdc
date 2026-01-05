#######################################################################################
#
# f9pcap_si_xc7k480t_impl.xdc
#
#######################################################################################
  set_property BITSTREAM.GENERAL.COMPRESS      TRUE   [current_design]
  set_property BITSTREAM.CONFIG.CCLK_TRISTATE  TRUE   [current_design]
  set_property BITSTREAM.CONFIG.CONFIGRATE     66     [current_design]
  set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES    [current_design]
  set_property BITSTREAM.CONFIG.SPI_BUSWIDTH   4      [current_design]
  set_property BITSTREAM.CONFIG.SPI_FALL_EDGE  YES    [current_design]
  set_property BITSTREAM.CONFIG.UNUSEDPIN      PULLUP [current_design]
  set_property CONFIG_VOLTAGE                  3.3    [current_design]
  set_property CFGBVS                          VCCO   [current_design]

#######################################################################################
########## CLOCK CONSTRAINTS FOR the BOARD ##########
## 提供給 DDR3
## set_property PACKAGE_PIN G27         [get_ports clk_200M_p]
## set_property IOSTANDARD  DIFF_SSTL15 [get_ports clk_200M_p]

  #----- for sys clk;
   set_property PACKAGE_PIN U24         [get_ports clk_50M]
   set_property IOSTANDARD  LVCMOS33    [get_ports clk_50M]

#######################################################################################
############ EEPROM(AT24C04) ##############
  set_property PACKAGE_PIN C17      [get_ports eeprom_scl]
  set_property IOSTANDARD LVCMOS33  [get_ports eeprom_scl]
  set_false_path -to                [get_ports eeprom_scl]

  set_property PACKAGE_PIN C16      [get_ports eeprom_sda]
  set_property IOSTANDARD LVCMOS33  [get_ports eeprom_sda]
  set_false_path -to                [get_ports eeprom_sda]
  set_false_path -from              [get_ports eeprom_sda]

#######################################################################################
##  # key1(PROB_B):左方,接近檔板;
##  # key2:右方接近電源;
##  # key3:下方接近SD插槽
##  # 按下(短路)=0;
##  set_property PACKAGE_PIN AE20    [get_ports key2]
##  set_property IOSTANDARD LVCMOS15 [get_ports key2]
##  set_property PACKAGE_PIN AC20    [get_ports key3]
##  set_property IOSTANDARD LVCMOS15 [get_ports key3]

#######################################################################################
############ LED CONSTRAINTS FOR the BOARD ##############
  set_property PACKAGE_PIN D16     [get_ports {leds_out[0]}]
  set_property PACKAGE_PIN D17     [get_ports {leds_out[1]}]
  set_property PACKAGE_PIN B17     [get_ports {leds_out[2]}]
  set_property PACKAGE_PIN A16     [get_ports {leds_out[3]}]
  set_property PACKAGE_PIN F16     [get_ports {leds_out[4]}]
  set_property PACKAGE_PIN E16     [get_ports {leds_out[5]}]
  set_property PACKAGE_PIN A14     [get_ports {leds_out[6]}]
  set_property PACKAGE_PIN B15     [get_ports {leds_out[7]}]
  set_property IOSTANDARD LVCMOS33 [get_ports {leds_out[*]}]
  set_false_path -to               [get_ports {leds_out[*]}]
  # 檔板上的 leds 依序為:
  # leds_out[2]; // red
  # leds_out[3]; // green
  # leds_out[1]; // green

#######################################################################################
##  # scl[2] sda[2] = (SFP*4)[2] or QSFP[0]
##  # scl[3] sda[3] = (SFP*4)[3] or QSFP[1]
##  set_property PACKAGE_PIN A15      [get_ports sfp_scl[0]]
##  set_property PACKAGE_PIN B14      [get_ports sfp_scl[1]]
##  set_property PACKAGE_PIN G15      [get_ports sfp_scl[2]]
##  set_property PACKAGE_PIN J16      [get_ports sfp_scl[3]]
##  set_property IOSTANDARD LVCMOS33  [get_ports sfp_scl[*]]
##  set_false_path -to                [get_ports sfp_scl[*]]
##
##  set_property PACKAGE_PIN C15      [get_ports sfp_sda[0]]
##  set_property PACKAGE_PIN C14      [get_ports sfp_sda[1]]
##  set_property PACKAGE_PIN F15      [get_ports sfp_sda[2]]
##  set_property PACKAGE_PIN H16      [get_ports sfp_sda[3]]
##  set_property IOSTANDARD LVCMOS33  [get_ports sfp_sda[*]]
##  set_false_path -to                [get_ports sfp_sda[*]]
##  set_false_path -from              [get_ports sfp_sda[*]]


#######################################################################################
########## ------ 1G/100M PHY A: RTL8211 RGMII interface ------ ##########
# =====================================================================================
  set_property IOSTANDARD  LVCMOS33 [get_ports {PHY_rgmii_*}          ]

  ###############--------------ETH PHY_*------------#################
  set_property PACKAGE_PIN V21      [get_ports    PHY_rgmii_rxc[0]    ]
  set_property PACKAGE_PIN U20      [get_ports PHY_rgmii_rx_ctl[0]    ]
  set_property PACKAGE_PIN U25      [get_ports    PHY_rgmii_rxd[0][3] ]
  set_property PACKAGE_PIN W22      [get_ports    PHY_rgmii_rxd[0][2] ]
  set_property PACKAGE_PIN W23      [get_ports    PHY_rgmii_rxd[0][1] ]
  set_property PACKAGE_PIN V20      [get_ports    PHY_rgmii_rxd[0][0] ]

  set_property PACKAGE_PIN V22      [get_ports    PHY_rgmii_txc[0]    ]
  set_property PACKAGE_PIN U19      [get_ports PHY_rgmii_tx_ctl[0]    ]
  set_property PACKAGE_PIN R19      [get_ports    PHY_rgmii_txd[0][0] ]
  set_property PACKAGE_PIN R18      [get_ports    PHY_rgmii_txd[0][1] ]
  set_property PACKAGE_PIN T21      [get_ports    PHY_rgmii_txd[0][2] ]
  set_property PACKAGE_PIN T20      [get_ports    PHY_rgmii_txd[0][3] ]

  set_property PACKAGE_PIN V19      [get_ports  PHY_rgmii_reset[0]    ]
##set_property PACKAGE_PIN U18      [get_ports    PHY_rgmii_mdc[0]    ]
##set_property PACKAGE_PIN U17      [get_ports   PHY_rgmii_mdio[0]    ]

#######################################################################################
