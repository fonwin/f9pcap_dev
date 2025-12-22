#######################################################################################
#
# f9pcap_dev_impl.xdc
#
#######################################################################################

#######################################################################################
########## delay system reset ##########
  set_false_path -from [get_pins  sys_ctrl_inst/delay_rst_d*/C]
  
#######################################################################################
# ----- phy link st to all;
  set_false_path -from [get_pins {f9pcap_dev_i/phy[*].rgmii_phy_rx_*/st_link_speed_*/C}]
  set_false_path -from [get_pins {f9pcap_dev_i/phy[*].rgmii_phy_rx_*/st_link_ready_*/C}]

#######################################################################################
# ----- [rgmii_rx <=> sfp_tx] CDC path for [handshake or sync]
# -------------------------------------------------------------------------------------
  set DEV_ST_TO_TEMAC_INST f9pcap_dev_i/f9pcap_i/dev_st[*].to_temac_i/axis_store_fwd_i
  set_false_path -to   [get_pins "$DEV_ST_TO_TEMAC_INST/sync_*/*q1*/D"]
  set_false_path -to   [get_pins "$DEV_ST_TO_TEMAC_INST/*sync_*/sync_reg*/PRE"]
  set_false_path -to   [get_pins "$DEV_ST_TO_TEMAC_INST/frame_len_fifo_i/sync_*/*q1*/D"]
  set_false_path -from [get_pins "$DEV_ST_TO_TEMAC_INST/frame_len_fifo_i/fifomem/mem*/*/CLK"]

  set_false_path -to   [get_pins {f9pcap_dev_i/xcvr[*].tgbaser_axis_i/tgbaser_axis_i/tgbaser_xcvr_inst/*_reset_sync_inst/sync_reg*/PRE}]

#######################################################################################
# ----- async fifo for: sfp[0] <=> sfp[1]
  set_false_path -to   [get_pins {f9pcap_dev_i/xcvr[*].tgbaser_axis_i/fwd_cdc_i/*_reset_sync_inst/sync_reg*/PRE}]
  set_false_path -to   [get_pins {f9pcap_dev_i/xcvr[*].tgbaser_axis_i/fwd_cdc_i/a_fifo_i/sync_*/*q1*/D}]
  set_false_path -from [get_pins {f9pcap_dev_i/xcvr[*].tgbaser_axis_i/fwd_cdc_i/a_fifo_i/fifomem/mem*/*/CLK}]

#######################################################################################
# ----- 從 eeprom 讀出的資料, 長期有效, 所有地方皆可直接使用, 不用考慮時序(Timing)問題;
  set_false_path -from [get_pins {f9pcap_dev_i/f9mg_i/f9mg_cmd_sn_i/f9mg_sn_out*/C}] 
  set_false_path -from [get_pins {f9pcap_dev_i/f9mg_i/CDC_*/C}] 

#######################################################################################
  set_false_path -to [get_pins {f9pcap_dev_i/sync_f9mg_rx_join_i/sync_reg*/PRE}]

#######################################################################################
# ----- vio probe_in
# set_false_path -to [get_pins -hierarchical {*probe_in*/D} -filter {NAME =~ "*/inst/PROBE_IN_INST/probe_in*/D"}]
# set_false_path -to [get_pins -hierarchical {*vio_mon_buf_out*/D}]

#######################################################################################
