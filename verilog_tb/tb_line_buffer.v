//==============================================================================
// Testbench:   tb_line_buffer
// Description: Unit tests for the line_buffer module using a compact 8-wide
//              x 4-row image so the full window behaviour fits within a short
//              simulation.
//
// Test image (row-major, unique values for easy tracing):
//
//   Row 0:  10  11  12  13  14  15  16  17
//   Row 1:  20  21  22  23  24  25  26  27
//   Row 2:  30  31  32  33  34  35  36  37
//   Row 3:  40  41  42  43  44  45  46  47
//
// Expected first valid window (centre pixel = row1,col1 = 21):
//
//   K0=10  K1=11  K2=12      row 0, cols 0-2
//   K3=20  K4=21  K5=22      row 1, cols 0-2
//   K6=30  K7=31  K8=32      row 2, cols 0-2
//
// Tests:
//   1. window_valid is LOW throughout rows 0 and 1.
//   2. window_valid is LOW for cols 0-1 of row 2.
//   3. First valid window at row2/col2 matches expected values.
//   4. Window shifts correctly as row 2 continues (cols 3 and 4).
//   5. window_valid goes LOW again at the start of row 3 (cols 0-1).
//   6. Valid window at row3/col2 uses the correct rotated rows.
//   7. Synchronous reset clears window_valid immediately.
//==============================================================================

