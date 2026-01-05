#######################################################################################
#
# f9pcap_si_xc7k480t_10sfp.xdc
#
#######################################################################################
########## ------------------   SFP   ------------------- ##########
# =====================================================================================
# ===== (SFP*10) =====
# ----- I/O BANK 117
  set_property PACKAGE_PIN A8     [get_ports {sfp_tx_p[0]}        ]
  set_property PACKAGE_PIN C8     [get_ports {sfp_tx_p[1]}        ]

# ----- QSFP[0].[0..3]
# ----- I/O BANK 116
  set_property PACKAGE_PIN B6     [get_ports {sfp_tx_p[5]}        ]
  set_property PACKAGE_PIN A4     [get_ports {sfp_tx_p[4]}        ]
  create_clock -period 6.4        [get_ports {sfp_gt_refclk_p[0]} ]
  set_property PACKAGE_PIN H6     [get_ports {sfp_gt_refclk_p[0]} ]
  set_property PACKAGE_PIN B2     [get_ports {sfp_tx_p[3]}        ]
  set_property PACKAGE_PIN D2     [get_ports {sfp_tx_p[2]}        ]

# ----- QSFP[1].[0..3]
# ----- I/O BANK 115
  set_property PACKAGE_PIN F2     [get_ports {sfp_tx_p[9]}        ]
  set_property PACKAGE_PIN H2     [get_ports {sfp_tx_p[8]}        ]
# create_clock -period 6.4        [get_ports {sfp_gt_refclk_p[1]} ]
# set_property PACKAGE_PIN L8     [get_ports {sfp_gt_refclk_p[1]} ]
  set_property PACKAGE_PIN K2     [get_ports {sfp_tx_p[7]}        ]
  set_property PACKAGE_PIN M2     [get_ports {sfp_tx_p[6]}        ]
  
# I/O BANK 113
# set_property PACKAGE_PIN U8     [get_ports {sfp_gt_refclk_p[2]} ]

#######################################################################################
########## ------------------   QSFP   ------------------- ##########
# =====================================================================================
  set_property PACKAGE_PIN H14      [get_ports  qsfp_ResetN_out[0]   ]
  set_property PACKAGE_PIN E14      [get_ports  qsfp_InitMode_out[0] ]
  set_property PACKAGE_PIN J14      [get_ports  qsfp_ModSelN_out[0]  ]
  set_property PACKAGE_PIN G14      [get_ports  qsfp_ModPrsN_in[0]   ]
  set_property PACKAGE_PIN E15      [get_ports  qsfp_IntN_in[0]      ]

  set_property PACKAGE_PIN H17      [get_ports  qsfp_ResetN_out[1]   ]
  set_property PACKAGE_PIN H15      [get_ports  qsfp_InitMode_out[1] ]
  set_property PACKAGE_PIN J17      [get_ports  qsfp_ModSelN_out[1]  ]
  set_property PACKAGE_PIN G17      [get_ports  qsfp_ModPrsN_in[1]   ]
  set_property PACKAGE_PIN F17      [get_ports  qsfp_IntN_in[1]      ]

  set_property IOSTANDARD LVCMOS33  [get_ports {qsfp_*}              ]
  set_false_path -to                [get_ports {qsfp_*_out[*]}       ]
  set_false_path -from              [get_ports {qsfp_*_in[*]}        ]

#######################################################################################
