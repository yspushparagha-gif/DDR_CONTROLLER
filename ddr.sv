
module ddr_controller (
    input  logic         apb_clk,
    input  logic         ddr_clk,
    input  logic         reset_n,

    // APB interface
    input  logic         apb_write, 
    input  logic         apb_read,
    input  logic [31:0]  apb_addr,
    input  logic [127:0] apb_wdata,  //4 times means 2 cycles
    output logic [127:0] apb_rdata,
    output logic         apb_ready,

    // DRAM interface
    output logic         dram_wr_en,
    output logic         dram_rd_en,
    output logic [63:0]  dram_wdata,
    input  logic [63:0]  dram_rdata
);

    logic [255:0] write_buf; //buf means store the data without modifying it and sends to dram_write
    logic [255:0] read_buf;  //buf means store the data without modifying it and send to dram_read
    int apb_cnt;
    int wr_cnt;
    int rd_cnt;
    logic read_done;  // signal to indicate DDR read completed

    // ---------------- APB SIDE ----------------
    always_ff @(posedge apb_clk or negedge reset_n) begin //negedge means 1->0 initial value becomes 1
        if (!reset_n) begin //reset_n==0
            apb_rdata  <= 0;
            apb_ready  <= 0;
        end
        else begin
            apb_ready <= 0;

            if (apb_read && read_done) begin
                apb_rdata <= read_buf[127:0]; // first 128-bit slice, can expand to full 256-bit
                apb_ready <= 1;
            end
        end
    end

    // ---------------- APB WRITE ----------------
    always_ff @(posedge apb_clk or negedge reset_n) begin
        if (!reset_n) begin //reset_n==0
            write_buf  <= 0;
            apb_cnt    <= 0;
            dram_wr_en <= 0;
            wr_cnt     <= 0;
        end
        else if (apb_write) begin //abp_write==1
            write_buf[apb_cnt*128 +:128] <= apb_wdata;
            apb_cnt <= apb_cnt + 1;

            if (apb_cnt == 1) begin
                apb_cnt    <= 0;
                dram_wr_en <= 1;
                wr_cnt     <= 0;
            end
        end
    end

    // ---------------- DDR WRITE ----------------
    always_ff @(posedge ddr_clk) begin
        if (dram_wr_en) begin //ddr_wr_en==1  (writting a data in posedge -  128/2 =64 bit)
            dram_wdata <= write_buf[wr_cnt*64 +:64];
            wr_cnt <= wr_cnt + 1;
            if (wr_cnt == 4) dram_wr_en <= 0;
        end
    end

    always_ff @(negedge ddr_clk) begin
        if (dram_wr_en) begin //ddr_wr_en==1 (writting a data in negedge - remaining 64bit )
            dram_wdata <= write_buf[wr_cnt*64 +:64];
            wr_cnt <= wr_cnt + 1;
        end
    end

    // ---------------- DDR READ ----------------
    always_ff @(posedge ddr_clk) begin
        if (dram_rd_en) begin  //ddr_rd_en==1 ( reading a data in posdege - only 1st 64 bit)  
		$display("HARISH INSIDE DRAM dram=%h time=%d", dram_rdata , $time);
            read_buf[rd_cnt*64 +:64] <= dram_rdata;
            rd_cnt <= rd_cnt + 1;
            if (rd_cnt == 3) begin
                dram_rd_en <= 0;
                read_done  <= 1;
            end
        end
    end

    always_ff @(negedge ddr_clk) begin
        if (dram_rd_en) begin   //ddr_rd_en==1 (reading a data in negedge - remaning 64 bit)
		$display("HARISH INSIDE DRAM  dram =%h time=%d", dram_rdata, $time);
            read_buf[rd_cnt*64 +:64] <= dram_rdata;
            rd_cnt <= rd_cnt + 1;
        end
    end

    // ---------------- START READ ----------------
    always_ff @(posedge apb_clk or negedge reset_n) begin
        if (!reset_n) begin  //reset_n==0 ( 
            rd_cnt    <= 0;
            dram_rd_en <= 0;
            read_done  <= 0;
        end
        else if (apb_read) begin
            rd_cnt     <= 0;
            dram_rd_en <= 1;
            read_done  <= 0;
        end
    end

