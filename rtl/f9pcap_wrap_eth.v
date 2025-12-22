`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
//
// 輸入(抓包) => 輸出(Multicast + f9phdr_wrap() + 抓到的封包)
//               Multicast:42 = ETH:14 + IP:20 + UDP:8
//               f9phdr_wrap():16
//               共增加 58 bytes;
//
module f9pcap_wrap_eth #(
  `include "eth_ip_localparam.vh"
  /// 最少需要一個完整封包的大小 + sizeof(f9phdr);
  parameter  F9HDR_BUFFER_LENGTH = 1600,
  parameter  TTS_WIDTH           = 7 * BYTE_WIDTH,

  parameter  SAME_IO_CLK         = 1,

  parameter  I_DATA_WIDTH        = 64,
  localparam I_KEEP_WIDTH        = (I_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,

  parameter  O_DATA_WIDTH        = I_DATA_WIDTH,
  localparam O_KEEP_WIDTH        = (O_DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH
)(
  input  wire                     rst_in,
  /// Tick Time Stamp; 使用 gray code;
  input  wire[TTS_WIDTH -1:0]     tts_gray_in,
  input  wire[BYTE_WIDTH-1:0]     port_id_in,

  input  wire                     i_clk_in,
  /// - 配合外部收到的資料(例:SFP、PHY...), 通常不支援 ready 控制流量;
  ///   所以這裡沒有提供 i_ready_out;
  /// - 為了加上 f9phdr, 所以必須先在緩衝區收完封包;
  ///   - 若緩衝區不足, 則會反映在 f9phdr.BufFullCnt_;
  ///     此時仍會傳遞抓到的封包, 但會遺漏部分內容;
  input  wire                     i_valid_in,
  input  wire[I_DATA_WIDTH-1:0]   i_data_in,
  input  wire[I_KEEP_WIDTH-1:0]   i_keep_in,
  input  wire                     i_last_in,
  input  wire                     i_frame_err_in,
  /// - 後端的緩衝區不足, 造成拋棄封包, 會累計在 f9phdr.BufFullCnt_ 計數器;
  /// - 後端輸出的接收端, 在收到 outbuf_full_in=1 的下一個封包時,
  ///   會發現漏封包: f9phdr.FrameSeqNo_ 序號跳號;
  input  wire                     outbuf_full_in,

  output wire                     o_rst_out,
  input  wire                     o_clk_in,
  output wire                     o_valid_out,
  output wire[O_DATA_WIDTH-1:0]   o_data_out,
  output wire[O_KEEP_WIDTH-1:0]   o_keep_out,
  output wire                     o_last_out,

  input  wire[MAC_ADDR_WIDTH-1:0] EthSrcMAC,
  input  wire[IP_ADDR_WIDTH -1:0] IpSrcAddr,
  input  wire[IP_ADDR_WIDTH -1:0] IpDstAddr,
  input  wire[IP_PORT_WIDTH -1:0] UdpSrcPort,
  input  wire[IP_PORT_WIDTH -1:0] UdpDstPort
);
// ===========================================================================
wire                   f9p_valid;
wire                   f9p_ready;
wire[O_DATA_WIDTH-1:0] f9p_data;
wire[O_KEEP_WIDTH-1:0] f9p_keep;
wire                   f9p_last;
wire[15:0]             f9p_data_len;
f9phdr_wrap #(
  .F9HDR_BUFFER_LENGTH (F9HDR_BUFFER_LENGTH ),
  .TTS_WIDTH           (TTS_WIDTH           ),
  .SAME_IO_CLK         (SAME_IO_CLK         ),
  .I_DATA_WIDTH        (I_DATA_WIDTH        ),
  .O_DATA_WIDTH        (O_DATA_WIDTH        )
)
f9phdr_wrap_i(
  .rst_in          (rst_in         ),
  .i_clk_in        (i_clk_in       ),
  .tts_gray_in     (tts_gray_in    ),
  .port_id_in      (port_id_in     ),
  .i_valid_in      (i_valid_in     ),
  .i_data_in       (i_data_in      ),
  .i_keep_in       (i_keep_in      ),
  .i_last_in       (i_last_in      ),
  .i_frame_err_in  (i_frame_err_in ),
  .outbuf_full_in  (outbuf_full_in ),
  .o_rst_out       (o_rst_out      ),
  .o_clk_in        (o_clk_in       ),
  .o_valid_out     (f9p_valid      ),
  .o_ready_in      (f9p_ready      ),
  .o_data_out      (f9p_data       ),
  .o_keep_out      (f9p_keep       ),
  .o_last_out      (f9p_last       ),
  .o_data_len_out  (f9p_data_len   )
);
// ---------------------------------------------------------------------------
udp_eth_send #(
  .DATA_WIDTH     (O_DATA_WIDTH )
)
udp_eth_send_i(
  .rst_in         (o_rst_out    ),
  .clk_in         (o_clk_in     ),
  .i_valid_in     (f9p_valid    ),
  .i_ready_out    (f9p_ready    ),
  .i_data_in      (f9p_data     ),
//.i_keep_in      (f9p_keep     ),
//.i_last_in      (f9p_last     ),
  .i_data_len_in  (f9p_data_len ),
  .o_valid_out    (o_valid_out  ),
  .o_data_out     (o_data_out   ),
  .o_keep_out     (o_keep_out   ),
  .o_last_out     (o_last_out   ),
  .EthSrcMAC      (EthSrcMAC    ),
  .IpSrcAddr      (IpSrcAddr    ),
  .IpDstAddr      (IpDstAddr    ),
  .UdpSrcPort     (UdpSrcPort   ),
  .UdpDstPort     (UdpDstPort   ),
  .ext_payload_header_in ()
);
// ===========================================================================
endmodule
//////////////////////////////////////////////////////////////////////////////