`timescale 1ns / 1ps

module tb_line_buffer;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    localparam IMG_W      = 8;
    localparam CLK_HALF   = 5;   // 5 ns half-period = 100 MHz

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg  [7:0] pix_in;
    reg        pix_wr;
    reg [15:0] img_width;

    wire [71:0] window;
    wire        window_valid;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    line_buffer #(.IMG_WIDTH_MAX(16)) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .pix_in       (pix_in),
        .pix_wr       (pix_wr),
        .img_width    (img_width),
        .window       (window),
        .window_valid (window_valid)
    );

    //--------------------------------------------------------------------------
    // Clock
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always  #CLK_HALF clk = ~clk;

    //--------------------------------------------------------------------------
    // Pass / fail counters
    //--------------------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;

    //--------------------------------------------------------------------------
    // Task: write a single pixel and wait for the registered outputs to settle
    //--------------------------------------------------------------------------
    task write_pixel;
        input [7:0] val;
        begin
            @(negedge clk);
            pix_in = val;
            pix_wr = 1'b1;
            @(posedge clk);
            #1;                 // let registered outputs settle
            pix_wr = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: assert window_valid is LOW
    //--------------------------------------------------------------------------
    task expect_invalid;
        input [79:0] label;   // up to 10 ASCII characters
        begin
            if (window_valid !== 1'b0) begin
                $display("FAIL [%s] window_valid should be LOW", label);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%s] window_valid correctly LOW", label);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: assert window_valid is HIGH and check all 9 pixel slots
    //--------------------------------------------------------------------------
    task expect_window;
        input [7:0] k0,k1,k2, k3,k4,k5, k6,k7,k8;
        input [79:0] label;
        reg [71:0] expected;
        begin
            expected = {k0,k1,k2, k3,k4,k5, k6,k7,k8};
            if (window_valid !== 1'b1) begin
                $display("FAIL [%s] window_valid should be HIGH", label);
                fail_cnt = fail_cnt + 1;
            end else if (window !== expected) begin
                $display("FAIL [%s]", label);
                $display("       got      = %02h %02h %02h / %02h %02h %02h / %02h %02h %02h",
                    window[71:64], window[63:56], window[55:48],
                    window[47:40], window[39:32], window[31:24],
                    window[23:16], window[15: 8], window[ 7: 0]);
                $display("       expected = %02h %02h %02h / %02h %02h %02h / %02h %02h %02h",
                    k0,k1,k2, k3,k4,k5, k6,k7,k8);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%s] window = %02h %02h %02h / %02h %02h %02h / %02h %02h %02h",
                    label,
                    window[71:64], window[63:56], window[55:48],
                    window[47:40], window[39:32], window[31:24],
                    window[23:16], window[15: 8], window[ 7: 0]);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Test image storage
    //--------------------------------------------------------------------------
    reg [7:0] img [0:3][0:7];
    integer   row, col;

    initial begin
        img[0][0]=8'd10; img[0][1]=8'd11; img[0][2]=8'd12; img[0][3]=8'd13;
        img[0][4]=8'd14; img[0][5]=8'd15; img[0][6]=8'd16; img[0][7]=8'd17;

        img[1][0]=8'd20; img[1][1]=8'd21; img[1][2]=8'd22; img[1][3]=8'd23;
        img[1][4]=8'd24; img[1][5]=8'd25; img[1][6]=8'd26; img[1][7]=8'd27;

        img[2][0]=8'd30; img[2][1]=8'd31; img[2][2]=8'd32; img[2][3]=8'd33;
        img[2][4]=8'd34; img[2][5]=8'd35; img[2][6]=8'd36; img[2][7]=8'd37;

        img[3][0]=8'd40; img[3][1]=8'd41; img[3][2]=8'd42; img[3][3]=8'd43;
        img[3][4]=8'd44; img[3][5]=8'd45; img[3][6]=8'd46; img[3][7]=8'd47;
    end

    //--------------------------------------------------------------------------
    // Stimulus
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_line_buffer.vcd");
        $dumpvars(0, tb_line_buffer);

        pass_cnt  = 0;
        fail_cnt  = 0;
        pix_wr    = 1'b0;
        pix_in    = 8'd0;
        img_width = IMG_W;

        // ---- Reset ----------------------------------------------------------
        rst_n = 1'b0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;

        // =====================================================================
        // TEST 1 — window_valid stays LOW during rows 0 and 1
        // =====================================================================
        $display("\n--- TEST 1: window_valid LOW during fill rows (rows 0-1) ---");
        for (row = 0; row < 2; row = row + 1) begin
            for (col = 0; col < IMG_W; col = col + 1) begin
                write_pixel(img[row][col]);
                expect_invalid("fill    ");
            end
        end

        // =====================================================================
        // TEST 2 — window_valid still LOW for cols 0-1 of row 2
        // =====================================================================
        $display("\n--- TEST 2: window_valid LOW for first two pixels of row 2 ---");
        write_pixel(img[2][0]); expect_invalid("r2c0    ");
        write_pixel(img[2][1]); expect_invalid("r2c1    ");

        // =====================================================================
        // TEST 3 — First valid window at row 2, col 2
        // =====================================================================
        $display("\n--- TEST 3: First valid window at row2/col2 ---");
        write_pixel(img[2][2]);
        expect_window(
            8'd10, 8'd11, 8'd12,
            8'd20, 8'd21, 8'd22,
            8'd30, 8'd31, 8'd32,
            "r2c2    "
        );

        // =====================================================================
        // TEST 4 — Window slides right across row 2
        // =====================================================================
        $display("\n--- TEST 4: Window slides right (row 2, cols 3-4) ---");
        write_pixel(img[2][3]);
        expect_window(
            8'd11, 8'd12, 8'd13,
            8'd21, 8'd22, 8'd23,
            8'd31, 8'd32, 8'd33,
            "r2c3    "
        );

        write_pixel(img[2][4]);
        expect_window(
            8'd12, 8'd13, 8'd14,
            8'd22, 8'd23, 8'd24,
            8'd32, 8'd33, 8'd34,
            "r2c4    "
        );

        // Flush remaining pixels of row 2
        write_pixel(img[2][5]);
        write_pixel(img[2][6]);
        write_pixel(img[2][7]);

        // =====================================================================
        // TEST 5 — window_valid LOW again at the start of row 3
        // =====================================================================
        $display("\n--- TEST 5: window_valid LOW at start of row 3 ---");
        write_pixel(img[3][0]); expect_invalid("r3c0    ");
        write_pixel(img[3][1]); expect_invalid("r3c1    ");

        // =====================================================================
        // TEST 6 — Row buffer rotation: row 3 window uses rows 1, 2, 3
        // =====================================================================
        $display("\n--- TEST 6: Valid window at row3/col2 uses rotated buffers ---");
        write_pixel(img[3][2]);
        expect_window(
            8'd20, 8'd21, 8'd22,
            8'd30, 8'd31, 8'd32,
            8'd40, 8'd41, 8'd42,
            "r3c2    "
        );

        write_pixel(img[3][3]);
        expect_window(
            8'd21, 8'd22, 8'd23,
            8'd31, 8'd32, 8'd33,
            8'd41, 8'd42, 8'd43,
            "r3c3    "
        );

        // =====================================================================
        // TEST 7 — Synchronous reset clears window_valid
        // =====================================================================
        $display("\n--- TEST 7: Synchronous reset clears window_valid ---");
        @(negedge clk);
        rst_n = 1'b0;
        @(posedge clk); #1;
        expect_invalid("rst     ");
        rst_n = 1'b1;

        // =====================================================================
        // Summary
        // =====================================================================
        #20;
        $display("\n========================================");
        $display(" RESULTS: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("========================================");
        if (fail_cnt == 0)
            $display("*** ALL TESTS PASSED ***\n");
        else
            $display("*** %0d TEST(S) FAILED — review waveform ***\n", fail_cnt);

        $finish;
    end

endmodule