endmodule






module dram_model (
    input  logic        ddr_clk,
    input  logic        wr_en,
    input  logic        rd_en,
    input  logic [63:0] wdata,//64/4 =16 bit 
    output logic [63:0] rdata //64/4=16bit
);

    logic [255:0] mem; 
    int wr_cnt;
    int rd_cnt;

    // WRITE posedge + negedge
    always @(posedge ddr_clk) begin
        if (wr_en) begin
		@(negedge ddr_clk);
            mem[wr_cnt*64 +: 64] = wdata;
            wr_cnt = wr_cnt + 1;
        end
    end

    always @(negedge ddr_clk) begin
        if (wr_en) begin
		@(posedge ddr_clk);
            mem[wr_cnt*64 +: 64] = wdata;
            wr_cnt = wr_cnt + 1;
        end
    end

    // READ posedge + negedge
    always @(posedge ddr_clk) begin
        if (rd_en) begin
		@(negedge ddr_clk);
            rdata = mem[rd_cnt*64 +: 64];
            rd_cnt = rd_cnt + 1;
        end
    end

    always @(negedge ddr_clk) begin
        if (rd_en) begin
		@(posedge ddr_clk);
            rdata = mem[rd_cnt*64 +: 64];
            rd_cnt = rd_cnt + 1;
        end
    end

    // Reset counters
    always @(negedge wr_en) wr_cnt = 0;
    always @(negedge rd_en) rd_cnt = 0;

endmodule


module tb;

    // Clocks
    logic apb_clk = 0;
    logic ddr_clk = 0;

    always #5   apb_clk = ~apb_clk;
    always #2.5 ddr_clk = ~ddr_clk;

    // APB
    logic reset_n;
    logic apb_write;
    logic apb_read;
    logic [31:0]  apb_addr;
    logic [127:0] apb_wdata;
    logic [127:0] apb_rdata;
    logic apb_ready;

    // DRAM
    logic dram_wr_en;
    logic dram_rd_en;
    logic [63:0] dram_wdata;
    logic [63:0] dram_rdata;

    // DUT
    ddr_controller dut (
        .apb_clk    (apb_clk),
        .ddr_clk    (ddr_clk),
        .reset_n    (reset_n),
        .apb_write  (apb_write),
        .apb_read   (apb_read),
        .apb_addr   (apb_addr),
        .apb_wdata  (apb_wdata),
        .apb_rdata  (apb_rdata),
        .apb_ready  (apb_ready),
        .dram_wr_en (dram_wr_en),
        .dram_rd_en (dram_rd_en),
        .dram_wdata (dram_wdata),
        .dram_rdata (dram_rdata)
    );

    // DRAM
    dram_model dram (
        .ddr_clk (ddr_clk),
        .wr_en   (dram_wr_en),
        .rd_en   (dram_rd_en),
        .wdata   (dram_wdata),
        .rdata   (dram_rdata)
    );

    initial begin
        reset_n   = 0;
        apb_write = 0;
        apb_read  = 0;
        apb_addr  = 0;
        apb_wdata = 0;

        #20 reset_n = 1;

        // -------- WRITE (2 × 128-bit) --------
        @(posedge apb_clk);
        apb_write = 1;
        apb_addr  = 32'hAABB_CCDD;
        apb_wdata = 128'h1111_2222_3333_4444_5555_6666_7777_8888;

        @(posedge apb_clk);
        apb_wdata = 128'h9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000;

        @(posedge apb_clk);
        apb_write = 0;

        // -------- READ --------
        repeat (6) @(posedge apb_clk);
        apb_read = 1;
        @(posedge apb_clk);
        apb_read = 0;
        #50 $finish;
    end

endmodule


