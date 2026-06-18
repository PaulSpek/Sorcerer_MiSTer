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
	"O[8],WAV polarity,Normal,Inverted;",
	"O[9],WAV baud,300,1200;",
	"-;",
	"F1,BIN,Load BIN;",
	"F2,WAV,Load WAV;",
	"-;",
	"P2,Test Page 2;",
	"P2-;",
	"P2-, -= Options in page 2 =-;",
	"P2-;",
	"P2S0,DSK;",
	"P2O[7:6],Option 2,1,2,3,4;",
	"-;",
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

localparam [1:0] IOCTL_ROM  = 2'd0;
localparam [1:0] IOCTL_WAV  = 2'd1;
localparam [1:0] IOCTL_PAC  = 2'd2;
localparam [1:0] IOCTL_TAPE = 2'd3;

wire wav_download = ioctl_download & (ioctl_index == IOCTL_WAV);
wire core_download = ioctl_download & (ioctl_index != IOCTL_WAV);

wire [21:0] gamma_bus;
wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),
	
	.ps2_key(ps2_key),
	
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
	.outclk_1(clk12),
);

wire reset = RESET | status[0] | buttons[1] | ~rom_loaded;

wire [1:0] col = status[4:3];

///// VIDEO ////
//
//

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire [7:0] video;
wire ce_pix;

