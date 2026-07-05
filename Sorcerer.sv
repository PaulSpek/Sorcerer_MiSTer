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

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"Sorcerer;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[2],TV Mode,NTSC,PAL;",
	"O[4:3],Noise,White,Red,Green,Blue;",
	"-;",
	"F1,BIN,Load BIN;",
	"F2,BIN,Load PAC;",
	"F3,DAT,Load DiskBoot;",
	"D0S0,DSK,Mount disk A;",
	"D0S1,DSK,Mount disk B;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;", // [optional] config version 0-99. 
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			  // so all options will get default values on first start.
	"V,v",`BUILD_DATE 
};


wire ioctl_download;
wire [15:0] ioctl_addr;
wire ioctl_wr;
wire [1:0] ioctl_index;
wire [15:0] ioctl_dout;
wire ioctl_wait;
wire quick_clear_busy;
wire diskboot_ready;

wire [1:0] img_mounted;
wire       img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba[2];
wire [5:0]  sd_blk_cnt[2];
wire [1:0]  sd_rd;
wire [1:0]  sd_wr;
wire [1:0]  sd_ack;
wire [13:0] sd_buff_addr;
wire [7:0]  sd_buff_dout;
wire [7:0]  sd_buff_din[2];
wire        sd_buff_wr;

localparam [1:0] IOCTL_ROM   = 2'd0;
localparam [1:0] IOCTL_QUICK = 2'd1;
localparam [1:0] IOCTL_PAC   = 2'd2;
localparam [1:0] IOCTL_DISKBOOT = 2'd3;

wire [21:0] gamma_bus;
wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

assign ioctl_wait = ioctl_download && (ioctl_index == IOCTL_QUICK) && quick_clear_busy;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(2)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({14'd0, 1'b1, ~diskboot_ready}),
	
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
        if (ioctl_index == IOCTL_PAC) pac_reset_cnt <= 4'hF;
    end else if (pac_reset_cnt) begin
        pac_reset_cnt <= pac_reset_cnt - 1'd1;
    end
end

wire [16:0] ram_addr;
wire        ram_rd, ram_wr;
wire  [7:0] ram_dout, ram_din;

wire        disk_req;
wire        disk_ack;
wire        disk_wait;
wire        disk_drive;
wire  [6:0] disk_track;
wire  [3:0] disk_sector;
wire  [8:0] disk_buf_addr;
wire  [7:0] disk_buf_dout;
reg   [1:0] disk_mounted = 0;
reg   [7:0] disk_buf[1024];
reg   [8:0] disk_base = 0;
reg         disk_ack_tgl = 0;
reg         disk_busy = 0;
reg         disk_rd = 0;
reg         disk_start = 0;
reg   [1:0] disk_gap = 0;
reg         disk_hps_ack_seen = 0;
reg         disk_data_ready = 0;
reg         disk_need_second_block = 0;
reg         disk_second_block = 0;
reg         disk_wait_ack_clear = 0;
reg         disk_wait_idle = 0;
reg         disk_req_meta = 0;
reg         disk_req_sync = 0;
reg         disk_req_last = 0;
reg         disk_req_pending = 0;
reg         disk_active_drive = 0;
reg  [31:0] disk_offset = 0;
reg  [31:0] disk_lba = 0;
wire  [9:0] disk_buf_rd_addr = {1'b0, disk_base} + {1'b0, disk_buf_addr};
wire  [9:0] disk_buf_end_addr = {1'b0, disk_base} + 10'd269;
wire  [9:0] disk_buf_wr_addr = {disk_second_block, sd_buff_addr[8:0]};
wire  [8:0] disk_target_addr = (disk_need_second_block && !disk_second_block) ? 9'h1FF : disk_buf_end_addr[8:0];

assign sd_wr = 2'b00;
assign sd_buff_din[0] = 8'hFF;
assign sd_buff_din[1] = 8'hFF;
assign sd_lba[0] = disk_lba;
assign sd_lba[1] = disk_lba;
assign sd_blk_cnt[0] = 6'd0;
assign sd_blk_cnt[1] = 6'd0;
assign sd_rd = disk_rd ? (disk_active_drive ? 2'b10 : 2'b01) : 2'b00;
assign disk_ack = disk_ack_tgl;
assign disk_buf_dout = disk_buf[disk_buf_rd_addr];

always @(posedge clk_sys) begin
	reg [17:0] sector_linear;
	reg [31:0] sector_offset;
	reg  [9:0] sector_end_addr;

	disk_req_meta <= disk_req;
	disk_req_sync <= disk_req_meta;
	disk_req_last <= disk_req_sync;
	if (disk_gap != 0) disk_gap <= disk_gap - 1'd1;
	if (disk_req_sync ^ disk_req_last) disk_req_pending <= 1;

	if (img_mounted[0]) disk_mounted[0] <= 1;
	if (img_mounted[1]) disk_mounted[1] <= 1;

	if (sd_buff_wr) begin
		disk_buf[disk_buf_wr_addr] <= sd_buff_dout;
		if (disk_busy && (sd_buff_addr[8:0] == disk_target_addr))
			disk_data_ready <= 1;
	end

	if (disk_start) begin
		disk_start <= 0;
		disk_rd <= 1;
	end

	if (disk_wait_ack_clear && !sd_ack[disk_active_drive]) begin
		disk_wait_ack_clear <= 0;
		disk_start <= 1;
	end

	if (disk_wait_idle && !sd_ack[disk_active_drive]) begin
		disk_wait_idle <= 0;
		disk_gap <= 2'd3;
	end

	if (~disk_busy && ~disk_start && !disk_wait_idle && (disk_gap == 0) && disk_req_pending && !sd_ack[disk_drive]) begin
		disk_req_pending <= 0;
		disk_active_drive <= disk_drive;
		sector_linear = ({11'd0, disk_track} << 4) + {14'd0, disk_sector};
		sector_offset = sector_linear * 18'd270;
		sector_end_addr = {1'b0, sector_offset[8:0]} + 10'd269;
		disk_offset <= sector_offset;
		disk_lba <= sector_offset[31:9];
		disk_base <= sector_offset[8:0];
		disk_need_second_block <= (sector_end_addr > 10'd511);
		disk_second_block <= 0;
		disk_wait_ack_clear <= 0;
		disk_busy <= 1;
		disk_hps_ack_seen <= 0;
		disk_data_ready <= 0;
		disk_start <= 1;
	end else if (disk_busy && sd_ack[disk_active_drive]) begin
		disk_rd <= 0;
		disk_hps_ack_seen <= 1;
	end else if (disk_busy && disk_hps_ack_seen && disk_data_ready) begin
		if (disk_need_second_block && !disk_second_block) begin
			disk_lba <= disk_lba + 1'd1;
			disk_second_block <= 1;
			disk_wait_ack_clear <= 1;
			disk_hps_ack_seen <= 0;
			disk_data_ready <= 0;
		end else begin
			disk_busy <= 0;
			disk_wait_idle <= 1;
			disk_ack_tgl <= ~disk_ack_tgl;
		end
	end

	if (!disk_busy) begin
		disk_hps_ack_seen <= 0;
		disk_wait_ack_clear <= 0;
	end
end

reg   [1:0] cass_in;
wire        cass_out;
wire        cass_motor;
wire        uart_tx;

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
	.PAL(1'b1),
	.ALTTIMINGS(1'b1),
	.TURBO(1'b1),

	.KEY_STROBE(key_strobe),
	.KEY_PRESSED(key_pressed),
	.KEY_EXTENDED(key_extended),
	.KEY_CODE(key_code),
	.UPCASE(upcase),

	.RAM_SIZE(3),
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
	.DL_ROM(ioctl_index == IOCTL_ROM),
	.DL_QUICK(ioctl_index == IOCTL_QUICK),
	.DL_PAC(ioctl_index == IOCTL_PAC),
	.DL_DISKBOOT(ioctl_index == IOCTL_DISKBOOT),
	.DL_CLEAR_BUSY(quick_clear_busy),
	.DISKBOOT_READY(diskboot_ready),

	.DISK_MOUNTED(disk_mounted),
	.DISK_REQ(disk_req),
	.DISK_ACK(disk_ack),
	.DISK_WAIT(disk_wait),
	.DISK_DRIVE(disk_drive),
	.DISK_TRACK(disk_track),
	.DISK_SECTOR(disk_sector),
	.DISK_BUF_ADDR(disk_buf_addr),
	.DISK_BUF_DOUT(disk_buf_dout),

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
