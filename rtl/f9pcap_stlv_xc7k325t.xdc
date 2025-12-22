#######################################################################################
#
# f9pcap_stlv_xc7k325t.xdc
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
  #----- for ddr3;
  set_property DCI_CASCADE {32 34}    [get_iobanks 33]

#######################################################################################
########## CLOCK CONSTRAINTS FOR the BOARD ##########
# set_property PACKAGE_PIN AB11     [get_ports clk_200M_p]
# set_property IOSTANDARD  LVDS     [get_ports clk_200M_p]

  #----- for sys clk;
  set_property PACKAGE_PIN F17      [get_ports clk_50M]
  set_property IOSTANDARD  LVCMOS15 [get_ports clk_50M]

#######################################################################################
############ EEPROM(AT24C04) ##############
  set_property PACKAGE_PIN U26      [get_ports eeprom_scl]
  set_property IOSTANDARD LVCMOS33  [get_ports eeprom_scl]
  set_false_path -to                [get_ports eeprom_scl]

  set_property PACKAGE_PIN V26      [get_ports eeprom_sda]
  set_property IOSTANDARD LVCMOS33  [get_ports eeprom_sda]
  set_false_path -to                [get_ports eeprom_sda]
  set_false_path -from              [get_ports eeprom_sda]

#######################################################################################
##  # key2: 下方,接近 PCIe;    key3:上方接近led;
##  # 按下(短路)=0;
##  set_property PACKAGE_PIN AC16    [get_ports key2]
##  set_property IOSTANDARD LVCMOS15 [get_ports key2]
##  set_property PACKAGE_PIN C24     [get_ports key3]
##  set_property IOSTANDARD LVCMOS33 [get_ports key3]

#######################################################################################
############ LED CONSTRAINTS FOR the BOARD ##############
  set_property PACKAGE_PIN AA2     [get_ports {led[0]}]
  set_property PACKAGE_PIN AD5     [get_ports {led[1]}]
  set_property PACKAGE_PIN W10     [get_ports {led[2]}]
  set_property PACKAGE_PIN Y10     [get_ports {led[3]}]
  set_property PACKAGE_PIN AE10    [get_ports {led[4]}]
  set_property PACKAGE_PIN W11     [get_ports {led[5]}]
  set_property PACKAGE_PIN V11     [get_ports {led[6]}]
  set_property PACKAGE_PIN Y12     [get_ports {led[7]}]
  set_property IOSTANDARD LVCMOS15 [get_ports {led[*]}]
  set_false_path -to               [get_ports {led[*]}]

#######################################################################################
########## ------------------ SFP A B ------------------- ##########
  # ----- 156.25M for SFP.
  set_property PACKAGE_PIN D6      [get_ports sfp_gt_refclk_p]
  create_clock -period 6.4         [get_ports sfp_gt_refclk_p]
  # -----
  set_property PACKAGE_PIN H2      [get_ports {sfp_tx_p[0]}  ]
  set_property PACKAGE_PIN K2      [get_ports {sfp_tx_p[1]}  ]

#######################################################################################
########## ------ 1G/100M PHY A B: RTL8211 RGMII interface ------ ##########
# =====================================================================================
  set_property IOSTANDARD  LVCMOS33 [get_ports {PHY_rgmii_*}          ]

  ###############--------------ETH PHY_*------------#################
  set_property PACKAGE_PIN C12      [get_ports    PHY_rgmii_rxc[0]    ]
  set_property PACKAGE_PIN F8       [get_ports PHY_rgmii_rx_ctl[0]    ]
  set_property PACKAGE_PIN D10      [get_ports    PHY_rgmii_rxd[0][3] ]
  set_property PACKAGE_PIN C9       [get_ports    PHY_rgmii_rxd[0][2] ]
  set_property PACKAGE_PIN D9       [get_ports    PHY_rgmii_rxd[0][1] ]
  set_property PACKAGE_PIN D8       [get_ports    PHY_rgmii_rxd[0][0] ]

  set_property PACKAGE_PIN D11      [get_ports    PHY_rgmii_txc[0]    ]
  set_property PACKAGE_PIN C14      [get_ports PHY_rgmii_tx_ctl[0]    ]
  set_property PACKAGE_PIN E12      [get_ports    PHY_rgmii_txd[0][0] ]
  set_property PACKAGE_PIN D13      [get_ports    PHY_rgmii_txd[0][1] ]
  set_property PACKAGE_PIN C13      [get_ports    PHY_rgmii_txd[0][2] ]
  set_property PACKAGE_PIN D14      [get_ports    PHY_rgmii_txd[0][3] ]

  set_property PACKAGE_PIN J8       [get_ports  PHY_rgmii_reset[0]    ]
##set_property PACKAGE_PIN F9       [get_ports    PHY_rgmii_mdc[0]    ]
##set_property PACKAGE_PIN H11      [get_ports   PHY_rgmii_mdio[0]    ]

  ###############--------------ETH PHY_B------------#################
  set_property PACKAGE_PIN B11      [get_ports    PHY_rgmii_txc[1]    ]
  set_property PACKAGE_PIN A14      [get_ports PHY_rgmii_tx_ctl[1]    ]
  set_property PACKAGE_PIN B12      [get_ports    PHY_rgmii_txd[1][0] ]
  set_property PACKAGE_PIN A12      [get_ports    PHY_rgmii_txd[1][1] ]
  set_property PACKAGE_PIN A13      [get_ports    PHY_rgmii_txd[1][2] ]
  set_property PACKAGE_PIN C11      [get_ports    PHY_rgmii_txd[1][3] ]

  set_property PACKAGE_PIN E10      [get_ports    PHY_rgmii_rxc[1]    ]
  set_property PACKAGE_PIN A8       [get_ports PHY_rgmii_rx_ctl[1]    ]
  set_property PACKAGE_PIN B9       [get_ports    PHY_rgmii_rxd[1][0] ]
  set_property PACKAGE_PIN A9       [get_ports    PHY_rgmii_rxd[1][1] ]
  set_property PACKAGE_PIN B10      [get_ports    PHY_rgmii_rxd[1][2] ]
  set_property PACKAGE_PIN A10      [get_ports    PHY_rgmii_rxd[1][3] ]

  set_property PACKAGE_PIN B14      [get_ports  PHY_rgmii_reset[1]    ]
##set_property PACKAGE_PIN A15      [get_ports    PHY_rgmii_mdc[1]    ]
##set_property PACKAGE_PIN B15      [get_ports   PHY_rgmii_mdio[1]    ]

  create_clock -period 8  [get_ports {PHY_rgmii_rxc[1]}]
  create_generated_clock -source [get_pins {f9pcap_dev_i/phy[1].rgmii_phy_tx_i/ODDR_rgmii_txc/C}] \
                         -divide_by 1 \
                         [get_ports PHY_rgmii_txc[1] ]
#######################################################################################