reg [1:0] count = 2'b00; // 2-bit counter
always @(posedge clk_sys or posedge reset) begin
    if (reset) begin
        count   <= 2'b00;
        ce_pix <= 0;
    end else begin
        count <= count + 1;
        if (count == 2'b11) // Toggle clk_out every 4 cycles
            ce_pix <= ~ce_pix;
    end
end

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
wire        wav_uart_rx;
wire        wav_active;

always @(posedge clk12) begin
`ifdef USE_AUDIO_IN
	cass_in[0] <= AUDIO_IN;
`else
	cass_in[0] <= UART_RXD;
`endif
	cass_in[1] <= cass_in[0];
end

wav_cass_loader wav_cass_loader
(
	.CLK(clk_sys),
	.RESET(reset),
	.DL(wav_download),
	.DL_WE(ioctl_wr),
	.DL_DATA(ioctl_dout[7:0]),
	.INVERT(status[8]),
	.BAUD_1200(status[9]),
	.WAIT(ioctl_wait),
	.UART_RX(wav_uart_rx),
	.ACTIVE(wav_active)
);

`ifdef USE_EXPANSION
assign MOTOR_CTRL = cass_motor ? 1'b0 : 1'bZ;
assign UART_TXD = uart_tx;
assign UART_RTS = 1'b0;
assign EXP7 = 1'bZ;
`else
assign UART_TXD = uart_en ? uart_tx : ~cass_motor;
`endif

reg rom_loaded = 0;
always @(posedge clk_sys) begin
    reg core_downlD;
    core_downlD <= core_download;
    if (core_downlD & ~core_download) rom_loaded <= 1;
end

wire [16:0] ram_addr;
wire        ram_rd, ram_wr;
wire  [7:0] ram_dout, ram_din;

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
	.CASS_UART_RX(wav_uart_rx),
	.CASS_UART_EN(wav_active),
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

	.RAM_SIZE(2),
	.RAM_ADDR(ram_addr),
	.RAM_RD(ram_rd),
	.RAM_WR(ram_wr),
	.RAM_DOUT(ram_dout),
	.RAM_DIN(ram_din),

	.UART_RX(UART_RXD),
	.UART_TX(uart_tx),

	.DL(core_download),
	.DL_CLK(clk_sys),
	.DL_ADDR(ioctl_addr[15:0]),
	.DL_DATA(ioctl_dout),
	.DL_WE(ioctl_wr),
	.DL_ROM(ioctl_index == IOCTL_ROM),
	.DL_PAC(ioctl_index == IOCTL_PAC),
	.DL_TAPE(ioctl_index == IOCTL_TAPE),

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
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = ce_pix;

assign VGA_DE = ~(HBlank | VBlank);
assign VGA_HS = HSync;
assign VGA_VS = VSync;

assign VGA_R = video ? 6'h3F : 6'h00;
assign VGA_G = video ? 6'h3F : 6'h00;
assign VGA_B = video ? 6'h3F : 6'h00;

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

module wav_cass_loader
(
	input        CLK,
	input        RESET,
	input        DL,
	input        DL_WE,
	input  [7:0] DL_DATA,
	input        INVERT,
	input        BAUD_1200,
	output       WAIT,
	output reg   UART_RX,
	output       ACTIVE
);

localparam CLK_FREQ = 32'd48000000;

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
reg  [2:0] frame_pos;
reg  [2:0] frame_bytes;
reg [31:0] sample_acc;
reg  [7:0] edge_count;
reg  [4:0] pulse_count;
reg        pulse_kind;
reg        sample_ready;
reg        invalid;
reg        sample_level;
reg        have_edge;

wire starting = DL & ~dl_d;
wire stopping = ~DL & dl_d;
wire in_data_sample_start = state == ST_DATA && frame_pos == 0;
wire accept = DL_WE & ~(in_data_sample_start & ~sample_ready);
wire [31:0] sample_rate_safe = sample_rate ? sample_rate : 32'd44100;

assign WAIT = DL & in_data_sample_start & ~sample_ready;
assign ACTIVE = DL & ~invalid;

always @(posedge CLK) begin
	dl_d <= DL;

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
		bits_per_sample <= 8;
		frame_pos <= 0;
		frame_bytes <= 1;
		sample_acc <= 0;
		edge_count <= 0;
		pulse_count <= 0;
		pulse_kind <= 0;
		sample_ready <= 1;
		invalid <= 0;
		sample_level <= 0;
		have_edge <= 0;
		UART_RX <= 1;
	end else if (stopping) begin
		state <= ST_DONE;
		sample_ready <= 0;
	end else if (DL) begin
		if (state == ST_DATA && ~sample_ready) begin
			if (sample_acc >= (CLK_FREQ - sample_rate_safe)) begin
				sample_acc <= sample_acc + sample_rate_safe - CLK_FREQ;
				sample_ready <= 1;
			end else begin
				sample_acc <= sample_acc + sample_rate_safe;
			end
		end

		if (accept) begin
			case (state)
				ST_HEADER: begin
					case (header_pos)
						0: if (DL_DATA != "R") invalid <= 1;
						1: if (DL_DATA != "I") invalid <= 1;
						2: if (DL_DATA != "F") invalid <= 1;
						3: if (DL_DATA != "F") invalid <= 1;
						8: if (DL_DATA != "W") invalid <= 1;
						9: if (DL_DATA != "A") invalid <= 1;
						10: if (DL_DATA != "V") invalid <= 1;
						11: if (DL_DATA != "E") invalid <= 1;
						default: ;
					endcase

					if (header_pos == 11) begin
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
					if (chunk_pos == 3) begin
						state <= ST_CHUNK_SIZE;
						chunk_pos <= 0;
						chunk_size <= 0;
					end else begin
						chunk_pos <= chunk_pos + 1'd1;
					end
				end

				ST_CHUNK_SIZE: begin
					chunk_size <= chunk_size | ({24'd0, DL_DATA} << {chunk_pos, 3'b000});
					if (chunk_pos == 3) begin
						chunk_left <= chunk_size | ({24'd0, DL_DATA} << 24);
						chunk_pos <= 0;

						if (chunk_id == "fmt ") begin
							state <= ST_FMT;
							fmt_pos <= 0;
						end else if (chunk_id == "data") begin
							state <= ST_DATA;
							frame_pos <= 0;
							sample_acc <= 0;
							edge_count <= 0;
							pulse_count <= 0;
							pulse_kind <= 0;
							sample_ready <= 1;
							frame_bytes <= (bits_per_sample == 16) ? (channels > 1 ? 3'd4 : 3'd2) :
							               (channels > 1 ? 3'd2 : 3'd1);
							if (audio_format != 1) invalid <= 1;
							if (bits_per_sample != 8 && bits_per_sample != 16) invalid <= 1;
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
					reg new_level;
					reg [7:0] edge_threshold;
					reg is_short;
					reg [4:0] next_pulse_count;
					reg [4:0] pulse_target;

					if (frame_pos == 0) sample_ready <= 0;

					new_level = sample_level;
					if (bits_per_sample == 8) begin
						if (frame_pos == 0) new_level = DL_DATA[7] ^ INVERT;
					end else begin
						if (frame_pos == 1) new_level = DL_DATA[7] ^ INVERT;
					end

					if (frame_pos == frame_bytes - 1'd1) begin
						edge_threshold = BAUD_1200 ? 8'd28 : 8'd14;

						if (new_level != sample_level) begin
							if (have_edge) begin
								is_short = edge_count <= edge_threshold;
								pulse_target = BAUD_1200 ? (is_short ? 5'd2 : 5'd1) : (is_short ? 5'd16 : 5'd8);
								next_pulse_count = (is_short == pulse_kind) ? pulse_count + 1'd1 : 5'd1;

								if (next_pulse_count >= pulse_target) begin
									UART_RX <= is_short;
									pulse_count <= 0;
								end else begin
									pulse_count <= next_pulse_count;
								end
								pulse_kind <= is_short;
							end
							edge_count <= 0;
							have_edge <= 1;
						end else if (edge_count != 8'hFF) begin
							edge_count <= edge_count + 1'd1;
						end
						sample_level <= new_level;
					end

					if (frame_pos == frame_bytes - 1'd1)
						frame_pos <= 0;
					else
						frame_pos <= frame_pos + 1'd1;

					if (chunk_left == 1) begin
						state <= ST_DONE;
						sample_ready <= 0;
					end
					chunk_left <= chunk_left - 1'd1;
				end

				default: ;
			endcase
		end
	end
end

endmodule
