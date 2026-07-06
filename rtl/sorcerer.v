//============================================================================
// 
//  Exidy Sorcerer top level
//  Copyright (C) 2024 Gyorgy Szombathelyi
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

module sorcerer (
	input         CLK12,
	input         RESET,
	output        HSYNC,
	output        VSYNC,
	output reg    HBLANK,
	output        VBLANK,
	output        VIDEO,
	output reg [13:0] AUDIO,
	input         CASS_IN,
	output        CASS_OUT,
	output        CASS_CTRL,
	input         PAL,
	input         ALTTIMINGS,
	input         TURBO,

	input         KEY_STROBE,
	input         KEY_PRESSED,
	input         KEY_EXTENDED,
	input   [7:0] KEY_CODE, // PS2 keycode
	output        UPCASE,

	input   [1:0] RAM_SIZE,
	output [16:0] RAM_ADDR,
	output        RAM_RD,
	output        RAM_WR,
	input   [7:0] RAM_DOUT,
	output  [7:0] RAM_DIN,

	input         UART_RX,
	output        UART_TX,

	// DMA bus
	input         DL,
	input         DL_WAIT,
	input         DL_CLK,
	input  [15:0] DL_ADDR,
	input   [7:0] DL_DATA,
	input         DL_WE,
	input         DL_ROM,
	input         DL_QUICK,
	input         DL_PAC,
	input         DL_DISKBOOT,
	output        DL_CLEAR_BUSY,
	output        DISKBOOT_READY,
	input         UNL_PAC,
	input         EXT_UART_RX_ACTIVE,
	input         EXT_UART_RX_BIT,
	input         EXT_UART_HIGH_BAUD,

	input   [1:0] DISK_MOUNTED,
	output reg    DISK_REQ,
	input         DISK_ACK,
	output        DISK_WAIT,
	output        DISK_DRIVE,
	output  [6:0] DISK_TRACK,
	output  [3:0] DISK_SECTOR,
	output  [8:0] DISK_BUF_ADDR,
	input   [7:0] DISK_BUF_DOUT,

	output        LED
);

// clock enables
reg cen6, cen2, cen4;
reg   [2:0] cnt;
always @(posedge CLK12) begin
	cen6 <= ~cen6;
	cnt <= cnt + 1'd1;
	if (cnt == 5) cnt <= 0;
	cen2 <= cnt == 0;
	cen4 <= cnt == 0 || cnt == 3;
end

// video circuit
reg   [8:0] hcnt; // 3a-4a-5a
reg   [8:0] vcnt; // 3b-4b-1b

reg   [7:0] rom_2b[32];
reg   [7:0] rom_2b_q;
reg   [7:0] charrom[1024];
reg   [7:0] charrom_q;
reg   [7:0] charram[1024];
reg   [7:0] charram_q;

always @(posedge DL_CLK) begin
	if (DL_WE & DL_ROM & DL_ADDR[15:12] == 1) begin
		if (DL_ADDR[11:0] < 1024) charrom[DL_ADDR[9:0]] <= DL_DATA;
		else rom_2b[DL_ADDR[4:0]] <= DL_DATA;
	end
end

reg         vsync, hblank;
reg         ihb, ihb_r;

assign      HSYNC = ~(~hcnt[8] | ~hcnt[5] | hcnt[6]);
assign      VSYNC = vsync;

assign      VBLANK = vcnt[8];

wire        buffload = &hcnt[1:0];

