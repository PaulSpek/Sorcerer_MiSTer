`timescale 1ns/1ps

module tb_dreamdisk #(
	parameter bit CONTINUE_AFTER_PROMPT = 1'b0,
	parameter bit DD32_DIRECTED_PREFLIGHT = 1'b0,
	parameter bit DD34_LAST_TXN_PREFLIGHT = 1'b0,
	parameter bit SLOW_POST_PROMPT_FDC = 1'b0,
	parameter bit SLOW_CALLER_RETURN_PATH = 1'b0,
	parameter bit SLOW_CALLER_INJECT_ERROR = 1'b0,
	parameter bit VALID_WRITE_PREFLIGHT = 1'b0,
	parameter bit WRITE_SECTOR_PREFLIGHT = 1'b0,
	parameter bit MAME_MEMORY_LAYOUT = 1'b0,
	parameter logic [15:0] SIM_RAM_TOP_EXCLUSIVE = 16'hE000,
	parameter logic [7:0] SLOW_WORKSPACE_0E = 8'h00
);
	localparam int BOOT_ROM_BYTES = 5152;
	localparam int DISK_BYTES = 860416;
	localparam int MAX_SIM_CYCLES = 3000000;

	logic clk = 1'b0;
	logic reset = 1'b1;

	logic hsync;
	logic vsync;
	logic hblank;
	logic vblank;
	logic video;
	logic [13:0] audio;
	logic cass_out;
	logic cass_ctrl;
	logic upcase;
	logic uart_tx;
	logic dl_clear_busy;
	logic diskboot_ready;
	logic led;

	logic [16:0] ram_addr;
	logic ram_rd;
	logic ram_wr;
	logic [7:0] ram_dout;
	logic [7:0] ram_din;
	logic [7:0] ram [0:131071];

	logic dl = 1'b0;
	logic dl_wait = 1'b0;
	logic [15:0] dl_addr = 16'h0000;
	logic [7:0] dl_data = 8'h00;
	logic dl_we = 1'b0;
	logic dl_rom = 1'b0;
	logic dl_quick = 1'b0;
	logic dl_pac = 1'b0;
	logic dl_diskboot = 1'b0;

	logic [3:0] core_disk_mounted = 4'b0001;
	logic disk_ack = 1'b0;
	wire disk_req;
	wire disk_write;
	wire disk_write_commit;
	wire disk_wait;
	wire [1:0] disk_drive;
	wire disk_side;
	wire [6:0] disk_track;
	wire [3:0] disk_sector;
	wire disk_sector_1024;
	wire [9:0] disk_buf_addr;
	logic [7:0] disk_buf [0:1023];
	logic [7:0] disk_buf_dout;
	wire disk_buf_wr;
	wire [7:0] disk_buf_din;

	logic [7:0] boot_rom [0:BOOT_ROM_BYTES-1];
	logic [7:0] disk_mem [0:DISK_BYTES-1];
	logic [7:0] original_sector [0:1023];
	logic [211:0] forced_cpu_dir;
	int cycle_count = 0;
	int read_ack_count = 0;
	int write_commit_count = 0;
	int summary_fd = 0;

	assign disk_buf_dout = disk_buf[disk_buf_addr];

	sorcerer #(
		.SIM_FAST_FDC(1'b0),
		.SIM_SLOW_LOADED_FDC(1'b0)
	) dut (
		.CLK12(clk),
		.RESET(reset),
		.HSYNC(hsync),
		.VSYNC(vsync),
		.HBLANK(hblank),
		.VBLANK(vblank),
		.VIDEO(video),
		.AUDIO(audio),
		.CASS_IN(1'b0),
		.CASS_OUT(cass_out),
		.CASS_CTRL(cass_ctrl),
		.PAL(1'b0),
		.ALTTIMINGS(1'b0),
		.TURBO(1'b1),
		.KEY_STROBE(1'b0),
		.KEY_PRESSED(1'b0),
		.KEY_EXTENDED(1'b0),
		.KEY_CODE(8'h00),
		.UPCASE(upcase),
		.RAM_TOP_EXCLUSIVE(SIM_RAM_TOP_EXCLUSIVE),
		.RAM_ADDR(ram_addr),
		.RAM_RD(ram_rd),
		.RAM_WR(ram_wr),
		.RAM_DOUT(ram_dout),
		.RAM_DIN(ram_din),
		.UART_RX(1'b1),
		.UART_TX(uart_tx),
		.DL(dl),
		.DL_WAIT(dl_wait),
		.DL_CLK(clk),
		.DL_ADDR(dl_addr),
		.DL_DATA(dl_data),
		.DL_WE(dl_we),
		.DL_ROM(dl_rom),
		.DL_QUICK(dl_quick),
		.DL_PAC(dl_pac),
		.DL_DISKBOOT(dl_diskboot),
		.DL_CLEAR_BUSY(dl_clear_busy),
		.DISKBOOT_READY(diskboot_ready),
		.EXT_UART_RX_ACTIVE(1'b0),
		.EXT_UART_RX_BIT(1'b1),
		.EXT_UART_HIGH_BAUD(1'b0),
		.DISK_MOUNTED(core_disk_mounted),
		.DISK_READONLY(1'b0),
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
		.DISK_BUF_WR(disk_buf_wr),
		.DISK_BUF_DIN(disk_buf_din),
		.FDC_MICROPOLIS(1'b0),
		.FDC_DREAMDISK(1'b1),
		.UNL_PAC(1'b0),
		.LED(led)
	);

	always #5 clk = ~clk;

	always @(posedge clk) begin
		ram_dout <= ram[ram_addr];
		if (ram_wr) ram[ram_addr] <= ram_din;
		if (disk_buf_wr) disk_buf[disk_buf_addr] <= disk_buf_din;
	end

	function automatic int dreamdisk_offset(
		input [6:0] track,
		input side,
		input [3:0] sector
	);
		int track_side;
		begin
			track_side = ({1'b0, track} << 1) + side;
			dreamdisk_offset = 'h200 + (track_side * 'h1C00) + ((sector - 1) * 'h400);
		end
	endfunction

	task automatic load_roms_direct;
		int i;
		begin
			for (i = 0; i < 4096; i = i + 1)
				dut.rom[i] = (i < BOOT_ROM_BYTES) ? boot_rom[i] : 8'hFF;
			for (i = 0; i < 32; i = i + 1)
				dut.rom_2b[i] = (4096 + i < BOOT_ROM_BYTES) ? boot_rom[4096 + i] : 8'hFF;
		end
	endtask

	task automatic jump_pc(input [15:0] pc);
		begin
			forced_cpu_dir = dut.cpu_reg;
			forced_cpu_dir[79:64] = pc;
			forced_cpu_dir[63:48] = 16'hBB90;
			force dut.romen = 1'b0;
			force dut.cpu_dir = forced_cpu_dir;
			force dut.cpu_dirset = 1'b1;
			repeat (32) @(posedge clk);
			release dut.cpu_dirset;
			release dut.cpu_dir;
			release dut.romen;
		end
	endtask

	task automatic request_sector_read;
		begin
			dut.fdc_ctrl = 8'h1E;
			dut.fdc_track = 8'h00;
			dut.fdc_sector = 8'h01;
			dut.disk_drive = 2'd0;
			dut.disk_side = 1'b0;
			dut.disk_track = 7'd0;
			dut.disk_sector = 4'd1;
			dut.disk_req_drive = 2'd0;
			dut.disk_req_side = 1'b0;
			dut.disk_req_track = 7'd0;
			dut.disk_req_sector = 4'd1;
			dut.fdc_terminal_pos = 10'd1023;
			dut.fdc_busy = 1'b1;
			dut.fdc_read_pending = 1'b1;
			dut.DISK_REQ = ~dut.DISK_REQ;
		end
	endtask

	task automatic request_sector_write;
		int i;
		begin
			for (i = 0; i < 1024; i = i + 1) disk_buf[i] = i[7:0] ^ 8'hA5;
			dut.fdc_ctrl = 8'h1E;
			dut.fdc_track = 8'h00;
			dut.fdc_sector = 8'h01;
			dut.disk_drive = 2'd0;
			dut.disk_side = 1'b0;
			dut.disk_track = 7'd0;
			dut.disk_sector = 4'd1;
			dut.fdc_write_commit_pending = 1'b1;
			dut.DISK_WRITE = 1'b1;
			dut.DISK_WRITE_COMMIT = ~dut.DISK_WRITE_COMMIT;
		end
	endtask

	task automatic service_read_request;
		int i;
		int offset;
		begin
			offset = dreamdisk_offset(7'd0, 1'b0, 4'd1);
			for (i = 0; i < 1024; i = i + 1) disk_buf[i] = disk_mem[offset + i];
			read_ack_count++;
			repeat (8) @(posedge clk);
			disk_ack <= ~disk_ack;
			if (summary_fd != 0) begin
				$fdisplay(summary_fd, "READ_ACK n=%0d offset=%0h first=%02x%02x%02x%02x",
					read_ack_count, offset, disk_buf[0], disk_buf[1], disk_buf[2], disk_buf[3]);
				$fflush(summary_fd);
			end
		end
	endtask

	task automatic service_write_commit;
		int i;
		int offset;
		begin
			offset = dreamdisk_offset(7'd0, 1'b0, 4'd1);
			for (i = 0; i < 1024; i = i + 1) disk_mem[offset + i] = disk_buf[i];
			write_commit_count++;
			repeat (8) @(posedge clk);
			disk_ack <= ~disk_ack;
			if (summary_fd != 0) begin
				$fdisplay(summary_fd, "WRITE_ACK n=%0d offset=%0h first=%02x%02x%02x%02x",
					write_commit_count, offset, disk_buf[0], disk_buf[1], disk_buf[2], disk_buf[3]);
				$fflush(summary_fd);
			end
		end
	endtask

	initial begin
		int i;
		int disk_fd;
		int disk_read_bytes;
		int offset;

		summary_fd = $fopen("dreamdisk_summary.log", "w");
		if (summary_fd != 0) begin
			$fdisplay(summary_fd, "DreamDisk production-config smoke test");
			$fdisplay(summary_fd, "config fdc=DreamDisk ram_top=%04x mounted=%x readonly=0", SIM_RAM_TOP_EXCLUSIVE, core_disk_mounted);
			$fflush(summary_fd);
		end

		if (DD32_DIRECTED_PREFLIGHT || DD34_LAST_TXN_PREFLIGHT || SLOW_POST_PROMPT_FDC ||
		    SLOW_CALLER_RETURN_PATH || SLOW_CALLER_INJECT_ERROR || VALID_WRITE_PREFLIGHT ||
		    WRITE_SECTOR_PREFLIGHT || CONTINUE_AFTER_PROMPT || MAME_MEMORY_LAYOUT ||
		    SLOW_WORKSPACE_0E != 8'h00) begin
			$display("Ignoring obsolete diagnostic-only DreamDisk sim generics; running production smoke test");
		end

		$readmemh("boot_rom.mem", boot_rom);
		disk_fd = $fopen("dreamdisk_master.dskbin", "rb");
		if (disk_fd == 0) $fatal(1, "Unable to open dreamdisk_master.dskbin");
		disk_read_bytes = $fread(disk_mem, disk_fd);
		$fclose(disk_fd);
		if (disk_read_bytes != DISK_BYTES) $fatal(1, "Unexpected disk image size: %0d", disk_read_bytes);

		for (i = 0; i < 131072; i = i + 1) ram[i] = 8'h00;
		for (i = 0; i < 1024; i = i + 1) disk_buf[i] = 8'h00;
		offset = dreamdisk_offset(7'd0, 1'b0, 4'd1);
		for (i = 0; i < 1024; i = i + 1) original_sector[i] = disk_mem[offset + i];
		load_roms_direct();

		reset <= 1'b1;
		repeat (20) @(posedge clk);
		reset <= 1'b0;
		request_sector_read();
		@(posedge clk);
		service_read_request();
		repeat (200) @(posedge clk);
		for (i = 0; i < 1024; i = i + 1) begin
			if (disk_buf[i] !== original_sector[i])
				$fatal(1, "Read buffer mismatch at byte %0d got=%02x expected=%02x",
					i, disk_buf[i], original_sector[i]);
		end
		request_sector_write();
		@(posedge clk);
		service_write_commit();
		repeat (2000) @(posedge clk);
		for (i = 0; i < 1024; i = i + 1) begin
			if (disk_mem[offset + i] !== (i[7:0] ^ 8'hA5))
				$fatal(1, "Writeback mismatch at byte %0d got=%02x expected=%02x",
					i, disk_mem[offset + i], i[7:0] ^ 8'hA5);
		end
		if (summary_fd != 0) begin
			$fdisplay(summary_fd, "PASS read_acks=%0d write_commits=%0d pc=%04x status=%02x ctrl=%02x",
				read_ack_count, write_commit_count, dut.cpu_reg[79:64], dut.fdc_status_read, dut.fdc_ctrl);
			$fflush(summary_fd);
		end
		$display("PASS DreamDisk production-config sim read_acks=%0d write_commits=%0d", read_ack_count, write_commit_count);
		$finish;
	end

	always @(posedge clk) begin
		cycle_count <= cycle_count + 1;
		if (cycle_count > MAX_SIM_CYCLES) begin
			if (summary_fd != 0) begin
				$fdisplay(summary_fd, "TIMEOUT pc=%04x status=%02x ctrl=%02x track=%02x sector=%02x pos=%03x read_acks=%0d write_commits=%0d",
					dut.cpu_reg[79:64], dut.fdc_status_read, dut.fdc_ctrl, dut.fdc_track,
					dut.fdc_sector, dut.fdc_pos, read_ack_count, write_commit_count);
				$fflush(summary_fd);
			end
			$fatal(1, "DreamDisk production-config sim timed out");
		end
	end
endmodule
