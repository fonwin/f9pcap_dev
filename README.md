 [SFP+ 抓包] 設備
==================

* 從 SFP+ 抓包, 透過特定格式, 從 RJ45 送出抓包內容。

## 取得 source code
```
git clone git@github.com:fonwin/f9pcap_dev.git
cd  f9pcap_dev
git submodule init
git submodule update
```

* 10G MAC(Media Access Control) 使用 [alexforencich/verilog-ethernet](https://github.com/alexforencich/verilog-ethernet);

## 有支援的硬體
### 赛特凌威科技
* si_xc7k325t_7s32
  * 紅卡 / Kintex 7 XC7K325T / SFP * 2 + RJ45 * 2
  * 建 Vivado 專案:  source  build_f9pcap_si_xc7k325t_7s32.tcl
  * 在 Vivado 燒錄:  source  program_cfgmem_s25fl256s0.tcl
