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

module sorcerer #(
	parameter SIM_FAST_FDC = 1'b0,
	parameter SIM_SLOW_LOADED_FDC = 1'b0
) (
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

	input  [15:0] RAM_TOP_EXCLUSIVE,
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

	input   [3:0] DISK_MOUNTED,
	input         DISK_READONLY,
	output reg    DISK_REQ,
	output reg    DISK_WRITE,
	output reg    DISK_WRITE_COMMIT,
	input         DISK_ACK,
	output        DISK_WAIT,
	output  [1:0] DISK_DRIVE,
	output        DISK_SIDE,
	output  [6:0] DISK_TRACK,
	output  [3:0] DISK_SECTOR,
	output        DISK_SECTOR_1024,
	output  [9:0] DISK_BUF_ADDR,
	input   [7:0] DISK_BUF_DOUT,
	output reg    DISK_BUF_WR,
	output reg [7:0] DISK_BUF_DIN,

	input         FDC_MICROPOLIS,
	input         FDC_DREAMDISK,
	output        LED
);

// clock enables
reg cen6 = 0, cen2 = 0, cen4 = 0;
reg   [2:0] cnt = 0;
always @(posedge CLK12) begin
	cen6 <= ~cen6;
	cnt <= cnt + 1'd1;
	if (cnt == 5) cnt <= 0;
	cen2 <= cnt == 0;
	cen4 <= cnt == 0 || cnt == 3;
end

// video circuit
reg   [8:0] hcnt = 0; // 3a-4a-5a
reg   [8:0] vcnt = 0; // 3b-4b-1b

reg   [7:0] rom_2b[32];
reg   [7:0] rom_2b_q = 8'hff;
reg   [7:0] charrom[1024];
reg   [7:0] charrom_q = 0;
reg   [7:0] charram[1024];
reg   [7:0] charram_q = 0;

always @(posedge DL_CLK) begin
	if (DL_WE & DL_ROM & DL_ADDR[15:12] == 1) begin
		if (DL_ADDR[11:0] < 1024) charrom[DL_ADDR[9:0]] <= DL_DATA;
		else rom_2b[DL_ADDR[4:0]] <= DL_DATA;
	end
end

reg         vsync = 0, hblank = 0;
reg         ihb = 0, ihb_r = 0;

wire        acpu;
wire        write_n;
wire        cs1;
wire        cs2;
wire        cs3;
wire        cs4;
wire        xwr;
wire [10:0] dl;
wire [11:0] tb;

