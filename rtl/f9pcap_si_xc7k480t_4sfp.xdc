#######################################################################################
#
# f9pcap_si_xc7k480t_4sfp.xdc
#
#######################################################################################
########## ------------------   SFP   ------------------- ##########
# =====================================================================================
# ===== (SFP*4) =====
# ----- 156.25M for SFP.
  create_clock -period 6.4        [get_ports {sfp_gt_refclk_p[0]} ]
  set_property PACKAGE_PIN H6     [get_ports {sfp_gt_refclk_p[0]} ]
# ----- I/O BANK 117
  set_property PACKAGE_PIN A8     [get_ports {sfp_tx_p[0]}        ]
  set_property PACKAGE_PIN C8     [get_ports {sfp_tx_p[1]}        ]
# ----- I/O BANK 116
  set_property PACKAGE_PIN D2     [get_ports {sfp_tx_p[2]}        ]
# ----- I/O BANK 115
  set_property PACKAGE_PIN M2     [get_ports {sfp_tx_p[3]}        ]

#######################################################################################