always @(posedge CLK12) begin
	if (cen6) begin
		hcnt <= hcnt + 1'd1;
		if (&hcnt[7:0]) hcnt[7:0] <= {1'b0, ~hcnt[8], ~hcnt[8], 1'b0, ~hcnt[8], ~hcnt[8], 1'b0, ALTTIMINGS ? hblank : ihb};
		if (hcnt == 511) vsync <= ~|{~vcnt[8], vcnt[4], ~vcnt[3]};
		if (&hcnt[8:0]) begin
			vcnt <= vcnt + 1'd1;
			if (&vcnt[7:0]) vcnt[7:0] <= {~vcnt[8], PAL ? 1'b0 : ~vcnt[8], ~vcnt[8], PAL ? 1'b1 : vcnt[8], PAL ? 1'b0 : ~vcnt[8], PAL ? ~vcnt[8] : 1'b0, ~vcnt[8], ~vcnt[8]};
		end
		if (buffload) begin
			hblank <= hcnt[8];
			HBLANK <= hblank;
		end

		if (ihb_r) ihb <= 1;
		if (buffload) begin
			ihb <= hcnt[8];
			ihb_r <= 0;
		end
		if (acpu) begin
			ihb_r <= 1;
			ihb <= 1;
		end
	end
	if (~vcnt[5]) vsync <= 0;
end

wire [11:0] tb = acpu ? cpu_addr[11:0] : {dl[10], vcnt[7:3], hcnt[7:2]};
wire        quick_dl = DL_QUICK & DL;
wire        quick_mem_active;
reg   [7:0] vram[2048];
reg   [7:0] vram_dout;
reg  [10:3] dl_r;
wire [10:0] dl = acpu ? tb[9:0] : {dl_r, vcnt[2:0]};
reg   [7:0] quick_wr;
reg  [15:0] quick_addr;
reg   [7:0] quick_data;
wire        quick_vram_wr = quick_mem_active & (|quick_wr) & (quick_addr[15:11] == 5'b11110);

// VRAM test pattern
initial begin
	integer i;
	for (i=0;i<2048;i=i+1) begin
		vram[i] = i[7:0];
	end

	for (i=0;i<1024;i=i+1) begin
		charram[i] = 8'haa << i[0];
	end
end

reg  [7:0] char_shift; // 8d

always @(posedge CLK12) begin
	vram_dout <= vram[tb[10:0]];
	if (quick_vram_wr) vram[quick_addr[10:0]] <= quick_data;
	else if ((!cs1 | !cs2) & !write_n) vram[tb[10:0]] <= cpu_dout;
	charrom_q <= charrom[dl[9:0]];
	charram_q <= charram[dl[9:0]];
	if (!cs4 & !write_n) charram[dl[9:0]] <= cpu_dout;
	if (cen6 & buffload) dl_r[10:3] <= vram_dout; //5d
	if (cen6 & buffload & ~ihb & ~acpu)
		char_shift <= !cs3 ? charrom_q : charram_q;
	else
		char_shift <= {char_shift[6:0], 1'b0};
end

assign VIDEO = char_shift[7]; // 8d

// cpu
wire        int_n = 1;
wire        nmi_n = 1;
wire [15:0] cpu_addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        iorq_n;
wire        mreq_n;
wire        rfsh_n;
wire        rd_n;
wire        wr_n;
wire        m1_n;
wire        busak_n;
wire [211:0] cpu_reg;
reg  [211:0] cpu_dir;
reg          cpu_dirset;

T80s T80 (
	.RESET_n(~RESET),
	.CLK(CLK12),
	.CEN(TURBO ? cen4 : cen2),
	.WAIT_n(~(DL_WAIT | DISK_WAIT)),
	.INT_n(int_n),
	.NMI_n(nmi_n),
	.BUSRQ_n(1'b1),
	.BUSAK_n(busak_n),
	.M1_n(m1_n),
	.RFSH_n(rfsh_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_n),
	.WR_n(wr_n),
	.A(cpu_addr),
	.DI(cpu_din),
	.DO(cpu_dout),
	.REG(cpu_reg),
	.DIRSet(cpu_dirset),
	.DIR(cpu_dir)
);

wire        inta_n = m1_n | iorq_n;
wire        up8k = &{cpu_addr[15:13], rfsh_n};
wire        acpu = &{up8k, cpu_addr[12], ~mreq_n} /* synthesis keep */;
wire        write_n = acpu ? xwr : 1'b1;
localparam [15:0] RAM_TOP_EXCLUSIVE = 16'hBC00;

reg   [7:0] rom[4096];
reg   [7:0] rom_dout;
reg   [7:0] diskboot[1024];
reg   [7:0] diskboot_dout;
reg         diskboot_loaded = 0;
integer     diskboot_init_idx;

assign      DISKBOOT_READY = diskboot_loaded;

initial begin
	for (diskboot_init_idx = 0; diskboot_init_idx < 1024; diskboot_init_idx = diskboot_init_idx + 1)
		diskboot[diskboot_init_idx] = 8'hFF;
end

reg   [7:0] pac[8192];
reg   [7:0] pac_dout;

always @(posedge CLK12) begin : ROM
	rom_dout <= rom[cpu_addr[11:0]];
	diskboot_dout <= diskboot[cpu_addr[9:0]];
	pac_dout <= pac[cpu_addr[12:0]];
	rom_2b_q <= rom_2b[{~acpu, tb[11:10], rd_n, wr_n}];
end
wire        cs1 = rom_2b_q[0] /* synthesis noprune */;
wire        cs2 = rom_2b_q[1] /* synthesis noprune */;
wire        cs3 = rom_2b_q[2] /* synthesis noprune */;
wire        cs4 = rom_2b_q[3] /* synthesis noprune */;
wire        dir = rom_2b_q[4] /* synthesis noprune */;
wire        db1e = rom_2b_q[5] /* synthesis noprune */;
wire        db2e = rom_2b_q[6] /* synthesis noprune */;
wire        xwr = rom_2b_q[7];

always @(posedge DL_CLK) begin : ROM_DL
	if (DL_WE & DL_ROM & DL_ADDR[15:12] == 0) rom[DL_ADDR[11:0]] <= DL_DATA;
	if (DL_WE & DL_DISKBOOT & DL_ADDR[15:10] == 0) begin
		diskboot[DL_ADDR[9:0]] <= DL_DATA;
		if (DL_ADDR[9:0] == 10'd255) diskboot_loaded <= 1;
	end
end

reg         pac_loaded = 0;

always @(posedge DL_CLK) begin : PAC_DL
	if (DL_WE & DL_PAC) begin
		pac[DL_ADDR[12:0]] <= DL_DATA;
		pac_loaded <= 1;
	end
	if (UNL_PAC) pac_loaded <= 0;
end

reg         romen = 1;
always @(posedge CLK12) begin
	if (RESET)
		romen <= 1;
	else begin
		if (up8k & ~rd_n & ~mreq_n & ~cpu_addr[12] & ~cpu_addr[11]) romen <= 0;
	end
end

wire        romcs = romen | (up8k & ~cpu_addr[12]) /* synthesis keep */;
wire        diskbootsel = rfsh_n & ~mreq_n & (cpu_addr[15:10] == 6'b101111) & (cpu_addr[15:2] != 14'b10111110000000) & diskboot_loaded;
wire        ramsel = ((RAM_SIZE == 0) & ~|cpu_addr[14:13]) |
                     ((RAM_SIZE == 1) & ~cpu_addr[14]) |
                     ((RAM_SIZE == 2) & ~cpu_addr[15]) |
                     ((RAM_SIZE == 3) & (cpu_addr < RAM_TOP_EXCLUSIVE));
wire        ramen = rfsh_n & ~mreq_n & ramsel & ~romen /* synthesis keep */;
wire        pacsel = rfsh_n & ~mreq_n & cpu_addr[15:13] == 3'b110 & pac_loaded;

wire        ioen = ~iorq_n & &cpu_addr[7:2];
wire        fdc_sel = ~iorq_n & (cpu_addr[7:2] == 6'b001010); // 28-2B
wire        fdc_ctrl_sel = ~iorq_n & (cpu_addr[7:2] == 6'b001011); // 2C-2F
reg   [7:0] fdc_track = 0;
reg   [7:0] fdc_sector = 1;
reg   [7:0] fdc_data = 0;
reg   [7:0] fdc_ctrl = 0;
reg   [8:0] fdc_pos = 0;
reg         fdc_busy = 0;
reg         fdc_drq = 0;
reg         fdc_not_found = 0;
reg         fdc_read_pending = 0;
reg   [7:0] micro_status = 8'h08;
reg   [3:0] micro_sector = 4'h0;
reg   [3:0] micro_status_sector = 4'h0;
reg   [8:0] micro_pos = 9'h000;
reg         micro_pending = 0;
reg         micro_ready = 0;
reg         micro_inv = 0;
reg         micro_data_armed = 0;
reg         micro_status_wait_done = 0;
reg         micro_status_wait_active = 0;
reg   [7:0] micro_status0_latch = 8'h00;
reg         disk_drive = 0;
reg   [6:0] disk_track = 0;
reg   [3:0] disk_sector = 0;
reg         disk_req_drive = 0;
reg   [6:0] disk_req_track = 0;
reg   [3:0] disk_req_sector = 0;
reg         disk_ack_meta = 0;
reg         disk_ack_sync = 0;
reg         disk_ack_last = 0;
wire        fdc_drive = fdc_ctrl[3] ? 1'b1 : 1'b0;
wire        fdc_drive_selected = fdc_ctrl[2] | fdc_ctrl[3];
wire        fdc_ready = fdc_drive_selected & DISK_MOUNTED[fdc_drive];
wire  [7:0] fdc_status_read = {~fdc_ready, 1'b0, 1'b0, fdc_not_found, 2'b00, fdc_drq, fdc_busy};
wire        microsel = rfsh_n & ~mreq_n & (cpu_addr[15:2] == 14'b10111110000000); // BE00-BE03
wire        micro_data_port_read = microsel & ~rd_n & cpu_addr[1] & micro_ready;
wire        micro_data_wait = 1'b0;
wire        micro_data_read = micro_data_port_read;
wire        disk_req_active = micro_pending | fdc_read_pending;
wire        disk_wait_drive = disk_req_active ? disk_req_drive : disk_drive;
wire        micro_status_wait = micro_status_wait_active &
                                DISK_MOUNTED[disk_wait_drive] & !micro_status_wait_done;
assign      DISK_DRIVE = disk_req_active ? disk_req_drive : disk_drive;
assign      DISK_TRACK = disk_req_active ? disk_req_track : disk_track;
assign      DISK_SECTOR = disk_req_active ? disk_req_sector : disk_sector;
assign      DISK_BUF_ADDR = microsel ? micro_pos : fdc_pos;
assign      DISK_WAIT = micro_pending | fdc_read_pending |
                        micro_status_wait |
                        micro_data_wait;

wire  [7:0] io_in = ~rd_n & 
            (fdc_sel ? (cpu_addr[1:0] == 2'b00 ? fdc_status_read :
                        cpu_addr[1:0] == 2'b01 ? fdc_track :
                        cpu_addr[1:0] == 2'b10 ? fdc_sector :
                        (fdc_drq ? DISK_BUF_DOUT : fdc_data)) :
            cpu_addr[1:0] == 2'b10 ? {2'b11, vcnt[8], kbd_in} :
            uart_data_sel ? (tape_emu_ready ? tape_emu_dout : uart_dout) :
            uart_ctrl_sel ? (tape_emu_ready ? 8'h02 : uart_status) :
            8'hff);
wire  [3:0] micro_next_sector = micro_sector + 4'd3 + {3'b000, micro_inv};
wire  [3:0] micro_raw_sector = micro_next_sector;
wire        micro_status_read = microsel & ~rd_n & (cpu_addr[1:0] == 2'b00);
wire  [3:0] micro_status_out = micro_status_sector;
wire  [6:0] micro_step_track = cpu_dout[0] ? ((disk_track != 7'd76) ? (disk_track + 1'd1) : disk_track) :
                                             ((disk_track != 7'd0)  ? (disk_track - 1'd1) : disk_track);
wire  [7:0] micro_step_status = 8'hA0 | ((micro_step_track == 7'd0) ? 8'h08 : 8'h00);
wire  [7:0] micro_status0_next = (micro_status & 8'h80) | {4'h0, micro_next_sector};
wire  [7:0] micro_status1_base = micro_status | ((disk_track == 7'd0) ? 8'h08 : 8'h00);
wire  [7:0] micro_status1_value = micro_status1_base | {7'b0000000, disk_drive};
wire  [7:0] micro_status0_value = micro_status_wait_active ? micro_status0_latch :
                                  ((micro_status & 8'h80) | {4'h0, micro_status_out});
wire  [7:0] micro_in = cpu_addr[1] ? (micro_ready ? DISK_BUF_DOUT : 8'h00) :
                       cpu_addr[0] ? micro_status1_value :
                       micro_status0_value;

always @(posedge CLK12) begin
	reg fdc_rd_data;
	reg fdc_rd_data_d;
	reg fdc_wr;
	reg fdc_wr_d;
	reg fdc_ctrl_wr;
	reg fdc_ctrl_wr_d;
	reg micro_rd;
	reg micro_rd_d;
	reg micro_wr;
	reg micro_wr_d;

	disk_ack_meta <= DISK_ACK;
	disk_ack_sync <= disk_ack_meta;
	disk_ack_last <= disk_ack_sync;

	fdc_rd_data <= fdc_sel & ~rd_n & (cpu_addr[1:0] == 2'b11);
	fdc_rd_data_d <= fdc_rd_data;
	fdc_wr <= fdc_sel & ~wr_n;
	fdc_wr_d <= fdc_wr;
	fdc_ctrl_wr <= fdc_ctrl_sel & ~wr_n;
	fdc_ctrl_wr_d <= fdc_ctrl_wr;
	micro_rd <= microsel & ~rd_n;
	micro_rd_d <= micro_rd;
	micro_wr <= microsel & ~wr_n;
	micro_wr_d <= micro_wr;

	if (RESET) begin
		fdc_track <= 0;
		fdc_sector <= 1;
		fdc_data <= 0;
		fdc_ctrl <= 0;
		fdc_pos <= 0;
		fdc_busy <= 0;
		fdc_drq <= 0;
		fdc_not_found <= 0;
		fdc_read_pending <= 0;
		micro_status <= 8'h08;
		micro_sector <= 0;
		micro_status_sector <= 0;
		micro_pos <= 0;
		micro_pending <= 0;
		micro_ready <= 0;
		micro_inv <= 0;
		micro_data_armed <= 0;
		micro_status_wait_done <= 0;
		micro_status_wait_active <= 0;
		micro_status0_latch <= 0;
		disk_drive <= 0;
		disk_track <= 0;
		disk_sector <= 0;
		disk_req_drive <= 0;
		disk_req_track <= 0;
		disk_req_sector <= 0;
		DISK_REQ <= 0;
	end else begin
		if (micro_data_read && !micro_data_armed) begin
			micro_data_armed <= 1;
		end
		if (micro_data_armed && !micro_data_read) begin
			micro_data_armed <= 0;
			if (micro_pos != 9'd269) begin
				micro_pos <= micro_pos + 1'd1;
			end else begin
				micro_ready <= 0;
			end
		end

		if ((disk_ack_sync ^ disk_ack_last) & fdc_read_pending) begin
			fdc_pos <= 0;
			fdc_busy <= 1;
			fdc_drq <= 1;
			fdc_not_found <= 0;
			fdc_read_pending <= 0;
		end
		if ((disk_ack_sync ^ disk_ack_last) & micro_pending) begin
			micro_pos <= 0;
			micro_pending <= 0;
			micro_ready <= 1;
			micro_status_wait_done <= 1;
			micro_status <= 8'hA0 | (disk_req_track == 0 ? 8'h08 : 8'h00);
		end

		if (!micro_status_read) begin
			micro_status_wait_done <= 0;
			micro_status_wait_active <= 0;
		end

		if (micro_rd & ~micro_rd_d) begin
			case (cpu_addr[1:0])
				2'b00: begin
					micro_status0_latch <= micro_status0_next;
					micro_status_wait_active <= 1;
					micro_sector <= micro_next_sector;
					micro_status_sector <= micro_next_sector;
					micro_inv <= ~micro_inv;
					micro_pos <= 0;
					micro_ready <= 0;
					fdc_sector <= {4'h0, micro_next_sector};
					fdc_track <= {1'b0, disk_track};
					if (DISK_MOUNTED[disk_drive]) begin
						disk_sector <= micro_raw_sector;
						disk_req_drive <= disk_drive;
						disk_req_track <= disk_track;
						disk_req_sector <= micro_raw_sector;
						micro_pending <= 1;
						DISK_REQ <= ~DISK_REQ;
					end else begin
						micro_status <= 8'h00 | (disk_track == 0 ? 8'h08 : 8'h00);
					end
				end
				default: ;
			endcase
		end

		if (micro_wr & ~micro_wr_d) begin
			if (!cpu_addr[1]) begin
				case (cpu_dout[7:5])
					3'd1: begin
						disk_drive <= cpu_dout[0];
						micro_status <= 8'hA0 | (disk_track == 0 ? 8'h08 : 8'h00);
					end
					3'd3: begin
						if (cpu_dout[0]) begin
							if (disk_track != 7'd76) disk_track <= disk_track + 1'd1;
						end else begin
							if (disk_track != 0) disk_track <= disk_track - 1'd1;
						end
						micro_status <= micro_step_status;
					end
					3'd5: begin
						// Command group 5 resets the sector phase and byte position.
						// This matches the local DiskBoot/Micropolis simulator.
						micro_sector <= 4'h0;
						micro_status_sector <= 4'h0;
						micro_pos <= 9'h000;
						micro_status <= 8'hA0 | (disk_track == 0 ? 8'h08 : 8'h00);
					end
					default: begin
						micro_status <= 8'hA0 | (disk_track == 0 ? 8'h08 : 8'h00);
					end
				endcase
			end
		end

		if (fdc_rd_data & ~fdc_rd_data_d & fdc_drq) begin
			if (fdc_pos == 9'd269) begin
				fdc_pos <= 0;
				fdc_busy <= 0;
				fdc_drq <= 0;
			end else begin
				fdc_pos <= fdc_pos + 1'd1;
			end
		end

		if (fdc_ctrl_wr & ~fdc_ctrl_wr_d) begin
			fdc_ctrl <= cpu_dout;
		end

		if (fdc_wr & ~fdc_wr_d) begin
			case (cpu_addr[1:0])
				2'b00: begin
					fdc_not_found <= 0;
					casez (cpu_dout)
						8'b0000_????: begin // restore
							fdc_track <= 0;
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
						end

						8'b0001_????: begin // seek
							fdc_track <= fdc_data;
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
						end

						8'b001?_????: begin // step
							fdc_busy <= 0;
							fdc_drq <= 0;
						end

						8'b010?_????: begin // step in
							if (fdc_track != 8'd76) fdc_track <= fdc_track + 1'd1;
							fdc_busy <= 0;
							fdc_drq <= 0;
						end

						8'b011?_????: begin // step out
							if (fdc_track != 0) fdc_track <= fdc_track - 1'd1;
							fdc_busy <= 0;
							fdc_drq <= 0;
						end

						8'b100?_????: begin // read sector
							fdc_pos <= 0;
							fdc_drq <= 0;
							if (fdc_ready && fdc_track < 8'd77 && fdc_sector >= 8'd1 && fdc_sector <= 8'd16) begin
								disk_drive <= fdc_drive;
								disk_track <= fdc_track[6:0];
								disk_sector <= fdc_sector[3:0] - 1'd1;
								disk_req_drive <= fdc_drive;
								disk_req_track <= fdc_track[6:0];
								disk_req_sector <= fdc_sector[3:0] - 1'd1;
								fdc_busy <= 1;
								fdc_read_pending <= 1;
								DISK_REQ <= ~DISK_REQ;
							end else begin
								fdc_busy <= 0;
								fdc_read_pending <= 0;
								fdc_not_found <= 1;
							end
						end

						8'b101?_????: begin // write sector is not implemented yet
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
							fdc_not_found <= 1;
						end

						8'b1101_????: begin // force interrupt
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
							fdc_not_found <= 0;
						end

						default: begin
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
						end
					endcase
				end

				2'b01: begin fdc_track <= cpu_dout; end
				2'b10: begin fdc_sector <= cpu_dout; end
				2'b11: begin fdc_data <= cpu_dout; end
			endcase
		end
	end
end

assign      cpu_din = romcs ? rom_dout :
                      diskbootsel ? diskboot_dout :
                      microsel ? micro_in :
                      ramen ? RAM_DOUT :
                      pacsel ? pac_dout:
                      ((~cs1 | ~cs2) & ~db1e) ? vram_dout :
                      (~cs3 & ~db1e) ? charrom_q :
                      (~cs4 & ~db1e) ? charram_q :
                      (ioen | fdc_sel) ? io_in : 8'hff;

wire        tape_dl = 1'b0;
reg   [7:0] tape_wr;
always @(posedge DL_CLK) begin
	if (DL_WE) tape_wr <= 8'hFF;
	else tape_wr <= {1'b0, tape_wr[7:1]};
end

reg  [15:0] quick_exec;
reg  [15:0] quick_pc;
reg  [15:0] quick_end;
reg  [15:0] quick_stub_addr;
reg         quick_ready;
reg         quick_error;
reg         quick_autorun;
reg         quick_basic;
reg         quick_run;
reg         quick_clear_busy;
reg  [15:0] quick_clear_addr;
reg   [3:0] quick_patch_idx;
wire        quick_patch_busy = quick_ready & ~quick_error & (quick_patch_idx < 4'd15);

assign quick_mem_active = quick_dl | quick_clear_busy | quick_patch_busy;
assign DL_CLEAR_BUSY = quick_clear_busy | quick_patch_busy;

always @(posedge DL_CLK) begin : quickload
	localparam [2:0]
		Q_HEADER  = 3'd0,
		Q_NAME    = 3'd1,
		Q_EXEC_LO = 3'd2,
		Q_EXEC_HI = 3'd3,
		Q_LOAD_LO = 3'd4,
		Q_LOAD_HI = 3'd5,
		Q_END_LO  = 3'd6,
		Q_PAYLOAD = 3'd7;

	reg        quick_dl_d;
	reg  [2:0] state;
	reg  [2:0] header_cnt;
	reg [15:0] load_addr;
	reg [15:0] end_addr;
	reg [15:0] payload_left;
	reg [15:0] payload_addr;
	reg [15:0] final_end;
	reg        is_basic_load;
	reg        is_autorun_load;
	quick_dl_d <= quick_dl;
	quick_wr <= {1'b0, quick_wr[7:1]};

	if (RESET | (quick_dl & ~quick_dl_d)) begin
		state <= Q_HEADER;
		header_cnt <= 0;
		load_addr <= 0;
		end_addr <= 0;
		payload_left <= 0;
		payload_addr <= 0;
		quick_end <= 0;
		quick_stub_addr <= 0;
		quick_addr <= 0;
		quick_data <= 0;
		quick_exec <= 0;
		quick_pc <= 0;
		quick_ready <= 0;
		quick_error <= 0;
		quick_autorun <= 0;
		quick_basic <= 0;
		quick_run <= 0;
		quick_clear_busy <= 0;
		quick_clear_addr <= 0;
		quick_wr <= 0;
		quick_patch_idx <= 4'hF;
	end else if (quick_clear_busy & quick_basic) begin
		quick_clear_busy <= 0;
	end else if (quick_clear_busy) begin
		quick_addr <= quick_clear_addr;
		quick_data <= 8'h00;
		quick_wr <= 8'hFF;
		if (quick_clear_addr == 16'hBB6F) begin
			quick_clear_busy <= 0;
		end else begin
			quick_clear_addr <= quick_clear_addr + 1'd1;
		end
	end else if (quick_dl & DL_WE & ~quick_error) begin
		case (state)
			Q_HEADER: begin
				if (header_cnt == 6)
					state <= Q_NAME;
				else
					header_cnt <= header_cnt + 1'd1;
			end

			Q_NAME: begin
				if (DL_DATA == 8'h1A)
					state <= Q_EXEC_LO;
			end

			Q_EXEC_LO: begin
				quick_exec[7:0] <= DL_DATA;
				state <= Q_EXEC_HI;
			end

			Q_EXEC_HI: begin
				quick_exec[15:8] <= DL_DATA;
				state <= Q_LOAD_LO;
			end

			Q_LOAD_LO: begin
				load_addr[7:0] <= DL_DATA;
				state <= Q_LOAD_HI;
			end

			Q_LOAD_HI: begin
				load_addr[15:8] <= DL_DATA;
				state <= Q_END_LO;
			end

			Q_END_LO: begin
				end_addr[7:0] <= DL_DATA;
				state <= Q_PAYLOAD;
			end

			Q_PAYLOAD: begin
				if (payload_left == 0) begin
					end_addr[15:8] <= DL_DATA;
					final_end = {DL_DATA, end_addr[7:0]};
					is_basic_load = (load_addr == 16'h01D5) || (quick_exec == 16'hC858);
					is_autorun_load = (quick_exec >= load_addr) && (quick_exec <= final_end) && (quick_exec < RAM_TOP_EXCLUSIVE) && !is_basic_load;
					if (final_end < load_addr || load_addr >= RAM_TOP_EXCLUSIVE || final_end >= RAM_TOP_EXCLUSIVE ||
					    (is_basic_load && ((final_end + 16'd11) >= RAM_TOP_EXCLUSIVE))) begin
						quick_error <= 1;
					end else begin
						payload_addr <= load_addr;
						payload_left <= final_end - load_addr + 1'd1;
						quick_end <= final_end;
						quick_stub_addr <= final_end + 16'd1;
						quick_basic <= is_basic_load;
						quick_autorun <= is_autorun_load;
						if (!is_basic_load) begin
							quick_clear_busy <= 1;
							quick_clear_addr <= 0;
						end
					end
				end else begin
					quick_addr <= payload_addr;
					quick_data <= DL_DATA;
					quick_wr <= 8'hFF;
					payload_addr <= payload_addr + 1'd1;
					payload_left <= payload_left - 1'd1;
					quick_ready <= 1;
					if (payload_left == 1) begin
						if (quick_basic)
							quick_patch_idx <= 0;
						else if (quick_autorun) begin
							quick_pc <= quick_exec;
							quick_run <= 1;
						end
					end
				end
			end

			default: ;
		endcase
	end else if (quick_patch_busy) begin
		case (quick_patch_idx)
			4'd0:  begin quick_addr <= quick_stub_addr + 16'd0;  quick_data <= 8'hCD; end // CALL C426
			4'd1:  begin quick_addr <= quick_stub_addr + 16'd1;  quick_data <= 8'h26; end
			4'd2:  begin quick_addr <= quick_stub_addr + 16'd2;  quick_data <= 8'hC4; end
			4'd3:  begin quick_addr <= quick_stub_addr + 16'd3;  quick_data <= 8'h21; end // LD HL,01D4
			4'd4:  begin quick_addr <= quick_stub_addr + 16'd4;  quick_data <= 8'hD4; end
			4'd5:  begin quick_addr <= quick_stub_addr + 16'd5;  quick_data <= 8'h01; end
			4'd6:  begin quick_addr <= quick_stub_addr + 16'd6;  quick_data <= 8'h36; end // LD (HL),00
			4'd7:  begin quick_addr <= quick_stub_addr + 16'd7;  quick_data <= 8'h00; end
			4'd8:  begin quick_addr <= quick_stub_addr + 16'd8;  quick_data <= 8'hC3; end // JP C3DD
			4'd9:  begin quick_addr <= quick_stub_addr + 16'd9;  quick_data <= 8'hDD; end
			4'd10: begin quick_addr <= quick_stub_addr + 16'd10; quick_data <= 8'hC3; end
			4'd11: begin quick_addr <= 16'h01B7; quick_data <= quick_end[7:0]; end
			4'd12: begin quick_addr <= 16'h01B8; quick_data <= quick_end[15:8]; end
			4'd13: begin quick_addr <= 16'h01D4; quick_data <= 8'h00; end
			default: ;
		endcase
		if (quick_patch_idx < 4'd14)
		quick_wr <= 8'hFF;
		quick_patch_idx <= quick_patch_idx + 1'd1;
		if (quick_patch_idx == 4'd14) begin
			quick_pc <= quick_stub_addr;
			quick_run <= 1;
		end
	end else if (~quick_dl) begin
		quick_clear_busy <= 0;
	end
end

always @(posedge CLK12) begin
	reg quick_run_meta;
	reg quick_run_sync;
	reg quick_run_d;

	quick_run_meta <= quick_run;
	quick_run_sync <= quick_run_meta;
	quick_run_d <= quick_run_sync;
	cpu_dirset <= 0;

	if (quick_run_sync & ~quick_run_d) begin
		cpu_dir <= cpu_reg;
		cpu_dir[79:64] <= quick_pc;
		cpu_dirset <= 1;
	end
end

wire        quick_ram_wr = quick_mem_active & (|quick_wr) & (quick_addr < RAM_TOP_EXCLUSIVE);

assign      RAM_ADDR = quick_mem_active ? {1'b0, quick_addr} :
                       tape_dl ? {1'b1, DL_ADDR[15:0]} :
                       rfsh_n ? {1'b0, cpu_addr[15:0]} : {1'b1, tape_emu_addr};
assign      RAM_RD = (quick_mem_active | tape_dl) ? 1'b0 : !rfsh_n | (ramen & ~rd_n);
assign      RAM_WR = quick_mem_active ? quick_ram_wr : tape_dl ? |tape_wr : ramen & ~wr_n;
assign      RAM_DIN = quick_mem_active ? quick_data : tape_dl ? DL_DATA : cpu_dout;

reg   [3:0] kbd_out;
reg         rs232_sel;
reg         baud_sel;
reg   [1:0] motor_ctrl;
wire  [4:0] kbd_in = key_matrix[kbd_out];
wire  [7:0] uart_dout;
wire  [7:0] uart_status;
wire        uart_data_sel = ioen & cpu_addr[1:0] == 2'b00;
wire        uart_ctrl_sel = ioen & cpu_addr[1:0] == 2'b01;
reg         cen_4800, cen_19200, cen_38400;
reg         uart_rx_cen, uart_tx_cen;
reg         ext_uart_active_meta, ext_uart_active_sync;
reg         ext_uart_bit_meta, ext_uart_bit_sync;
reg         ext_uart_baud_meta, ext_uart_baud_sync;

reg   [5:0] div55_cnt;
reg   [2:0] div8_cnt;
always @(posedge CLK12) begin
	cen_38400 <= 0;
	if (cen2) begin
		div55_cnt <= div55_cnt + 1'd1;
		if (div55_cnt == 54) begin
			div55_cnt <= 0;
			cen_38400 <= 1;
		end
	end
	if (cen_38400) 
		div8_cnt <= div8_cnt + 1'd1;

	cen_19200 <= cen_38400 & div8_cnt[0];
	cen_4800 <= cen_38400 & ~|div8_cnt;

end

always @(posedge CLK12) begin
	ext_uart_active_meta <= EXT_UART_RX_ACTIVE;
	ext_uart_active_sync <= ext_uart_active_meta;
	ext_uart_bit_meta <= EXT_UART_RX_BIT;
	ext_uart_bit_sync <= ext_uart_bit_meta;
	ext_uart_baud_meta <= EXT_UART_HIGH_BAUD;
	ext_uart_baud_sync <= ext_uart_baud_meta;
end

always @(*) begin
	case (ext_uart_active_sync ? {1'b0, ext_uart_baud_sync} : {rs232_sel, baud_sel})
		3: uart_rx_cen = cen_19200;
		2: uart_rx_cen = cen_4800;
		1: uart_rx_cen = cen_19200; // casette read clock (1200 baud) - emulate PLL? - UART syncs to byte start anyway
		0: uart_rx_cen = cen_4800;  // casette read clock (300 baud) - emulate PLL?
		default: uart_rx_cen = 1;
	endcase

	uart_tx_cen = baud_sel ? cen_19200 : cen_4800;
end

wire        decode_cen = baud_sel ? cen_19200 : cen_38400;
reg   [2:0] decoder;
reg   [3:0] decoder_cnt;

always @(posedge CLK12) begin
	reg cass_in_d;
	cass_in_d <= CASS_IN;
	if (cass_in_d ^ CASS_IN) begin
		decoder[0] <= 1;
		decoder[1] <= decoder[0];
	end
	if (decode_cen) begin
		if (decoder[0]) 
			decoder_cnt <= decoder_cnt + 1'd1;
		else
			decoder_cnt <= 4;

		if (decoder_cnt == 4'he) begin
			decoder[0] <= 0;
			if (decoder[0]) decoder[2] <= decoder[1];
		end
		if (decoder_cnt == 4'hf)
			decoder_cnt <= 4;
	end
end

gen_uart_ay_31015 uart (
	.reset(RESET),
	.clk(CLK12),
	.rx_clk_en(uart_rx_cen),
	.tx_clk_en(uart_tx_cen),
	.din(cpu_dout),
	.dout(uart_dout),
	.ds_n(~(uart_data_sel & ~wr_n)),
	.eoc(),
	// status
	.pe(uart_status[4]),
	.fe(uart_status[3]),
	.ovr(uart_status[2]),
	.tbmt(uart_status[0]),
	.dav(uart_status[1]),
	.rdav_n(~(uart_data_sel & ~rd_n)),
	// control
	.cs(uart_ctrl_sel & ~wr_n),
	.np(cpu_dout[4]),  // no parity
	.tsb(cpu_dout[2]), // number of stop bits (not implemented)
	.nb(cpu_dout[1:0]),  // word length
	.eps(cpu_dout[3]), // even parity select
	// uart pins
	.rx(rs232_sel ? UART_RX : (ext_uart_active_sync ? ext_uart_bit_sync : decoder[2])),
	.tx(UART_TX)
);

always @(posedge CLK12) begin
	if (RESET)
		kbd_out <= 0;
	else if (ioen & ~wr_n & cpu_addr[1:0] == 2'b10) {rs232_sel, baud_sel, motor_ctrl, kbd_out} <= cpu_dout;

	if (RESET)
		AUDIO <= 14'h2000;
	else if (ioen & ~wr_n & cpu_addr[1:0] == 2'b11)
		AUDIO <= {cpu_dout, 6'b000000};
end

assign CASS_CTRL = motor_ctrl[0];
reg   [4:0] key_matrix[16];
assign UPCASE = ~key_matrix[0][3];

always @(posedge CLK12) begin : KEYBOARD
	if(RESET) begin
		integer i;
		for (i=0;i<16;i=i+1) begin
			key_matrix[i] <= 5'h1F;
		end
	end else begin
		if (KEY_STROBE) begin
			casez ({KEY_EXTENDED, KEY_CODE})
				9'h171: key_matrix[0][0] <= ~KEY_PRESSED; //Del (stop)
				9'h011: key_matrix[0][1] <= ~KEY_PRESSED; //LALT (GRAPHICS)
				9'h?14: key_matrix[0][2] <= ~KEY_PRESSED; //CTRL
				9'h?58: if (KEY_PRESSED) key_matrix[0][3] <= ~key_matrix[0][3]; //shift lock
				9'h?12: key_matrix[0][4] <= ~KEY_PRESSED; //lshift
				9'h?59: key_matrix[0][4] <= ~KEY_PRESSED; //rshift

				9'h16C: key_matrix[1][0] <= ~KEY_PRESSED; //Home (clear)
				9'h111: key_matrix[1][1] <= ~KEY_PRESSED; //RALT (repeat)
				9'h?29: key_matrix[1][2] <= ~KEY_PRESSED; //space
				9'h?0D: key_matrix[1][3] <= ~KEY_PRESSED; //TAB (skip)
				9'h?76: key_matrix[1][4] <= ~KEY_PRESSED; //ESC (sel)

				9'h?22: key_matrix[2][0] <= ~KEY_PRESSED; //X
				9'h?1A: key_matrix[2][1] <= ~KEY_PRESSED; //Z
				9'h?1C: key_matrix[2][2] <= ~KEY_PRESSED; //A
				9'h?15: key_matrix[2][3] <= ~KEY_PRESSED; //Q
				9'h?16: key_matrix[2][4] <= ~KEY_PRESSED; //1

				9'h?21: key_matrix[3][0] <= ~KEY_PRESSED; //C
				9'h?23: key_matrix[3][1] <= ~KEY_PRESSED; //D
				9'h?1B: key_matrix[3][2] <= ~KEY_PRESSED; //S
				9'h?1D: key_matrix[3][3] <= ~KEY_PRESSED; //W
				9'h?1E: key_matrix[3][4] <= ~KEY_PRESSED; //2

				9'h?2B: key_matrix[4][0] <= ~KEY_PRESSED; //F
				9'h?2D: key_matrix[4][1] <= ~KEY_PRESSED; //R
				9'h?24: key_matrix[4][2] <= ~KEY_PRESSED; //E
				9'h?25: key_matrix[4][3] <= ~KEY_PRESSED; //4
				9'h?26: key_matrix[4][4] <= ~KEY_PRESSED; //3

				9'h?32: key_matrix[5][0] <= ~KEY_PRESSED; //B
				9'h?2A: key_matrix[5][1] <= ~KEY_PRESSED; //V
				9'h?34: key_matrix[5][2] <= ~KEY_PRESSED; //G
				9'h?2C: key_matrix[5][3] <= ~KEY_PRESSED; //T
				9'h?2E: key_matrix[5][4] <= ~KEY_PRESSED; //5

				9'h?3A: key_matrix[6][0] <= ~KEY_PRESSED; //M
				9'h?31: key_matrix[6][1] <= ~KEY_PRESSED; //N
				9'h?33: key_matrix[6][2] <= ~KEY_PRESSED; //H
				9'h?35: key_matrix[6][3] <= ~KEY_PRESSED; //Y
				9'h?36: key_matrix[6][4] <= ~KEY_PRESSED; //6

				9'h?42: key_matrix[7][0] <= ~KEY_PRESSED; //K
				9'h?43: key_matrix[7][1] <= ~KEY_PRESSED; //I
				9'h?3B: key_matrix[7][2] <= ~KEY_PRESSED; //J
				9'h?3C: key_matrix[7][3] <= ~KEY_PRESSED; //U
				9'h?3D: key_matrix[7][4] <= ~KEY_PRESSED; //7

				9'h?41: key_matrix[8][0] <= ~KEY_PRESSED; //,
				9'h?4B: key_matrix[8][1] <= ~KEY_PRESSED; //L
				9'h?44: key_matrix[8][2] <= ~KEY_PRESSED; //O
				9'h?46: key_matrix[8][3] <= ~KEY_PRESSED; //9
				9'h?3E: key_matrix[8][4] <= ~KEY_PRESSED; //8

				9'h04A: key_matrix[9][0] <= ~KEY_PRESSED; //
				9'h?49: key_matrix[9][1] <= ~KEY_PRESSED; //.
				9'h?4C: key_matrix[9][2] <= ~KEY_PRESSED; //;
				9'h?4D: key_matrix[9][3] <= ~KEY_PRESSED; //P
				9'h?45: key_matrix[9][4] <= ~KEY_PRESSED; //0

				9'h?5D: key_matrix[10][0] <= ~KEY_PRESSED; //
				9'h?52: key_matrix[10][1] <= ~KEY_PRESSED; //' (@)
				9'h?5B: key_matrix[10][2] <= ~KEY_PRESSED; //]
				9'h?54: key_matrix[10][3] <= ~KEY_PRESSED; //[
				9'h?0E: key_matrix[10][4] <= ~KEY_PRESSED; //` (:)

				9'h?66: key_matrix[11][0] <= ~KEY_PRESSED; //Backspace (RUB, _)
				9'h?5A: key_matrix[11][1] <= ~KEY_PRESSED; //CR
				9'h17D: key_matrix[11][2] <= ~KEY_PRESSED; //Pg Up (Line Feed)
				9'h?55: key_matrix[11][3] <= ~KEY_PRESSED; //= (^)
				9'h?4E: key_matrix[11][4] <= ~KEY_PRESSED; //-

				9'h079: key_matrix[12][0] <= ~KEY_PRESSED; //KP +
				9'h07C: key_matrix[12][1] <= ~KEY_PRESSED; //KP *
				9'h14A: key_matrix[12][2] <= ~KEY_PRESSED; //KP /
				9'h07B: key_matrix[12][3] <= ~KEY_PRESSED; //KP -

				9'h070: key_matrix[13][0] <= ~KEY_PRESSED; //KP 0
				9'h069: key_matrix[13][1] <= ~KEY_PRESSED; //KP 1
				9'h06B: key_matrix[13][2] <= ~KEY_PRESSED; //KP 4
				9'h075: key_matrix[13][3] <= ~KEY_PRESSED; //KP 8
				9'h06C: key_matrix[13][4] <= ~KEY_PRESSED; //KP 7

				9'h071: key_matrix[14][0] <= ~KEY_PRESSED; //KP .
				9'h072: key_matrix[14][1] <= ~KEY_PRESSED; //KP 2
				9'h073: key_matrix[14][2] <= ~KEY_PRESSED; //KP 5
				9'h074: key_matrix[14][3] <= ~KEY_PRESSED; //KP 6
				9'h07D: key_matrix[14][4] <= ~KEY_PRESSED; //KP 9

				//9'h: key_matrix[15][3] <= ~KEY_PRESSED; // (KP =)
				9'h07A: key_matrix[15][4] <= ~KEY_PRESSED; //KP 3
			endcase
		end
	end

end

// Tape emulation
reg [15:0] tape_emu_addr;
reg [15:0] tape_emu_end;
reg        tape_emu_ready;
reg  [7:0] tape_emu_dout;

always @(posedge DL_CLK) begin : tape_emu
	reg rfshb_d;
	reg data_sel_d;

	if (RESET) begin
		tape_emu_addr <= 0;
		tape_emu_end <= 0;
		tape_emu_ready <= 0;
	end else begin
		if (tape_dl) begin
			tape_emu_addr <= 0;
			if (DL_WE) begin
				tape_emu_end <= DL_ADDR[15:0];
				tape_emu_ready <= 1;
			end
		end
		rfshb_d <= rfsh_n;
		if (~rfshb_d & rfsh_n) tape_emu_dout <= RAM_DOUT;
		data_sel_d <= uart_data_sel & ~rd_n;
		if (data_sel_d & ~(uart_data_sel & ~rd_n) & tape_emu_ready) begin
			tape_emu_addr <= tape_emu_addr + 1'd1;
			if (tape_emu_addr == tape_emu_end) tape_emu_ready <= 0;
		end
	end
end

assign LED = DL | tape_emu_ready | quick_ready | diskboot_loaded | |DISK_MOUNTED | fdc_busy | fdc_drq;

endmodule