wire        int_n = 1;
wire        nmi_n;
wire [15:0] cpu_addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        iorq_n;
wire        mreq_n;
wire        rfsh_n;
wire        rd_n;
wire        wr_n;
wire        m1_n;
wire        halt_n;
wire        busak_n;
wire [211:0] cpu_reg;
reg  [211:0] cpu_dir = 0;
reg          cpu_dirset = 0;
wire        pcgsel = rfsh_n & ~mreq_n & (cpu_addr[15:10] == 6'b111111);

reg   [3:0] kbd_out = 0;
reg         rs232_sel = 0;
reg         baud_sel = 0;
reg   [1:0] motor_ctrl = 0;
reg   [4:0] key_matrix[16];
wire  [4:0] kbd_in;
wire  [7:0] uart_dout;
wire  [7:0] uart_status;
wire        uart_data_sel;
wire        uart_ctrl_sel;
reg [15:0] tape_emu_addr = 0;
reg [15:0] tape_emu_end = 0;
reg        tape_emu_ready = 0;
reg  [7:0] tape_emu_dout = 0;

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

assign      tb = acpu ? cpu_addr[11:0] : {dl[10], vcnt[7:3], hcnt[7:2]};
wire        quick_dl = DL_QUICK & DL;
wire        quick_mem_active;
reg   [7:0] vram[2048];
reg   [7:0] vram_dout = 0;
reg  [10:3] dl_r = 0;
assign      dl = acpu ? tb[9:0] : {dl_r, vcnt[2:0]};
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
		charram[i] = 8'h00;
	end
end

reg  [7:0] char_shift = 0; // 8d

always @(posedge CLK12) begin
	vram_dout <= vram[tb[10:0]];
	if (quick_vram_wr) vram[quick_addr[10:0]] <= quick_data;
	else if ((!cs1 | !cs2) & !write_n) vram[tb[10:0]] <= cpu_dout;
	charrom_q <= charrom[dl[9:0]];
	charram_q <= charram[dl[9:0]];
	if ((!cs4 & !write_n) | (pcgsel & ~wr_n)) charram[dl[9:0]] <= cpu_dout;
	if (cen6 & buffload) dl_r[10:3] <= vram_dout; //5d
	if (cen6 & buffload & ~ihb & ~acpu)
		char_shift <= !cs3 ? charrom_q : charram_q;
	else
		char_shift <= {char_shift[6:0], 1'b0};
end

assign VIDEO = char_shift[7]; // 8d

// cpu
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
	.HALT_n(halt_n),
	.OUT0(1'b0),
	.A(cpu_addr),
	.DI(cpu_din),
	.DO(cpu_dout),
	.REG(cpu_reg),
	.DIRSet(cpu_dirset),
	.DIR(cpu_dir)
);

wire        inta_n = m1_n | iorq_n;
wire        up8k = &{cpu_addr[15:13], rfsh_n};
assign      acpu = &{up8k, cpu_addr[12], ~mreq_n} /* synthesis keep */;
assign      write_n = acpu ? xwr : 1'b1;
reg   [7:0] rom[4096];
reg   [7:0] rom_dout = 0;
reg   [7:0] diskboot[1024];
reg   [7:0] diskboot_dout = 0;
reg         diskboot_loaded = 0;
integer     diskboot_init_idx;

assign      DISKBOOT_READY = diskboot_loaded;

initial begin
	for (diskboot_init_idx = 0; diskboot_init_idx < 1024; diskboot_init_idx = diskboot_init_idx + 1)
		diskboot[diskboot_init_idx] = 8'hFF;
end

reg   [7:0] pac[8192];
reg   [7:0] pac_dout = 0;

always @(posedge CLK12) begin : ROM
	rom_dout <= rom[cpu_addr[11:0]];
	diskboot_dout <= diskboot[cpu_addr[9:0]];
	pac_dout <= pac[cpu_addr[12:0]];
	rom_2b_q <= rom_2b[{~acpu, tb[11:10], rd_n, wr_n}];
end
assign      cs1 = rom_2b_q[0] /* synthesis noprune */;
assign      cs2 = rom_2b_q[1] /* synthesis noprune */;
assign      cs3 = rom_2b_q[2] /* synthesis noprune */;
assign      cs4 = rom_2b_q[3] /* synthesis noprune */;
wire        dir = rom_2b_q[4] /* synthesis noprune */;
wire        db1e = rom_2b_q[5] /* synthesis noprune */;
wire        db2e = rom_2b_q[6] /* synthesis noprune */;
assign      xwr = rom_2b_q[7];

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
wire        diskbootsel = FDC_MICROPOLIS & rfsh_n & ~mreq_n & (cpu_addr[15:10] == 6'b101111) & (cpu_addr[15:2] != 14'b10111110000000) & diskboot_loaded;
wire        ramsel = cpu_addr < RAM_TOP_EXCLUSIVE;
wire        pacsel = rfsh_n & ~mreq_n & cpu_addr[15:13] == 3'b110 & pac_loaded;
wire        ramen = rfsh_n & ~mreq_n & ramsel & ~romen & ~pacsel /* synthesis keep */;
wire        ioen = ~iorq_n & &cpu_addr[7:2];
wire        fdc_sel = ~iorq_n & ((FDC_DREAMDISK & (cpu_addr[7:2] == 6'b010001)) | // 44-47
                                 (FDC_MICROPOLIS & (cpu_addr[7:2] == 6'b001010))); // 28-2B
wire        fdc_ctrl_sel = ~iorq_n & ((FDC_DREAMDISK & (cpu_addr[7:2] == 6'b010010)) | // 48-4B
                                      (FDC_MICROPOLIS & (cpu_addr[7:2] == 6'b001011))); // 2C-2F
reg   [7:0] fdc_track = 0;
reg   [7:0] fdc_sector = 1;
reg   [7:0] fdc_data = 0;
reg   [7:0] fdc_data_latch = 0;
reg         fdc_data_latched = 0;
reg   [7:0] fdc_ini_data = 0;
reg         fdc_ini_data_valid = 0;
reg   [7:0] fdc_ctrl = 0;
reg   [9:0] fdc_pos = 0;
reg         fdc_busy = 0;
reg         fdc_drq = 0;
reg         fdc_intrq = 0;
reg         fdc_not_found = 0;
reg         fdc_write_protect = 0;
reg         fdc_read_pending = 0;
reg         fdc_write_prepare_pending = 0;
reg         fdc_write_collecting = 0;
reg         fdc_write_commit_pending = 0;
reg         fdc_type1_status = 1;
reg   [9:0] fdc_terminal_pos = 0;
reg         fdc_dream_boot_short = 1;
reg         fdc_nmi_assert = 0;
reg         fdc_intrq_nmi_d = 0;
reg         fdc_intrq_nmi_pending = 0;
reg         fdc_drq_nmi_pending = 0;
reg         fdc_intrq_nmi_safe = 0;
reg   [7:0] fdc_dream_read_count = 0;
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
reg   [1:0] disk_drive = 0;
reg         disk_side = 0;
reg   [6:0] disk_track = 0;
reg   [3:0] disk_sector = 0;
reg   [1:0] disk_req_drive = 0;
reg         disk_req_side = 0;
reg   [6:0] disk_req_track = 0;
reg   [3:0] disk_req_sector = 0;
reg         disk_ack_meta = 0;
reg         disk_ack_sync = 0;
reg         disk_ack_last = 0;
wire  [7:0] fdc_ctrl_dec = fdc_ctrl ^ 8'h1f;
wire        fdc_dream_drive_selected = |fdc_ctrl_dec[3:0];
wire  [1:0] fdc_dream_drive = fdc_ctrl_dec[3] ? 2'd3 :
                               fdc_ctrl_dec[2] ? 2'd2 :
                               fdc_ctrl_dec[1] ? 2'd1 : 2'd0;
// DreamDisk port 48 matches MAME's port48_w: when no active-low select bit
// is asserted the WD2793 is disconnected, rather than retaining a prior drive.
wire  [1:0] fdc_drive = FDC_DREAMDISK ? fdc_dream_drive : {1'b0, fdc_ctrl[3]};
wire        fdc_drive_selected = FDC_DREAMDISK ? fdc_dream_drive_selected : (fdc_ctrl[2] | fdc_ctrl[3]);
wire        fdc_side = FDC_DREAMDISK ? fdc_ctrl_dec[4] : 1'b0;
wire        fdc_ready = fdc_drive_selected & DISK_MOUNTED[fdc_drive];
wire        fdc_dream_valid_sector = fdc_track < 8'd80 && fdc_sector >= 8'd1 && fdc_sector <= 8'd5;
wire        fdc_micro_valid_sector = fdc_track < 8'd77 && fdc_sector >= 8'd1 && fdc_sector <= 8'd16;
wire        fdc_track0_status = fdc_type1_status & FDC_DREAMDISK & (fdc_track == 8'd0) & ~fdc_drq;
wire  [7:0] fdc_status_read = {~fdc_ready, fdc_write_protect, 1'b0, fdc_not_found, 1'b0, fdc_track0_status, fdc_drq, fdc_busy};
// MAME's port48_r returns the unmodified output latch regardless of readiness.
wire  [7:0] fdc_ctrl_read = fdc_ctrl;
wire  [7:0] fdc_data_read = fdc_drq ? (fdc_data_latched ? fdc_data_latch : DISK_BUF_DOUT) : fdc_data;
wire        fdc_intrq_nmi_rise = fdc_intrq & ~fdc_intrq_nmi_d;
wire        m1_fetch = rfsh_n & ~mreq_n & ~rd_n & ~m1_n;
wire        mem_write_cycle = rfsh_n & ~mreq_n & ~wr_n;
wire        loaded_bios_pc = cpu_reg[79:64] >= 16'hB000 && cpu_reg[79:64] < 16'hC000;
wire        fdc_ini_writeback = FDC_DREAMDISK & fdc_ini_data_valid & mem_write_cycle & ramen;
wire        fdc_nmi_ack = m1_fetch && (cpu_addr == 16'h0066);
wire        fdc_intrq_nmi_source = fdc_intrq_nmi_safe & (fdc_intrq_nmi_pending | fdc_intrq_nmi_rise);
wire        fdc_nmi_source = fdc_drq_nmi_pending | fdc_intrq_nmi_source;
wire        microsel = FDC_MICROPOLIS & rfsh_n & ~mreq_n & (cpu_addr[15:2] == 14'b10111110000000); // BE00-BE03
wire        micro_data_port_read = microsel & ~rd_n & cpu_addr[1] & micro_ready;
wire        micro_data_wait = 1'b0;
wire        micro_data_read = micro_data_port_read;
wire        disk_req_active = micro_pending | fdc_read_pending |
                                fdc_write_prepare_pending | fdc_write_commit_pending;
wire  [1:0] disk_wait_drive = disk_req_active ? disk_req_drive : disk_drive;
wire        micro_status_wait = micro_status_wait_active &
                                DISK_MOUNTED[disk_wait_drive] & !micro_status_wait_done;
assign      DISK_DRIVE = disk_req_active ? disk_req_drive : disk_drive;
assign      DISK_SIDE = disk_req_active ? disk_req_side : disk_side;
assign      DISK_TRACK = disk_req_active ? disk_req_track : disk_track;
assign      DISK_SECTOR = disk_req_active ? disk_req_sector : disk_sector;
assign      DISK_SECTOR_1024 = FDC_DREAMDISK &&
                               (fdc_read_pending | fdc_write_prepare_pending |
                                fdc_write_collecting | fdc_write_commit_pending);
assign      DISK_BUF_ADDR = microsel ? {1'b0, micro_pos} : fdc_pos;
assign      DISK_WAIT = micro_pending | fdc_read_pending |
                        fdc_write_prepare_pending | fdc_write_commit_pending |
                        micro_status_wait |
                        micro_data_wait;
assign      nmi_n = ~fdc_nmi_assert;

wire  [7:0] io_in_raw =
            fdc_sel ? (cpu_addr[1:0] == 2'b00 ? fdc_status_read :
                       cpu_addr[1:0] == 2'b01 ? fdc_track :
                       cpu_addr[1:0] == 2'b10 ? fdc_sector :
                       fdc_data_read) :
            fdc_ctrl_sel ? fdc_ctrl_read :
            cpu_addr[1:0] == 2'b10 ? {2'b11, vcnt[8], kbd_in} :
            uart_data_sel ? (tape_emu_ready ? tape_emu_dout : uart_dout) :
            uart_ctrl_sel ? (tape_emu_ready ? 8'h02 : uart_status) :
            8'hff;
wire  [7:0] io_in = (~rd_n === 1'b1) ? io_in_raw : 8'hff;
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
	reg fdc_rd_status;
	reg fdc_rd_status_d;
	reg fdc_rd_data;
	reg fdc_rd_data_d;
	reg fdc_wr;
	reg fdc_wr_d;
	reg fdc_wr_data;
	reg fdc_wr_data_d;
	reg fdc_ctrl_wr;
	reg fdc_ctrl_wr_d;
	reg micro_rd;
	reg micro_rd_d;
	reg micro_wr;
	reg micro_wr_d;

	disk_ack_meta <= DISK_ACK;
	disk_ack_sync <= disk_ack_meta;
	disk_ack_last <= disk_ack_sync;

	fdc_rd_status <= fdc_sel & ~rd_n & (cpu_addr[1:0] == 2'b00);
	fdc_rd_status_d <= fdc_rd_status;
	fdc_rd_data <= fdc_sel & ~rd_n & (cpu_addr[1:0] == 2'b11);
	fdc_rd_data_d <= fdc_rd_data;
	fdc_wr <= fdc_sel & ~wr_n;
	fdc_wr_d <= fdc_wr;
	fdc_wr_data <= fdc_sel & ~wr_n & (cpu_addr[1:0] == 2'b11);
	fdc_wr_data_d <= fdc_wr_data;
	fdc_ctrl_wr <= fdc_ctrl_sel & ~wr_n;
	fdc_ctrl_wr_d <= fdc_ctrl_wr;
	micro_rd <= microsel & ~rd_n;
	micro_rd_d <= micro_rd;
	micro_wr <= microsel & ~wr_n;
	micro_wr_d <= micro_wr;
	DISK_BUF_WR <= 0;

	if (RESET) begin
		fdc_rd_status <= 0;
		fdc_rd_status_d <= 0;
		fdc_rd_data <= 0;
		fdc_rd_data_d <= 0;
		fdc_wr <= 0;
		fdc_wr_d <= 0;
		fdc_wr_data <= 0;
		fdc_wr_data_d <= 0;
		fdc_ctrl_wr <= 0;
		fdc_ctrl_wr_d <= 0;
		micro_rd <= 0;
		micro_rd_d <= 0;
		micro_wr <= 0;
		micro_wr_d <= 0;
		fdc_track <= 0;
		fdc_sector <= 1;
		fdc_data <= 0;
		fdc_data_latch <= 0;
		fdc_data_latched <= 0;
		fdc_ini_data <= 0;
		fdc_ini_data_valid <= 0;
		fdc_ctrl <= FDC_DREAMDISK ? 8'h1f : 8'h00;
		fdc_pos <= 0;
		fdc_busy <= 0;
		fdc_drq <= 0;
		fdc_intrq <= 0;
		fdc_not_found <= 0;
		fdc_write_protect <= 0;
		fdc_read_pending <= 0;
		fdc_write_prepare_pending <= 0;
		fdc_write_collecting <= 0;
		fdc_write_commit_pending <= 0;
		fdc_type1_status <= 1;
		fdc_terminal_pos <= 0;
		fdc_dream_boot_short <= 1;
		fdc_nmi_assert <= 0;
		fdc_intrq_nmi_d <= 0;
		fdc_intrq_nmi_pending <= 0;
		fdc_drq_nmi_pending <= 0;
		fdc_intrq_nmi_safe <= 0;
		fdc_dream_read_count <= 0;
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
		disk_side <= 0;
		disk_track <= 0;
		disk_sector <= 0;
		disk_req_drive <= 0;
		disk_req_side <= 0;
		disk_req_track <= 0;
		disk_req_sector <= 0;
		DISK_REQ <= 0;
		DISK_WRITE <= 0;
		DISK_WRITE_COMMIT <= 0;
		DISK_BUF_WR <= 0;
		DISK_BUF_DIN <= 0;
	end else begin
		fdc_intrq_nmi_d <= fdc_intrq;
		if (fdc_intrq_nmi_rise) fdc_intrq_nmi_pending <= 1;
		if (fdc_nmi_ack) begin
			fdc_intrq_nmi_pending <= 0;
			fdc_drq_nmi_pending <= 0;
		end
		if (mem_write_cycle && cpu_addr == 16'h0066) fdc_intrq_nmi_safe <= cpu_dout == 8'hC9;
		fdc_nmi_assert <= FDC_DREAMDISK && fdc_nmi_source && !halt_n;

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
			if (SIM_FAST_FDC && FDC_DREAMDISK && !(SIM_SLOW_LOADED_FDC && loaded_bios_pc)) begin
				fdc_busy <= 0;
				fdc_drq <= 0;
				fdc_drq_nmi_pending <= 0;
				fdc_intrq <= 0;
				fdc_intrq_nmi_pending <= 0;
			end else begin
				fdc_busy <= 1;
				fdc_drq <= 1;
				fdc_drq_nmi_pending <= FDC_DREAMDISK;
			end
			fdc_not_found <= 0;
			fdc_read_pending <= 0;
		end
		if ((disk_ack_sync ^ disk_ack_last) & fdc_write_prepare_pending) begin
			fdc_pos <= 0;
			fdc_busy <= 1;
			fdc_drq <= 1;
			fdc_drq_nmi_pending <= FDC_DREAMDISK;
			fdc_not_found <= 0;
			fdc_write_prepare_pending <= 0;
			fdc_write_collecting <= 1;
		end
		if ((disk_ack_sync ^ disk_ack_last) & fdc_write_commit_pending) begin
			fdc_pos <= 0;
			fdc_busy <= 0;
			fdc_drq <= 0;
			fdc_intrq <= FDC_DREAMDISK;
			fdc_intrq_nmi_pending <= FDC_DREAMDISK;
			fdc_write_commit_pending <= 0;
			DISK_WRITE <= 0;
		end
		if (fdc_rd_status & ~fdc_rd_status_d) begin
			fdc_intrq <= 0;
			fdc_intrq_nmi_pending <= 0;
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
			fdc_data_latch <= DISK_BUF_DOUT;
			fdc_data_latched <= 1;
			if (FDC_DREAMDISK) begin
				fdc_ini_data <= DISK_BUF_DOUT;
				fdc_ini_data_valid <= 1;
			end
		end
		if (fdc_rd_data_d & ~fdc_rd_data & fdc_drq) begin
			fdc_data_latched <= 0;
			if (fdc_pos == fdc_terminal_pos) begin
				fdc_pos <= 0;
				fdc_busy <= 0;
				fdc_drq <= 0;
				fdc_drq_nmi_pending <= 0;
				fdc_intrq <= FDC_DREAMDISK;
				fdc_intrq_nmi_pending <= FDC_DREAMDISK;
			end else begin
				fdc_pos <= fdc_pos + 1'd1;
				fdc_drq_nmi_pending <= FDC_DREAMDISK;
			end
		end
		if (fdc_wr_data & ~fdc_wr_data_d & fdc_drq & fdc_write_collecting) begin
			DISK_BUF_DIN <= cpu_dout;
			DISK_BUF_WR <= 1;
		end
		if (fdc_wr_data_d & ~fdc_wr_data & fdc_drq & fdc_write_collecting) begin
			if (fdc_pos == fdc_terminal_pos) begin
				fdc_pos <= 0;
				fdc_drq <= 0;
				fdc_drq_nmi_pending <= 0;
				fdc_write_collecting <= 0;
				fdc_write_commit_pending <= 1;
				DISK_WRITE_COMMIT <= ~DISK_WRITE_COMMIT;
			end else begin
				fdc_pos <= fdc_pos + 1'd1;
				fdc_drq_nmi_pending <= FDC_DREAMDISK;
			end
		end
		if (m1_fetch) begin
			fdc_ini_data_valid <= 0;
		end

		if (fdc_ctrl_wr & ~fdc_ctrl_wr_d) begin
			fdc_ctrl <= cpu_dout;
		end

		if (fdc_wr & ~fdc_wr_d) begin
			case (cpu_addr[1:0])
				2'b00: begin
					fdc_not_found <= 0;
					fdc_intrq <= 0;
					fdc_drq_nmi_pending <= 0;
					casez (cpu_dout)
						8'b0000_????: begin // restore
							fdc_type1_status <= 1;
							fdc_track <= 0;
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
							fdc_not_found <= 0;
							fdc_write_protect <= 0;
							fdc_intrq <= FDC_DREAMDISK;
							fdc_intrq_nmi_pending <= FDC_DREAMDISK;
						end

						8'b0001_????: begin // seek
							fdc_type1_status <= 1;
							fdc_track <= fdc_data;
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
							fdc_not_found <= 0;
							fdc_intrq <= FDC_DREAMDISK;
							fdc_intrq_nmi_pending <= FDC_DREAMDISK;
						end

						8'b001?_????: begin // step
							fdc_type1_status <= 1;
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_intrq <= FDC_DREAMDISK;
							fdc_intrq_nmi_pending <= FDC_DREAMDISK;
						end

						8'b010?_????: begin // step in
							fdc_type1_status <= 1;
							if (fdc_track != (FDC_DREAMDISK ? 8'd79 : 8'd76)) fdc_track <= fdc_track + 1'd1;
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_intrq <= FDC_DREAMDISK;
							fdc_intrq_nmi_pending <= FDC_DREAMDISK;
						end

						8'b011?_????: begin // step out
							fdc_type1_status <= 1;
							if (fdc_track != 0) fdc_track <= fdc_track - 1'd1;
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_intrq <= FDC_DREAMDISK;
							fdc_intrq_nmi_pending <= FDC_DREAMDISK;
						end

						8'b100?_????: begin // read sector
							fdc_type1_status <= 0;
							DISK_WRITE <= 0;
							fdc_pos <= 0;
							fdc_drq <= 0;
							fdc_intrq <= 0;
							if (fdc_ready && (FDC_DREAMDISK ? fdc_dream_valid_sector : fdc_micro_valid_sector)) begin
								disk_drive <= fdc_drive;
								disk_side <= fdc_side;
								disk_track <= fdc_track[6:0];
								disk_sector <= FDC_DREAMDISK ? fdc_sector[3:0] : (fdc_sector[3:0] - 1'd1);
								disk_req_drive <= fdc_drive;
								disk_req_side <= fdc_side;
								disk_req_track <= fdc_track[6:0];
								disk_req_sector <= FDC_DREAMDISK ? fdc_sector[3:0] : (fdc_sector[3:0] - 1'd1);
								fdc_busy <= 1;
								fdc_read_pending <= 1;
								fdc_terminal_pos <= FDC_DREAMDISK ? (fdc_dream_boot_short ? 10'd127 : 10'd1023) : 10'd269;
								if (FDC_DREAMDISK) fdc_dream_boot_short <= 0;
								if (FDC_DREAMDISK) fdc_dream_read_count <= fdc_dream_read_count + 1'd1;
								fdc_not_found <= 0;
								fdc_write_protect <= 0;
								DISK_REQ <= ~DISK_REQ;
							end else begin
								fdc_busy <= 0;
								fdc_read_pending <= 0;
								fdc_not_found <= 1;
								fdc_intrq <= FDC_DREAMDISK;
								fdc_intrq_nmi_pending <= FDC_DREAMDISK;
							end
						end

						8'b101?_????: begin // write sector
							fdc_type1_status <= 0;
							fdc_pos <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
							fdc_write_collecting <= 0;
							fdc_write_commit_pending <= 0;
							if (fdc_ready && fdc_dream_valid_sector && !DISK_READONLY) begin
								disk_drive <= fdc_drive;
								disk_side <= fdc_side;
								disk_track <= fdc_track[6:0];
								disk_sector <= fdc_sector[3:0];
								disk_req_drive <= fdc_drive;
								disk_req_side <= fdc_side;
								disk_req_track <= fdc_track[6:0];
								disk_req_sector <= fdc_sector[3:0];
								fdc_terminal_pos <= 10'd1023;
								fdc_busy <= 1;
								fdc_not_found <= 0;
								fdc_write_protect <= 0;
								fdc_write_prepare_pending <= 1;
								DISK_WRITE <= 1;
								DISK_REQ <= ~DISK_REQ;
							end else begin
								fdc_busy <= 0;
								fdc_write_prepare_pending <= 0;
								fdc_not_found <= !DISK_READONLY;
								fdc_write_protect <= DISK_READONLY;
								fdc_intrq <= FDC_DREAMDISK;
								fdc_intrq_nmi_pending <= FDC_DREAMDISK;
								DISK_WRITE <= 0;
							end
						end

						8'b1101_????: begin // force interrupt
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
							fdc_write_prepare_pending <= 0;
							fdc_write_collecting <= 0;
							fdc_write_commit_pending <= 0;
							DISK_WRITE <= 0;
							fdc_not_found <= 0;
							fdc_intrq <= FDC_DREAMDISK;
							fdc_intrq_nmi_pending <= FDC_DREAMDISK;
						end

						default: begin
							fdc_busy <= 0;
							fdc_drq <= 0;
							fdc_read_pending <= 0;
							fdc_intrq <= FDC_DREAMDISK;
							fdc_intrq_nmi_pending <= FDC_DREAMDISK;
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

assign      cpu_din = pcgsel ? charram_q :
                      romcs ? rom_dout :
                      diskbootsel ? diskboot_dout :
                      microsel ? micro_in :
                      ramen ? RAM_DOUT :
                      pacsel ? pac_dout:
                      ((~cs1 | ~cs2) & ~db1e) ? vram_dout :
                      (~cs3 & ~db1e) ? charrom_q :
                      (~cs4 & ~db1e) ? charram_q :
                      (ioen | fdc_sel | fdc_ctrl_sel) ? io_in : 8'hff;

wire        tape_dl = 1'b0;
reg   [7:0] tape_wr = 0;
always @(posedge DL_CLK) begin
	if (RESET) tape_wr <= 0;
	else if (DL_WE) tape_wr <= 8'hFF;
	else tape_wr <= {1'b0, tape_wr[7:1]};
end

reg  [15:0] quick_exec = 0;
reg  [15:0] quick_pc = 0;
reg  [15:0] quick_end = 0;
reg  [15:0] quick_stub_addr = 0;
reg         quick_ready = 0;
reg         quick_error = 0;
reg         quick_autorun = 0;
reg         quick_basic = 0;
reg         quick_run = 0;
reg         quick_clear_busy = 0;
reg  [15:0] quick_clear_addr = 0;
reg   [3:0] quick_patch_idx = 4'hF;
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
		final_end <= 0;
		is_basic_load <= 0;
		is_autorun_load <= 0;
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

	if (RESET) begin
		quick_run_meta <= 0;
		quick_run_sync <= 0;
		quick_run_d <= 0;
		cpu_dirset <= 0;
	end else if (quick_run_sync & ~quick_run_d) begin
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
assign      RAM_DIN = quick_mem_active ? quick_data : tape_dl ? DL_DATA : fdc_ini_writeback ? fdc_ini_data : cpu_dout;

assign      kbd_in = key_matrix[kbd_out];
assign      uart_data_sel = ioen & cpu_addr[1:0] == 2'b00;
assign      uart_ctrl_sel = ioen & cpu_addr[1:0] == 2'b01;
reg         cen_4800 = 0, cen_19200 = 0, cen_38400 = 0;
reg         uart_rx_cen = 0, uart_tx_cen = 0;
reg         ext_uart_active_meta = 0, ext_uart_active_sync = 0;
reg         ext_uart_bit_meta = 0, ext_uart_bit_sync = 0;
reg         ext_uart_baud_meta = 0, ext_uart_baud_sync = 0;

reg   [5:0] div55_cnt = 0;
reg   [2:0] div8_cnt = 0;
always @(posedge CLK12) begin
	if (RESET) begin
		div55_cnt <= 0;
		div8_cnt <= 0;
		cen_38400 <= 0;
		cen_19200 <= 0;
		cen_4800 <= 0;
	end else begin
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
end

always @(posedge CLK12) begin
	if (RESET) begin
		ext_uart_active_meta <= 0;
		ext_uart_active_sync <= 0;
		ext_uart_bit_meta <= 0;
		ext_uart_bit_sync <= 0;
		ext_uart_baud_meta <= 0;
		ext_uart_baud_sync <= 0;
	end else begin
		ext_uart_active_meta <= EXT_UART_RX_ACTIVE;
		ext_uart_active_sync <= ext_uart_active_meta;
		ext_uart_bit_meta <= EXT_UART_RX_BIT;
		ext_uart_bit_sync <= ext_uart_bit_meta;
		ext_uart_baud_meta <= EXT_UART_HIGH_BAUD;
		ext_uart_baud_sync <= ext_uart_baud_meta;
	end
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
reg   [2:0] decoder = 0;
reg   [3:0] decoder_cnt = 4;

always @(posedge CLK12) begin
	reg cass_in_d;

	if (RESET) begin
		cass_in_d <= 0;
		decoder <= 0;
		decoder_cnt <= 4;
	end else begin
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
always @(posedge DL_CLK) begin : tape_emu
	reg rfshb_d;
	reg data_sel_d;

	if (RESET) begin
		rfshb_d <= 0;
		data_sel_d <= 0;
		tape_emu_addr <= 0;
		tape_emu_end <= 0;
		tape_emu_ready <= 0;
		tape_emu_dout <= 0;
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
