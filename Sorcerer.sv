//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  


assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;

wire [13:0] audio;

assign AUDIO_S = 0;
assign AUDIO_L = {audio, 2'b00};
assign AUDIO_R = {audio, 2'b00};
assign AUDIO_MIX = 2'b11;

assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"Sorcerer;;",
	"P1,Hardware;",
	"P1O[6:5],FDC,DreamDisk,Micropolis,None;",
	"P1O[8:7],Memory,56K,48K,32K;",
	"P2,Video;",
	"P2O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2O[2],TV Mode,PAL,NTSC;",
	"P2O[4:3],Noise,White,Red,Green,Blue;",
	"-;",
	"F1,BIN,Load BIN;",
	"F2,WAV,Load WAV;",
	"F3,BIN,Load PAC;",
	"D4F4,DAT,Load DiskBoot;",
	"F5,ROM,Load Monitor;",
	"D0S0,DSK,Mount disk A;",
	"D0S1,DSK,Mount disk B;",
	"D1S2,DSK,Mount disk C;",
	"D1S3,DSK,Mount disk D;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,14;", // [optional] config version 0-99.
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			  // so all options will get default values on first start.
	"V,v",`BUILD_DATE 
};


wire ioctl_download;
wire [15:0] ioctl_addr;
wire ioctl_wr;
wire [15:0] ioctl_index;
wire [15:0] ioctl_dout;
wire ioctl_wait;
wire quick_clear_busy;
wire diskboot_ready;

wire [3:0] img_mounted;
wire       img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba[4];
wire [5:0]  sd_blk_cnt[4];
wire [3:0]  sd_rd;
wire [3:0]  sd_wr;
wire [3:0]  sd_ack;
wire [13:0] sd_buff_addr;
wire [7:0]  sd_buff_dout;
wire [7:0]  sd_buff_din[4];
wire        sd_buff_wr;

localparam [15:0] IOCTL_ROM      = 16'd0;
localparam [15:0] IOCTL_QUICK    = 16'd1;
localparam [15:0] IOCTL_WAV      = 16'd2;
localparam [15:0] IOCTL_PAC      = 16'd3;
localparam [15:0] IOCTL_DISKBOOT = 16'd4;
localparam [15:0] IOCTL_MONITOR  = 16'd5;

wire [21:0] gamma_bus;
wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [1:0] fdc_mode = status[6:5];
wire        fdc_dreamdisk = fdc_mode == 2'd0;
wire        fdc_micropolis = fdc_mode == 2'd1;
wire        fdc_none = fdc_mode == 2'd2;
wire  [1:0] memory_mode = status[8:7];
wire [15:0] ram_top_exclusive = memory_mode == 2'd1 ? 16'hC000 :
                                memory_mode == 2'd2 ? 16'h8000 : 16'hE000;
wire [15:0] status_menumask = (fdc_none       ? 16'h0001 : 16'h0000) |
                              (~fdc_dreamdisk ? 16'h0002 : 16'h0000) |
                              (~fdc_micropolis ? 16'h0010 : 16'h0000);

assign ioctl_wait = ioctl_download && (ioctl_index == IOCTL_QUICK) && quick_clear_busy;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(4)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(status_menumask),
	
	.ps2_key(ps2_key),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	
    .ioctl_download(ioctl_download),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_wr(ioctl_wr),
    .ioctl_index(ioctl_index),
    .ioctl_wait(ioctl_wait)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys,clk12;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk12)
);

reg rom_loaded = 0;
reg pac_load_reset = 0;
reg [3:0] pac_reset_cnt = 0;
wire reset = RESET | status[0] | buttons[1] | ~rom_loaded | pac_load_reset;

wire [1:0] col = status[4:3];

///// VIDEO ////
//
//

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire [7:0] video;

////////////////////////////////////////////////////////////
// Keyboard
////////////////////////////////////////////////////////////

reg         key_strobe;
wire        key_pressed;
wire        key_extended;
wire  [7:0] key_code;
wire        upcase;

assign key_extended = ps2_key[8];
assign key_pressed  = ps2_key[9];
assign key_code     = ps2_key[7:0];

// Simple strobe on any change of ps2_key[10]
always @(posedge clk12) begin
    reg old_state;
    old_state <= ps2_key[10];
    if(old_state != ps2_key[10]) begin
       key_strobe <= ~key_strobe;
    end
end

wire        uart_en = 1'b0;

always @(posedge clk12) begin
`ifdef USE_AUDIO_IN
	cass_in[0] <= AUDIO_IN;
`else
	cass_in[0] <= UART_RXD;
`endif
	cass_in[1] <= cass_in[0];
end

`ifdef USE_EXPANSION
assign MOTOR_CTRL = cass_motor ? 1'b0 : 1'bZ;
assign UART_TXD = uart_tx;
assign UART_RTS = 1'b0;
assign EXP7 = 1'bZ;
`else
assign UART_TXD = uart_en ? uart_tx : ~cass_motor;
`endif

always @(posedge clk_sys) begin
    reg ioctl_downlD;

    ioctl_downlD <= ioctl_download;
    pac_load_reset <= |pac_reset_cnt;

    if (ioctl_downlD & ~ioctl_download) begin
        rom_loaded <= 1;
        if (ioctl_index == IOCTL_PAC || ioctl_index == IOCTL_MONITOR) pac_reset_cnt <= 4'hF;
    end else if (pac_reset_cnt) begin
        pac_reset_cnt <= pac_reset_cnt - 1'd1;
    end
end

wire [16:0] ram_addr;
wire        ram_rd, ram_wr;
wire  [7:0] ram_dout, ram_din;

wire        disk_req;
wire        disk_write;
wire        disk_write_commit;
wire        disk_ack;
wire        disk_wait;
wire  [1:0] disk_drive;
wire        disk_side;
wire  [6:0] disk_track;
wire  [3:0] disk_sector;
wire        disk_sector_1024;
wire  [9:0] disk_buf_addr;
wire  [7:0] disk_buf_dout;
wire        disk_buf_cpu_wr;
wire  [7:0] disk_buf_cpu_din;
reg   [3:0] disk_mounted = 0;
reg   [7:0] disk_buf[2048];
reg   [8:0] disk_base = 0;
reg         disk_ack_tgl = 0;
reg         disk_busy = 0;
reg         disk_rd = 0;
reg         disk_start = 0;
reg   [1:0] disk_gap = 0;
reg   [1:0] disk_last_block = 0;
reg         disk_hps_ack_seen = 0;
reg         disk_data_ready = 0;
reg         disk_wait_idle = 0;
reg         disk_req_meta = 0;
reg         disk_req_sync = 0;
reg         disk_req_last = 0;
reg         disk_req_pending = 0;
reg         disk_commit_meta = 0;
reg         disk_commit_sync = 0;
reg         disk_commit_last = 0;
reg         disk_commit_pending = 0;
reg         disk_writeback_busy = 0;
reg         disk_writeback_start = 0;
reg         disk_writeback_wait_idle = 0;
reg         disk_wr = 0;
reg   [1:0] disk_active_drive = 0;
reg  [31:0] disk_offset = 0;
reg  [31:0] disk_lba = 0;
wire  [3:0] core_disk_mounted = disk_mounted;
wire  [1:0] disk_req_host_drive = disk_drive;
wire [10:0] disk_buf_rd_addr = {2'b00, disk_base} + {1'b0, disk_buf_addr};
wire [10:0] disk_buf_wr_addr = sd_buff_addr[10:0];
wire [10:0] disk_buf_cpu_wr_addr = {2'b00, disk_base} + {1'b0, disk_buf_addr};
wire  [5:0] disk_blk_cnt = {4'd0, disk_last_block};
reg  [10:0] disk_end_addr = 0;

assign sd_wr = disk_wr ? (4'b0001 << disk_active_drive) : 4'b0000;
assign sd_buff_din[0] = disk_buf[sd_buff_addr[10:0]];
assign sd_buff_din[1] = disk_buf[sd_buff_addr[10:0]];
assign sd_buff_din[2] = disk_buf[sd_buff_addr[10:0]];
assign sd_buff_din[3] = disk_buf[sd_buff_addr[10:0]];
assign sd_lba[0] = disk_lba;
assign sd_lba[1] = disk_lba;
assign sd_lba[2] = disk_lba;
assign sd_lba[3] = disk_lba;
assign sd_blk_cnt[0] = disk_blk_cnt;
assign sd_blk_cnt[1] = disk_blk_cnt;
assign sd_blk_cnt[2] = disk_blk_cnt;
assign sd_blk_cnt[3] = disk_blk_cnt;
assign sd_rd = disk_rd ? (4'b0001 << disk_active_drive) : 4'b0000;
assign disk_ack = disk_ack_tgl;
assign disk_buf_dout = disk_buf[disk_buf_rd_addr];

always @(posedge clk_sys) begin
	reg [18:0] sector_linear;
	reg  [7:0] dream_track_side;
	reg [31:0] sector_offset;
	reg [10:0] sector_end_addr;

	disk_req_meta <= disk_req;
	disk_req_sync <= disk_req_meta;
	disk_req_last <= disk_req_sync;
	disk_commit_meta <= disk_write_commit;
	disk_commit_sync <= disk_commit_meta;
	disk_commit_last <= disk_commit_sync;
	if (disk_gap != 0) disk_gap <= disk_gap - 1'd1;
	if (disk_req_sync ^ disk_req_last) begin
		disk_req_pending <= 1;
	end
	if (disk_commit_sync ^ disk_commit_last) disk_commit_pending <= 1;

	if (img_mounted[0]) disk_mounted[0] <= 1;
	if (img_mounted[1]) disk_mounted[1] <= 1;
	if (img_mounted[2]) disk_mounted[2] <= 1;
	if (img_mounted[3]) disk_mounted[3] <= 1;

	if (disk_busy && sd_ack[disk_active_drive] && sd_buff_wr) begin
		disk_buf[disk_buf_wr_addr] <= sd_buff_dout;
		if (sd_buff_addr[10:0] == disk_end_addr)
			disk_data_ready <= 1;
	end
	if (disk_buf_cpu_wr) disk_buf[disk_buf_cpu_wr_addr] <= disk_buf_cpu_din;

	if (disk_start) begin
		disk_start <= 0;
		disk_rd <= 1;
	end

	if (disk_wait_idle && !sd_ack[disk_active_drive]) begin
		disk_wait_idle <= 0;
		disk_gap <= 2'd3;
	end

	if (~disk_busy && ~disk_start && !disk_wait_idle && (disk_gap == 0) && disk_req_pending && !sd_ack[disk_req_host_drive]) begin
		disk_req_pending <= 0;
		disk_active_drive <= disk_req_host_drive;
		if (disk_sector_1024) begin
			dream_track_side = {disk_track, 1'b0} + {7'd0, disk_side};
			sector_offset = 32'h00000200 +
			                ({24'd0, dream_track_side} << 12) +
			                ({24'd0, dream_track_side} << 10) +
			                ({24'd0, dream_track_side} << 8) +
			                (({28'd0, disk_sector} - 32'd1) << 10);
			sector_end_addr = {2'b00, sector_offset[8:0]} + 11'd1023;
		end else begin
			sector_linear = ({12'd0, disk_track} << 4) + {15'd0, disk_sector};
			sector_offset = sector_linear * 18'd270;
			sector_end_addr = {2'b00, sector_offset[8:0]} + 11'd269;
		end
		disk_offset <= sector_offset;
		disk_lba <= sector_offset[31:9];
		disk_base <= sector_offset[8:0];
		disk_end_addr <= sector_end_addr;
		disk_last_block <= sector_end_addr[10:9];
		disk_busy <= 1;
		disk_hps_ack_seen <= 0;
		disk_data_ready <= 0;
		disk_start <= 1;
	end else if (disk_busy && sd_ack[disk_active_drive]) begin
		disk_rd <= 0;
		disk_hps_ack_seen <= 1;
	end else if (disk_busy && disk_hps_ack_seen && disk_data_ready) begin
		disk_busy <= 0;
		disk_wait_idle <= 1;
		disk_ack_tgl <= ~disk_ack_tgl;
	end

	if (!disk_busy) begin
		disk_hps_ack_seen <= 0;
	end

	if (disk_writeback_start) begin
		disk_writeback_start <= 0;
		disk_wr <= 1;
	end

	if (disk_writeback_wait_idle && !sd_ack[disk_active_drive]) begin
		disk_writeback_wait_idle <= 0;
		disk_writeback_busy <= 0;
		disk_ack_tgl <= ~disk_ack_tgl;
	end

	if (!disk_busy && !disk_writeback_busy && !disk_writeback_start &&
	    !disk_writeback_wait_idle && disk_commit_pending &&
	    !sd_ack[disk_active_drive]) begin
		disk_commit_pending <= 0;
		disk_writeback_busy <= 1;
		disk_writeback_start <= 1;
	end else if (disk_writeback_busy && sd_ack[disk_active_drive]) begin
		disk_wr <= 0;
		disk_writeback_wait_idle <= 1;
	end
end

reg   [1:0] cass_in;
wire        cass_out;
wire        cass_motor;
wire        uart_tx;
wire        ledb;
wire        wav_uart_active;
wire        wav_uart_error;
wire        wav_uart_rx_active;
wire        wav_uart_rx_bit;
wire        wav_uart_high_baud;

assign LED_USER = ledb | wav_uart_active | wav_uart_error;
assign LED_DISK = 0;
assign LED_POWER = 0;

wav_uart_loader wav_uart_loader (
	.CLK(clk_sys),
	.RESET(reset),
	.DL(ioctl_download && (ioctl_index == IOCTL_WAV)),
	.DL_WE(ioctl_wr),
	.DL_DATA(ioctl_dout[7:0]),
	.RX_ACTIVE(wav_uart_rx_active),
	.RX_BIT(wav_uart_rx_bit),
	.HIGH_BAUD(wav_uart_high_baud),
	.ACTIVE(wav_uart_active),
	.ERROR(wav_uart_error)
);

sorcerer sorcerer (
	.RESET(reset),
	.CLK12(clk12),
	.HSYNC(HSync),
	.VSYNC(VSync),
	.HBLANK(HBlank),
	.VBLANK(VBlank),
	.VIDEO(video),
	.AUDIO(audio),
	.CASS_IN(cass_in[1]),
	.CASS_OUT(cass_out),
	.CASS_CTRL(cass_motor),
	.PAL(~status[2]),
	.ALTTIMINGS(1'b1),
	.TURBO(1'b0),

	.KEY_STROBE(key_strobe),
	.KEY_PRESSED(key_pressed),
	.KEY_EXTENDED(key_extended),
	.KEY_CODE(key_code),
	.UPCASE(upcase),

	.RAM_TOP_EXCLUSIVE(ram_top_exclusive),
	.RAM_ADDR(ram_addr),
	.RAM_RD(ram_rd),
	.RAM_WR(ram_wr),
	.RAM_DOUT(ram_dout),
	.RAM_DIN(ram_din),

	.UART_RX(UART_RXD),
	.UART_TX(uart_tx),

	.DL(ioctl_download),
	.DL_WAIT((ioctl_download && ioctl_index != IOCTL_DISKBOOT) || quick_clear_busy),
	.DL_CLK(clk_sys),
	.DL_ADDR(ioctl_addr[15:0]),
	.DL_DATA(ioctl_dout),
	.DL_WE(ioctl_wr),
	.DL_ROM(ioctl_index == IOCTL_ROM || ioctl_index == IOCTL_MONITOR),
	.DL_QUICK(ioctl_index == IOCTL_QUICK),
	.DL_PAC(ioctl_index == IOCTL_PAC),
	.DL_DISKBOOT(ioctl_index == IOCTL_DISKBOOT),
	.DL_CLEAR_BUSY(quick_clear_busy),
	.DISKBOOT_READY(diskboot_ready),
	.EXT_UART_RX_ACTIVE(wav_uart_rx_active),
	.EXT_UART_RX_BIT(wav_uart_rx_bit),
	.EXT_UART_HIGH_BAUD(wav_uart_high_baud),

	.DISK_MOUNTED(core_disk_mounted),
	.DISK_READONLY(img_readonly),
	.DISK_REQ(disk_req),
	.DISK_WRITE(disk_write),
	.DISK_WRITE_COMMIT(disk_write_commit),
	.DISK_ACK(disk_ack),
	.DISK_WAIT(disk_wait),
	.DISK_DRIVE(disk_drive),
	.DISK_SIDE(disk_side),
	.DISK_TRACK(disk_track),
	.DISK_SECTOR(disk_sector),
	.DISK_SECTOR_1024(disk_sector_1024),
	.DISK_BUF_ADDR(disk_buf_addr),
	.DISK_BUF_DOUT(disk_buf_dout),
	.DISK_BUF_WR(disk_buf_cpu_wr),
	.DISK_BUF_DIN(disk_buf_cpu_din),

	.FDC_MICROPOLIS(fdc_micropolis),
	.FDC_DREAMDISK(fdc_dreamdisk),
	.UNL_PAC(status[1]),
	.LED(ledb)
);

dpram #(
    .data_width_g (8),
    .addr_width_g (16)
) ram (
    .clock     (clk_sys),
    .ram_cs    (ram_rd),
    .wren_a    (ram_wr),
    .address_a (ram_addr),
    .data_a    (ram_din),
    .q_a       (ram_dout)
);

///////////////////   VIDEO   ////////////////////
wire rotate_ccw = 0;
wire no_rotate = 1'b1;
wire flip = ~no_rotate;
wire video_rotated;

//screen_rotate screen_rotate (.*);

assign VGA_SL = 0;
assign CLK_VIDEO = clk12;
assign CE_PIXEL = 1'b1;

assign VGA_DE = ~(HBlank | VBlank);
assign VGA_HS = HSync;
assign VGA_VS = VSync;

assign VGA_R = video ? 8'hFF : 8'h00;
assign VGA_G = video ? 8'hFF : 8'h00;
assign VGA_B = video ? 8'hFF : 8'h00;

/*
arcade_video #(256,24) arcade_video
(
	.*,
	.clk_video(clk_sys),
	.RGB_in({ video, video, video }),
	.HBlank(HBlank),
	.VBlank(VBlank),
	.HSync(HSync),
	.VSync(VSync),
	.fx(0)
);
*/
endmodule

module wav_uart_loader
(
	input        CLK,
	input        RESET,
	input        DL,
	input        DL_WE,
	input  [7:0] DL_DATA,
	output       RX_ACTIVE,
	output       RX_BIT,
	output       HIGH_BAUD,
	output       ACTIVE,
	output       ERROR
);

localparam [14:0] BUF_LAST = 15'h7FFF;
localparam [17:0] BIT_TICKS_300  = 18'd168498; // clk_sys ~= 50.54945 MHz / 300
localparam [17:0] BIT_TICKS_1200 = 18'd42124;  // clk_sys ~= 50.54945 MHz / 1200
localparam [10:0] START_IDLE_BITS = 11'd1200;
localparam [5:0] INTER_BYTE_IDLE_BITS = 6'd24;

wire        sample_valid;
wire signed [15:0] sample;
wire        wav_valid;
wire        wav_error;
wire        byte_valid_300;
wire  [7:0] byte_300;
wire        byte_valid_300_strict;
wire  [7:0] byte_300_strict;
wire        byte_valid_300_raw;
wire  [7:0] byte_300_raw;
wire        byte_valid_1200;
wire  [7:0] byte_1200;
wire        byte_valid_basic;
wire  [7:0] byte_basic;
reg         dl_d;
reg         overflow;

reg  [7:0] buf_300 [0:BUF_LAST];
reg  [7:0] buf_300_strict [0:BUF_LAST];
reg  [7:0] buf_300_raw [0:BUF_LAST];
reg  [7:0] buf_1200 [0:BUF_LAST];
reg  [7:0] buf_basic [0:BUF_LAST];
reg [14:0] count_300;
reg [14:0] count_300_strict;
reg [14:0] count_300_raw;
reg [14:0] count_1200;
reg [14:0] count_basic;
reg [14:0] start_300;
reg [14:0] start_300_strict;
reg [14:0] start_300_raw;
reg [14:0] start_1200;
reg [14:0] start_basic;
reg [14:0] end_300;
reg [14:0] end_300_strict;
reg [14:0] end_300_raw;
reg [14:0] end_1200;
reg [14:0] end_basic;
reg        valid_300;
reg        valid_300_strict;
reg        valid_300_raw;
reg        valid_1200;
reg        valid_basic;
reg        done_300_d;
reg        done_300_strict_d;
reg        done_300_raw_d;
reg        done_1200_d;
reg        basic_done_d;

wire        ram_wr_unused_300;
wire [15:0] ram_addr_unused_300;
wire  [7:0] ram_data_unused_300;
wire        done_300;
wire        error_300;
wire        header_300;
wire [15:0] run_addr_unused_300;
wire        ram_wr_unused_300_strict;
wire [15:0] ram_addr_unused_300_strict;
wire  [7:0] ram_data_unused_300_strict;
wire        done_300_strict;
wire        error_300_strict;
wire        header_300_strict;
wire [15:0] run_addr_unused_300_strict;
wire        ram_wr_unused_300_raw;
wire [15:0] ram_addr_unused_300_raw;
wire  [7:0] ram_data_unused_300_raw;
wire        done_300_raw;
wire        error_300_raw;
wire        header_300_raw;
wire [15:0] run_addr_unused_300_raw;
wire        ram_wr_unused_1200;
wire [15:0] ram_addr_unused_1200;
wire  [7:0] ram_data_unused_1200;
wire        done_1200;
wire        error_1200;
wire        header_1200;
wire [15:0] run_addr_unused_1200;
wire        basic_ram_wr_unused;
wire [15:0] basic_ram_addr_unused;
wire  [7:0] basic_ram_data_unused;
wire        basic_done;
wire        basic_error;
wire        basic_header;
wire [15:0] basic_end_unused;

reg        replay;
reg        replay_high_baud;
reg  [2:0] replay_sel;
reg [14:0] replay_pos;
reg [14:0] replay_end;
reg [17:0] bit_ticks;
reg [17:0] bit_timer;
reg  [3:0] bit_pos;
reg [10:0] idle_bits;
reg  [5:0] inter_byte_bits;
reg  [7:0] replay_byte;
reg        rx_bit;

wire starting = DL & ~dl_d;
wire stopping = ~DL & dl_d;

wav_sample_reader wav_sample_reader
(
	.CLK(CLK),
	.RESET(RESET),
	.DL(DL),
	.DL_WE(DL_WE),
	.DL_DATA(DL_DATA),
	.SAMPLE_VALID(sample_valid),
	.SAMPLE(sample),
	.VALID(wav_valid),
	.ERROR(wav_error)
);

wav_fsk_uart_decoder #(
	.HYSTERESIS(16'sd4000),
	.MIN_EDGE_SAMPLES(8'd3),
	.SHORT_THRESHOLD(8'd14),
	.SHORT_TARGET(5'd16),
	.LONG_TARGET(5'd8)
) decoder_300 (
	.CLK(CLK),
	.RESET(RESET | starting),
	.SAMPLE_VALID(sample_valid),
	.SAMPLE(sample),
	.BYTE_VALID(byte_valid_300),
	.BYTE(byte_300)
);

wav_fsk_uart_decoder #(
	.HYSTERESIS(16'sd8000),
	.MIN_EDGE_SAMPLES(8'd4),
	.SHORT_THRESHOLD(8'd14),
	.SHORT_TARGET(5'd16),
	.LONG_TARGET(5'd8)
) decoder_300_strict (
	.CLK(CLK),
	.RESET(RESET | starting),
	.SAMPLE_VALID(sample_valid),
	.SAMPLE(sample),
	.BYTE_VALID(byte_valid_300_strict),
	.BYTE(byte_300_strict)
);

wav_fsk_uart_decoder #(
	.HYSTERESIS(16'sd0),
	.MIN_EDGE_SAMPLES(8'd1),
	.SHORT_THRESHOLD(8'd14),
	.SHORT_TARGET(5'd16),
	.LONG_TARGET(5'd8)
) decoder_300_raw (
	.CLK(CLK),
	.RESET(RESET | starting),
	.SAMPLE_VALID(sample_valid),
	.SAMPLE(sample),
	.BYTE_VALID(byte_valid_300_raw),
	.BYTE(byte_300_raw)
);

wav_fsk_uart_decoder #(
	.HYSTERESIS(16'sd4000),
	.MIN_EDGE_SAMPLES(8'd1),
	.SHORT_THRESHOLD(8'd28),
	.SHORT_TARGET(5'd2),
	.LONG_TARGET(5'd1)
) decoder_1200 (
	.CLK(CLK),
	.RESET(RESET | starting),
	.SAMPLE_VALID(sample_valid),
	.SAMPLE(sample),
	.BYTE_VALID(byte_valid_1200),
	.BYTE(byte_1200)
);

wav_core_uart_decoder decoder_basic (
	.CLK(CLK),
	.RESET(RESET | starting),
	.SAMPLE_VALID(sample_valid),
	.SAMPLE(sample),
	.BYTE_VALID(byte_valid_basic),
	.BYTE(byte_basic)
);

sorcerer_tape_parser parser_300
(
	.CLK(CLK),
	.RESET(RESET | starting),
	.ENABLE(1'b1),
	.BYTE_VALID(byte_valid_300),
	.BYTE(byte_300),
	.RAM_WR(ram_wr_unused_300),
	.RAM_ADDR(ram_addr_unused_300),
	.RAM_DATA(ram_data_unused_300),
	.HEADER_FOUND(header_300),
	.DONE(done_300),
	.ERROR(error_300),
	.RUN_ADDR(run_addr_unused_300)
);

sorcerer_tape_parser parser_300_strict
(
	.CLK(CLK),
	.RESET(RESET | starting),
	.ENABLE(1'b1),
	.BYTE_VALID(byte_valid_300_strict),
	.BYTE(byte_300_strict),
	.RAM_WR(ram_wr_unused_300_strict),
	.RAM_ADDR(ram_addr_unused_300_strict),
	.RAM_DATA(ram_data_unused_300_strict),
	.HEADER_FOUND(header_300_strict),
	.DONE(done_300_strict),
	.ERROR(error_300_strict),
	.RUN_ADDR(run_addr_unused_300_strict)
);

sorcerer_tape_parser parser_300_raw
(
	.CLK(CLK),
	.RESET(RESET | starting),
	.ENABLE(1'b1),
	.BYTE_VALID(byte_valid_300_raw),
	.BYTE(byte_300_raw),
	.RAM_WR(ram_wr_unused_300_raw),
	.RAM_ADDR(ram_addr_unused_300_raw),
	.RAM_DATA(ram_data_unused_300_raw),
	.HEADER_FOUND(header_300_raw),
	.DONE(done_300_raw),
	.ERROR(error_300_raw),
	.RUN_ADDR(run_addr_unused_300_raw)
);

sorcerer_tape_parser parser_1200
(
	.CLK(CLK),
	.RESET(RESET | starting),
	.ENABLE(1'b1),
	.BYTE_VALID(byte_valid_1200),
	.BYTE(byte_1200),
	.RAM_WR(ram_wr_unused_1200),
	.RAM_ADDR(ram_addr_unused_1200),
	.RAM_DATA(ram_data_unused_1200),
	.HEADER_FOUND(header_1200),
	.DONE(done_1200),
	.ERROR(error_1200),
	.RUN_ADDR(run_addr_unused_1200)
);

sorcerer_basic_tape_parser parser_basic
(
	.CLK(CLK),
	.RESET(RESET | starting),
	.ENABLE(1'b1),
	.BYTE_VALID(byte_valid_basic),
	.BYTE(byte_basic),
	.RAM_WR(basic_ram_wr_unused),
	.RAM_ADDR(basic_ram_addr_unused),
	.RAM_DATA(basic_ram_data_unused),
	.HEADER_FOUND(basic_header),
	.DONE(basic_done),
	.ERROR(basic_error),
	.END_ADDR(basic_end_unused)
);

always @(posedge CLK) begin
	dl_d <= DL;
	if (RESET | starting) begin
		count_300 <= 0;
		count_300_strict <= 0;
		count_300_raw <= 0;
		count_1200 <= 0;
		count_basic <= 0;
		start_300 <= 0;
		start_300_strict <= 0;
		start_300_raw <= 0;
		start_1200 <= 0;
		start_basic <= 0;
		end_300 <= 0;
		end_300_strict <= 0;
		end_300_raw <= 0;
		end_1200 <= 0;
		end_basic <= 0;
		valid_300 <= 0;
		valid_300_strict <= 0;
		valid_300_raw <= 0;
		valid_1200 <= 0;
		valid_basic <= 0;
		done_300_d <= 0;
		done_300_strict_d <= 0;
		done_300_raw_d <= 0;
		done_1200_d <= 0;
		basic_done_d <= 0;
		overflow <= 0;
		replay <= 0;
		replay_high_baud <= 0;
		replay_sel <= 0;
		replay_pos <= 0;
		replay_end <= 0;
		bit_ticks <= BIT_TICKS_1200;
		bit_timer <= 0;
		bit_pos <= 4'd11;
		idle_bits <= 0;
		inter_byte_bits <= 0;
		replay_byte <= 0;
		rx_bit <= 1;
	end else begin
		done_300_d <= done_300;
		done_300_strict_d <= done_300_strict;
		done_300_raw_d <= done_300_raw;
		done_1200_d <= done_1200;
		basic_done_d <= basic_done;

		if (DL) begin
			if (byte_valid_300) begin
				buf_300[count_300] <= byte_300;
				if (count_300 != BUF_LAST)
					count_300 <= count_300 + 1'd1;
				else
					overflow <= 1;
			end
			if (byte_valid_300_strict) begin
				buf_300_strict[count_300_strict] <= byte_300_strict;
				if (count_300_strict != BUF_LAST)
					count_300_strict <= count_300_strict + 1'd1;
				else
					overflow <= 1;
			end
			if (byte_valid_300_raw) begin
				buf_300_raw[count_300_raw] <= byte_300_raw;
				if (count_300_raw != BUF_LAST)
					count_300_raw <= count_300_raw + 1'd1;
				else
					overflow <= 1;
			end
			if (byte_valid_1200) begin
				buf_1200[count_1200] <= byte_1200;
				if (count_1200 != BUF_LAST)
					count_1200 <= count_1200 + 1'd1;
				else
					overflow <= 1;
			end
			if (byte_valid_basic) begin
				buf_basic[count_basic] <= byte_basic;
				if (count_basic != BUF_LAST)
					count_basic <= count_basic + 1'd1;
				else
					overflow <= 1;
			end

			if (header_300 && !valid_300) begin
				valid_300 <= 1;
				start_300 <= (count_300 > 15'd119) ? (count_300 - 15'd119) : 15'd0;
			end
			if (header_300_strict && !valid_300_strict) begin
				valid_300_strict <= 1;
				start_300_strict <= (count_300_strict > 15'd119) ? (count_300_strict - 15'd119) : 15'd0;
			end
			if (header_300_raw && !valid_300_raw) begin
				valid_300_raw <= 1;
				start_300_raw <= (count_300_raw > 15'd119) ? (count_300_raw - 15'd119) : 15'd0;
			end
			if (header_1200 && !valid_1200) begin
				valid_1200 <= 1;
				start_1200 <= (count_1200 > 15'd119) ? (count_1200 - 15'd119) : 15'd0;
			end
			if (basic_header && !valid_basic) begin
				valid_basic <= 1;
				start_basic <= 0;
			end
			if (done_300 && !done_300_d)
				end_300 <= count_300;
			if (done_300_strict && !done_300_strict_d)
				end_300_strict <= count_300_strict;
			if (done_300_raw && !done_300_raw_d)
				end_300_raw <= count_300_raw;
			if (done_1200 && !done_1200_d)
				end_1200 <= count_1200;
			if (basic_done && !basic_done_d)
				end_basic <= count_basic;
		end

		if (stopping && !overflow) begin
			if (done_300 | (valid_300 & !done_300_strict & !done_300_raw & !done_1200 & !basic_done & !valid_1200 & !valid_basic)) begin
				replay <= 1;
				replay_high_baud <= 0;
				replay_sel <= 3'd0;
				replay_pos <= start_300;
				replay_end <= done_300 ? end_300 : count_300;
				bit_ticks <= BIT_TICKS_300;
				bit_timer <= BIT_TICKS_300;
				bit_pos <= 4'd11;
				idle_bits <= START_IDLE_BITS;
				inter_byte_bits <= 0;
				rx_bit <= 1;
			end else if (done_300_strict) begin
				replay <= 1;
				replay_high_baud <= 0;
				replay_sel <= 3'd1;
				replay_pos <= start_300_strict;
				replay_end <= end_300_strict;
				bit_ticks <= BIT_TICKS_300;
				bit_timer <= BIT_TICKS_300;
				bit_pos <= 4'd11;
				idle_bits <= START_IDLE_BITS;
				inter_byte_bits <= 0;
				rx_bit <= 1;
			end else if (done_300_raw | (valid_300_raw & !done_1200 & !basic_done & !valid_1200 & !valid_basic)) begin
				replay <= 1;
				replay_high_baud <= 0;
				replay_sel <= 3'd2;
				replay_pos <= start_300_raw;
				replay_end <= done_300_raw ? end_300_raw : count_300_raw;
				bit_ticks <= BIT_TICKS_300;
				bit_timer <= BIT_TICKS_300;
				bit_pos <= 4'd11;
				idle_bits <= START_IDLE_BITS;
				inter_byte_bits <= 0;
				rx_bit <= 1;
			end else if (done_1200) begin
				replay <= 1;
				replay_high_baud <= 1;
				replay_sel <= 3'd3;
				replay_pos <= start_1200;
				replay_end <= end_1200;
				bit_ticks <= BIT_TICKS_1200;
				bit_timer <= BIT_TICKS_1200;
				bit_pos <= 4'd11;
				idle_bits <= START_IDLE_BITS;
				inter_byte_bits <= 0;
				rx_bit <= 1;
			end else if (basic_done | valid_basic) begin
				replay <= 1;
				replay_high_baud <= 1;
				replay_sel <= 3'd4;
				replay_pos <= start_basic;
				replay_end <= basic_done ? end_basic : count_basic;
				bit_ticks <= BIT_TICKS_1200;
				bit_timer <= BIT_TICKS_1200;
				bit_pos <= 4'd11;
				idle_bits <= START_IDLE_BITS;
				inter_byte_bits <= 0;
				rx_bit <= 1;
			end
		end

		if (replay) begin
			if (bit_timer != 0) begin
				bit_timer <= bit_timer - 1'd1;
			end else begin
				bit_timer <= bit_ticks;
				if (idle_bits != 0) begin
					idle_bits <= idle_bits - 1'd1;
					rx_bit <= 1;
				end else if (bit_pos == 4'd11) begin
					if (inter_byte_bits != 0) begin
						inter_byte_bits <= inter_byte_bits - 1'd1;
						rx_bit <= 1;
					end else if (replay_pos == replay_end) begin
						replay <= 0;
						rx_bit <= 1;
					end else begin
						case (replay_sel)
							3'd0: replay_byte <= buf_300[replay_pos];
							3'd1: replay_byte <= buf_300_strict[replay_pos];
							3'd2: replay_byte <= buf_300_raw[replay_pos];
							3'd3: replay_byte <= buf_1200[replay_pos];
							default: replay_byte <= buf_basic[replay_pos];
						endcase
						replay_pos <= replay_pos + 1'd1;
						bit_pos <= 0;
						rx_bit <= 0;
					end
				end else if (bit_pos < 4'd8) begin
					rx_bit <= replay_byte[bit_pos];
					bit_pos <= bit_pos + 1'd1;
				end else begin
					rx_bit <= 1;
					if (bit_pos == 4'd9) begin
						bit_pos <= 4'd11;
						inter_byte_bits <= INTER_BYTE_IDLE_BITS;
					end else begin
						bit_pos <= bit_pos + 1'd1;
					end
				end
			end
		end
	end
end

assign RX_ACTIVE = replay;
assign RX_BIT = rx_bit;
assign HIGH_BAUD = replay_high_baud;
assign ACTIVE = DL | replay;
assign ERROR = wav_error | overflow | ((done_300 | done_300_strict | done_300_raw | done_1200 | valid_300 | valid_300_strict | valid_300_raw | basic_done | valid_basic) ? 1'b0 : (stopping & ~overflow));

endmodule

module wav_sample_reader
(
	input        CLK,
	input        RESET,
	input        DL,
	input        DL_WE,
	input  [7:0] DL_DATA,
	output reg        SAMPLE_VALID,
	output reg signed [15:0] SAMPLE,
	output reg        VALID,
	output reg        ERROR
);

localparam [2:0]
	ST_HEADER     = 3'd0,
	ST_CHUNK_ID   = 3'd1,
	ST_CHUNK_SIZE = 3'd2,
	ST_FMT        = 3'd3,
	ST_SKIP       = 3'd4,
	ST_DATA       = 3'd5,
	ST_DONE       = 3'd6;

reg        dl_d;
reg  [2:0] state;
reg  [3:0] header_pos;
reg  [1:0] chunk_pos;
reg [31:0] chunk_id;
reg [31:0] chunk_size;
reg [31:0] chunk_left;
reg  [4:0] fmt_pos;
reg [15:0] audio_format;
reg [15:0] channels;
reg [31:0] sample_rate;
reg [15:0] bits_per_sample;
reg  [4:0] frame_pos;
reg  [4:0] frame_bytes;
reg  [7:0] sample_lo;
reg signed [15:0] next_sample;

wire starting = DL & ~dl_d;
wire [4:0] bytes_per_sample = (bits_per_sample == 16) ? 5'd2 : 5'd1;
wire [4:0] calc_frame_bytes = channels[4:0] * bytes_per_sample;

always @(posedge CLK) begin
	dl_d <= DL;
	SAMPLE_VALID <= 0;

	if (RESET | starting) begin
		state <= ST_HEADER;
		header_pos <= 0;
		chunk_pos <= 0;
		chunk_id <= 0;
		chunk_size <= 0;
		chunk_left <= 0;
		fmt_pos <= 0;
		audio_format <= 1;
		channels <= 1;
		sample_rate <= 44100;
		bits_per_sample <= 16;
		frame_pos <= 0;
		frame_bytes <= 2;
		sample_lo <= 0;
		SAMPLE <= 0;
		VALID <= 1;
		ERROR <= 0;
	end else if (DL & DL_WE & !ERROR) begin
		case (state)
			ST_HEADER: begin
				case (header_pos)
					0: if (DL_DATA != "R") ERROR <= 1;
					1: if (DL_DATA != "I") ERROR <= 1;
					2: if (DL_DATA != "F") ERROR <= 1;
					3: if (DL_DATA != "F") ERROR <= 1;
					8: if (DL_DATA != "W") ERROR <= 1;
					9: if (DL_DATA != "A") ERROR <= 1;
					10: if (DL_DATA != "V") ERROR <= 1;
					11: if (DL_DATA != "E") ERROR <= 1;
					default: ;
				endcase
				if (header_pos == 4'd11) begin
					state <= ST_CHUNK_ID;
					header_pos <= 0;
					chunk_pos <= 0;
					chunk_id <= 0;
				end else begin
					header_pos <= header_pos + 1'd1;
				end
			end

			ST_CHUNK_ID: begin
				chunk_id <= {chunk_id[23:0], DL_DATA};
				if (chunk_pos == 2'd3) begin
					state <= ST_CHUNK_SIZE;
					chunk_pos <= 0;
					chunk_size <= 0;
				end else begin
					chunk_pos <= chunk_pos + 1'd1;
				end
			end

			ST_CHUNK_SIZE: begin
				chunk_size <= chunk_size | ({24'd0, DL_DATA} << {chunk_pos, 3'b000});
				if (chunk_pos == 2'd3) begin
					chunk_left <= chunk_size | ({24'd0, DL_DATA} << 24);
					chunk_pos <= 0;
					if (chunk_id == "fmt ") begin
						state <= ST_FMT;
						fmt_pos <= 0;
					end else if (chunk_id == "data") begin
						state <= ST_DATA;
						frame_pos <= 0;
						frame_bytes <= calc_frame_bytes;
						if (audio_format != 16'd1) ERROR <= 1;
						if (sample_rate == 0) ERROR <= 1;
						if (channels == 0 || channels > 16'd2) ERROR <= 1;
						if (bits_per_sample != 16'd8 && bits_per_sample != 16'd16) ERROR <= 1;
					end else begin
						state <= ST_SKIP;
					end
				end else begin
					chunk_pos <= chunk_pos + 1'd1;
				end
			end

			ST_FMT: begin
				case (fmt_pos)
					0: audio_format[7:0] <= DL_DATA;
					1: audio_format[15:8] <= DL_DATA;
					2: channels[7:0] <= DL_DATA;
					3: channels[15:8] <= DL_DATA;
					4: sample_rate[7:0] <= DL_DATA;
					5: sample_rate[15:8] <= DL_DATA;
					6: sample_rate[23:16] <= DL_DATA;
					7: sample_rate[31:24] <= DL_DATA;
					14: bits_per_sample[7:0] <= DL_DATA;
					15: bits_per_sample[15:8] <= DL_DATA;
					default: ;
				endcase
				fmt_pos <= fmt_pos + 1'd1;
				if (chunk_left == 1) begin
					state <= ST_CHUNK_ID;
					chunk_pos <= 0;
					chunk_id <= 0;
					chunk_size <= 0;
				end
				chunk_left <= chunk_left - 1'd1;
			end

			ST_SKIP: begin
				if (chunk_left == 1) begin
					state <= ST_CHUNK_ID;
					chunk_pos <= 0;
					chunk_id <= 0;
					chunk_size <= 0;
				end
				chunk_left <= chunk_left - 1'd1;
			end

			ST_DATA: begin
				if (bits_per_sample == 16'd8) begin
					if (frame_pos == 0)
						next_sample = {DL_DATA ^ 8'h80, 8'h00};
				end else begin
					if (frame_pos == 0)
						sample_lo <= DL_DATA;
					else if (frame_pos == 1)
						next_sample = {DL_DATA, sample_lo};
				end

				if (frame_pos == frame_bytes - 1'd1) begin
					SAMPLE <= next_sample;
					SAMPLE_VALID <= 1;
					frame_pos <= 0;
				end else begin
					frame_pos <= frame_pos + 1'd1;
				end

				if (chunk_left == 1)
					state <= ST_DONE;
				chunk_left <= chunk_left - 1'd1;
			end

			default: ;
		endcase
	end
end

endmodule

module wav_fsk_uart_decoder
#(
	parameter signed [15:0] HYSTERESIS = 16'sd4000,
	parameter [7:0] MIN_EDGE_SAMPLES = 8'd1,
	parameter [7:0] SHORT_THRESHOLD = 8'd28,
	parameter [4:0] SHORT_TARGET = 5'd2,
	parameter [4:0] LONG_TARGET = 5'd1
)
(
	input        CLK,
	input        RESET,
	input        SAMPLE_VALID,
	input signed [15:0] SAMPLE,
	output reg        BYTE_VALID,
	output reg  [7:0] BYTE
);

reg        level;
reg        have_level;
reg        have_edge;
reg  [7:0] edge_count;
reg        pulse_kind;
reg  [4:0] pulse_count;
reg        uart_in_byte;
reg  [3:0] uart_bit_pos;
reg  [7:0] uart_byte;

always @(posedge CLK) begin
	reg next_level;
	reg is_short;
	reg [4:0] pulse_target;
	reg [4:0] next_pulse_count;
	reg fsk_bit;

	BYTE_VALID <= 0;

	if (RESET) begin
		level <= 0;
		have_level <= 0;
		have_edge <= 0;
		edge_count <= 0;
		pulse_kind <= 0;
		pulse_count <= 0;
		uart_in_byte <= 0;
		uart_bit_pos <= 0;
		uart_byte <= 0;
		BYTE <= 0;
	end else if (SAMPLE_VALID) begin
		next_level = level;
		if (!have_level) begin
			next_level = (SAMPLE >= 0);
			have_level <= 1;
		end else begin
			if (!level && SAMPLE >= HYSTERESIS)
				next_level = 1;
			else if (level && SAMPLE <= -HYSTERESIS)
				next_level = 0;
		end

		if (have_level && next_level != level) begin
			if (edge_count >= MIN_EDGE_SAMPLES) begin
				if (have_edge) begin
					is_short = edge_count <= SHORT_THRESHOLD;
					pulse_target = is_short ? SHORT_TARGET : LONG_TARGET;
					next_pulse_count = (is_short == pulse_kind) ? pulse_count + 1'd1 : 5'd1;

					if (next_pulse_count >= pulse_target) begin
						fsk_bit = is_short;
						pulse_count <= 0;
						if (!uart_in_byte) begin
							if (!fsk_bit) begin
								uart_in_byte <= 1;
								uart_bit_pos <= 0;
								uart_byte <= 0;
							end
						end else if (uart_bit_pos != 4'd8) begin
							uart_byte[uart_bit_pos] <= fsk_bit;
							uart_bit_pos <= uart_bit_pos + 1'd1;
						end else begin
							uart_in_byte <= 0;
							if (fsk_bit) begin
								BYTE <= uart_byte;
								BYTE_VALID <= 1;
							end
						end
					end else begin
						pulse_count <= next_pulse_count;
					end
					pulse_kind <= is_short;
				end
				edge_count <= 0;
				have_edge <= 1;
				level <= next_level;
			end else if (edge_count != 8'hFF) begin
				edge_count <= edge_count + 1'd1;
			end
		end else if (edge_count != 8'hFF) begin
			edge_count <= edge_count + 1'd1;
			level <= next_level;
		end
	end
end

endmodule

module wav_core_uart_decoder
(
	input        CLK,
	input        RESET,
	input        SAMPLE_VALID,
	input signed [15:0] SAMPLE,
	output reg        BYTE_VALID,
	output reg  [7:0] BYTE
);

reg        level;
reg        level_d;
reg        decoder0;
reg        decoder1;
reg        decoder2;
reg  [3:0] decoder_cnt;
reg        serial_d;
reg        uart_busy;
localparam [5:0] BIT_SAMPLES = 6'd18;

reg  [5:0] sample_count;
reg  [3:0] bit_pos;
reg  [7:0] uart_byte;

always @(posedge CLK) begin
	BYTE_VALID <= 0;

	if (RESET) begin
		level <= 0;
		level_d <= 0;
		decoder0 <= 0;
		decoder1 <= 0;
		decoder2 <= 1;
		decoder_cnt <= 4;
		serial_d <= 1;
		uart_busy <= 0;
		sample_count <= 0;
		bit_pos <= 0;
		uart_byte <= 0;
		BYTE <= 0;
	end else if (SAMPLE_VALID) begin
		level <= SAMPLE >= 0;
		if (level_d ^ level) begin
			decoder0 <= 1;
			decoder1 <= decoder0;
		end
		level_d <= level;

		if (decoder0)
			decoder_cnt <= decoder_cnt + 1'd1;
		else
			decoder_cnt <= 4;

		if (decoder_cnt == 4'hE) begin
			decoder0 <= 0;
			if (decoder0)
				decoder2 <= decoder1;
		end else if (decoder_cnt == 4'hF) begin
			decoder_cnt <= 4;
		end

		serial_d <= decoder2;
		if (!uart_busy) begin
			if (serial_d && !decoder2) begin
				uart_busy <= 1;
				sample_count <= BIT_SAMPLES + (BIT_SAMPLES >> 1);
				bit_pos <= 0;
				uart_byte <= 0;
			end
		end else if (sample_count != 0) begin
			sample_count <= sample_count - 1'd1;
		end else begin
			sample_count <= BIT_SAMPLES - 1'd1;
			if (bit_pos < 4'd8) begin
				uart_byte[bit_pos] <= decoder2;
				bit_pos <= bit_pos + 1'd1;
			end else begin
				uart_busy <= 0;
				if (decoder2) begin
					BYTE <= uart_byte;
					BYTE_VALID <= 1;
				end
			end
		end
	end
end

endmodule

module sorcerer_basic_tape_parser
(
	input        CLK,
	input        RESET,
	input        ENABLE,
	input        BYTE_VALID,
	input  [7:0] BYTE,
	output reg        RAM_WR,
	output reg [15:0] RAM_ADDR,
	output reg  [7:0] RAM_DATA,
	output reg        HEADER_FOUND,
	output reg        DONE,
	output reg        ERROR,
	output reg [15:0] END_ADDR
);

localparam RAM_TOP_EXCLUSIVE = 16'hE000;
localparam BASIC_START = 16'h0200;

localparam [1:0]
	ST_SCAN = 2'd0,
	ST_CANDIDATE = 2'd1,
	ST_FLUSH = 2'd2,
	ST_LOAD = 2'd3;

reg [1:0] state;
reg [7:0] scan0;
reg [7:0] scan1;
reg [7:0] scan2;
reg [7:0] line_buf [0:255];
reg [7:0] buf_count;
reg [7:0] first_len;
reg [7:0] flush_idx;
reg [15:0] candidate_next;
reg [15:0] write_addr;
reg [15:0] record_base;
reg [15:0] record_next;
reg [7:0] next_low;
reg [7:0] record_pos;

always @(posedge CLK) begin
	reg [15:0] cand_next;
	reg [15:0] cand_line;
	reg [15:0] cand_len;
	reg [15:0] next_addr;

	RAM_WR <= 0;

	if (RESET) begin
		state <= ST_SCAN;
		RAM_ADDR <= 0;
		RAM_DATA <= 0;
		HEADER_FOUND <= 0;
		DONE <= 0;
		ERROR <= 0;
		END_ADDR <= 0;
		scan0 <= 0;
		scan1 <= 0;
		scan2 <= 0;
		buf_count <= 0;
		first_len <= 0;
		flush_idx <= 0;
		candidate_next <= 0;
		write_addr <= BASIC_START;
		record_base <= BASIC_START;
		record_next <= BASIC_START;
		next_low <= 0;
		record_pos <= 0;
	end else if (ENABLE & BYTE_VALID & !DONE & !ERROR) begin
		case (state)
			ST_SCAN: begin
				cand_next = {scan1, scan0};
				cand_line = {BYTE, scan2};
				cand_len = cand_next - BASIC_START;
				if (cand_next > (BASIC_START + 16'd4) && cand_next < RAM_TOP_EXCLUSIVE &&
				    cand_len <= 16'd255 && cand_line > 0 && cand_line < 16'd10000) begin
					line_buf[0] <= scan0;
					line_buf[1] <= scan1;
					line_buf[2] <= scan2;
					line_buf[3] <= BYTE;
					buf_count <= 4;
					first_len <= cand_len[7:0];
					candidate_next <= cand_next;
					state <= ST_CANDIDATE;
				end
				scan0 <= scan1;
				scan1 <= scan2;
				scan2 <= BYTE;
			end

			ST_CANDIDATE: begin
				line_buf[buf_count] <= BYTE;
				if (buf_count == first_len - 1'd1) begin
					if (BYTE == 8'h00) begin
						HEADER_FOUND <= 1;
						flush_idx <= 0;
						state <= ST_FLUSH;
					end else begin
						state <= ST_SCAN;
					end
				end else begin
					buf_count <= buf_count + 1'd1;
				end
			end

			ST_FLUSH: begin
				RAM_ADDR <= BASIC_START + flush_idx;
				RAM_DATA <= line_buf[flush_idx];
				RAM_WR <= 1;
				if (flush_idx == first_len - 1'd1) begin
					write_addr <= candidate_next;
					record_base <= candidate_next;
					record_pos <= 0;
					state <= ST_LOAD;
				end else begin
					flush_idx <= flush_idx + 1'd1;
				end
			end

			ST_LOAD: begin
				RAM_ADDR <= write_addr;
				RAM_DATA <= BYTE;
				RAM_WR <= write_addr < RAM_TOP_EXCLUSIVE;

				if (record_pos == 0) begin
					next_low <= BYTE;
					record_pos <= 1;
				end else if (record_pos == 1) begin
					next_addr = {BYTE, next_low};
					if (next_addr == 0) begin
						DONE <= 1;
						END_ADDR <= write_addr;
					end else if (next_addr <= record_base || next_addr >= RAM_TOP_EXCLUSIVE ||
					             (next_addr - record_base) > 16'd255) begin
						ERROR <= 1;
					end else begin
						record_next <= next_addr;
						record_pos <= 2;
					end
				end else if ((write_addr + 1'd1) == record_next) begin
					if (BYTE != 8'h00)
						ERROR <= 1;
					record_base <= record_next;
					record_pos <= 0;
				end else begin
					record_pos <= record_pos + 1'd1;
				end

				write_addr <= write_addr + 1'd1;
			end

			default: ;
		endcase
	end
end

endmodule

module sorcerer_tape_parser
(
	input        CLK,
	input        RESET,
	input        ENABLE,
	input        BYTE_VALID,
	input  [7:0] BYTE,
	output reg        RAM_WR,
	output reg [15:0] RAM_ADDR,
	output reg  [7:0] RAM_DATA,
	output reg        HEADER_FOUND,
	output reg        DONE,
	output reg        ERROR,
	output reg [15:0] RUN_ADDR
);

localparam RAM_TOP_EXCLUSIVE = 16'hE000;

reg  [6:0] header_pos;
reg [15:0] tape_length;
reg [15:0] tape_load_addr;
reg [15:0] tape_data_count;
reg  [7:0] tape_block_pos;
reg  [7:0] tape_checksum;
reg        expect_checksum;
reg        seen_marker;

always @(posedge CLK) begin
	RAM_WR <= 0;

	if (RESET) begin
		RAM_ADDR <= 0;
		RAM_DATA <= 0;
		HEADER_FOUND <= 0;
		DONE <= 0;
		ERROR <= 0;
		RUN_ADDR <= 0;
		header_pos <= 0;
		tape_length <= 0;
		tape_load_addr <= 0;
		tape_data_count <= 0;
		tape_block_pos <= 0;
		tape_checksum <= 0;
		expect_checksum <= 0;
		seen_marker <= 0;
	end else if (ENABLE & BYTE_VALID & !DONE & !ERROR) begin
		if (!seen_marker) begin
			if (BYTE == 8'h01) begin
				HEADER_FOUND <= 0;
				seen_marker <= 1;
				header_pos <= 1;
				tape_length <= 0;
				tape_load_addr <= 0;
				tape_data_count <= 0;
				tape_block_pos <= 0;
				tape_checksum <= 0;
				expect_checksum <= 0;
			end
		end else if (!HEADER_FOUND) begin
			case (header_pos)
				7'd8:  tape_length[7:0] <= BYTE;
				7'd9:  tape_length[15:8] <= BYTE;
				7'd10: tape_load_addr[7:0] <= BYTE;
				7'd11: tape_load_addr[15:8] <= BYTE;
				default: ;
			endcase
			header_pos <= header_pos + 1'd1;
			if (header_pos == 7'd118) begin
				if (tape_length == 0 || tape_load_addr >= RAM_TOP_EXCLUSIVE ||
				    ({1'b0, tape_load_addr} + {1'b0, tape_length}) > {1'b0, RAM_TOP_EXCLUSIVE}) begin
					seen_marker <= 0;
					header_pos <= 0;
					tape_length <= 0;
					tape_load_addr <= 0;
					tape_data_count <= 0;
					tape_block_pos <= 0;
					tape_checksum <= 0;
					expect_checksum <= 0;
				end else begin
					HEADER_FOUND <= 1;
					RUN_ADDR <= tape_load_addr;
				end
			end
		end else if (expect_checksum) begin
			if (((tape_checksum + BYTE) & 8'hFF) != 8'h00)
				ERROR <= 1;
			tape_checksum <= 0;
			expect_checksum <= 0;
			if (tape_data_count == tape_length)
				DONE <= 1;
		end else if (tape_data_count != tape_length) begin
			RAM_ADDR <= tape_load_addr + tape_data_count;
			RAM_DATA <= BYTE;
			RAM_WR <= 1;
			tape_checksum <= tape_checksum + BYTE;
			tape_data_count <= tape_data_count + 1'd1;
			if (tape_block_pos == 8'hFF || tape_data_count == tape_length - 1'd1) begin
				tape_block_pos <= 0;
				expect_checksum <= 1;
			end else begin
				tape_block_pos <= tape_block_pos + 1'd1;
			end
		end
	end
end

endmodule
