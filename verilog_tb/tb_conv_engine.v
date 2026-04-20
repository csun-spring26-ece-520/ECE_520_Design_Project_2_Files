//==============================================================================
// Testbench:   tb_conv_engine
// Description: Unit tests for the conv_engine module covering all key
//              arithmetic behaviours.
//
// Test cases:
//   TC1  Box blur, uniform window        — basic MAC + SCALE=9
//   TC2  Box blur, mixed window          — general accumulator arithmetic
//   TC3  Sobel Gx, positive gradient     — signed coefficients, no overflow
//   TC4  Upper clamp: result > 255       — saturation + overflow flag
//   TC5  Lower clamp: result < 0         — saturation + overflow flag
//   TC6  Emboss bias: BIAS=128           — bias register behaviour
//   TC7  window_valid=0                  — output suppressed when invalid
//==============================================================================

`timescale 1ns / 1ps

module tb_conv_engine;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    localparam CLK_HALF = 5;   // 5 ns half-period = 100 MHz

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg [71:0] window;
    reg        window_valid;
    reg [71:0] kernel;
    reg  [7:0] scale;
    reg signed [8:0] bias;

    wire [7:0] pix_out;
    wire       pix_valid;
    wire       overflow;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    conv_engine dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .window       (window),
        .window_valid (window_valid),
        .kernel       (kernel),
        .scale        (scale),
        .bias         (bias),
        .pix_out      (pix_out),
        .pix_valid    (pix_valid),
        .overflow     (overflow)
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
    // Helper functions: pack 9 bytes into a 72-bit bus (K0=MSB, K8=LSB)
    //--------------------------------------------------------------------------
    function [71:0] pack9;
        input [7:0] b0,b1,b2,b3,b4,b5,b6,b7,b8;
        begin
            pack9 = {b0,b1,b2,b3,b4,b5,b6,b7,b8};
        end
    endfunction

    //--------------------------------------------------------------------------
    // Task: apply one set of inputs, clock one cycle, check outputs
    //--------------------------------------------------------------------------
    task run_and_check;
        input [71:0] win;
        input        win_valid;
        input [71:0] kern;
        input  [7:0] sc;
        input signed [8:0] b;
        input  [7:0] exp_pix;
        input        exp_overflow;
        input [127:0] label;
        begin
            @(negedge clk);
            window       = win;
            window_valid = win_valid;
            kernel       = kern;
            scale        = sc;
            bias         = b;

            @(posedge clk); #1;

            if (pix_valid !== win_valid) begin
                $display("FAIL [%s] pix_valid=%b expected=%b", label, pix_valid, win_valid);
                fail_cnt = fail_cnt + 1;
            end else if (win_valid && pix_out !== exp_pix) begin
                $display("FAIL [%s] pix_out=%0d expected=%0d  overflow=%b",
                         label, pix_out, exp_pix, overflow);
                fail_cnt = fail_cnt + 1;
            end else if (win_valid && overflow !== exp_overflow) begin
                $display("FAIL [%s] pix_out=%0d OK but overflow=%b expected=%b",
                         label, pix_out, overflow, exp_overflow);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%s] pix_out=%0d overflow=%b", label, pix_out, overflow);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Stimulus
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_conv_engine.vcd");
        $dumpvars(0, tb_conv_engine);

        pass_cnt     = 0;
        fail_cnt     = 0;
        window       = 72'd0;
        window_valid = 1'b0;
        kernel       = 72'd0;
        scale        = 8'd1;
        bias         = 9'sd0;

        // ---- Reset ----------------------------------------------------------
        rst_n = 1'b0;
        repeat(3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;

        $display("\n========================================");
        $display(" tb_conv_engine");
        $display("========================================");

        // =====================================================================
        // TC1: Box blur — uniform window, all pixels = 90
        //      kernel all 1s, scale = 9, bias = 0
        //      MAC = 9 * 90 = 810   scaled = 810 / 9 = 90
        // =====================================================================
        $display("\n--- TC1: Box blur, uniform window (all 90) ---");
        run_and_check(
            pack9(90,90,90, 90,90,90, 90,90,90), 1'b1,
            pack9(1,1,1, 1,1,1, 1,1,1),
            8'd9, 9'sd0,
            8'd90, 1'b0, "TC1_blur_uniform "
        );

        // =====================================================================
        // TC2: Box blur — mixed window
        //      pixels: 10 20 30 / 40 50 60 / 70 80 90
        //      MAC = 450   scaled = 450 / 9 = 50
        // =====================================================================
        $display("\n--- TC2: Box blur, mixed window ---");
        run_and_check(
            pack9(10,20,30, 40,50,60, 70,80,90), 1'b1,
            pack9(1,1,1, 1,1,1, 1,1,1),
            8'd9, 9'sd0,
            8'd50, 1'b0, "TC2_blur_mixed   "
        );

        // =====================================================================
        // TC3: Sobel Gx — gentle left-to-right gradient, no overflow
        //      kernel: -1  0 +1 / -2  0 +2 / -1  0 +1
        //      window:  0  0 50 /  0  0 50 /  0  0 50
        //      MAC = (1*50 + 2*50 + 1*50) = 200   no clamp
        //      Negative coefficients as 8-bit two's complement:
        //        -1 = 8'hFF,   -2 = 8'hFE
        // =====================================================================
        $display("\n--- TC3: Sobel Gx, gentle gradient (no overflow) ---");
        run_and_check(
            pack9(0,0,50,  0,0,50,  0,0,50), 1'b1,
            pack9(8'hFF,8'h00,8'h01,
                  8'hFE,8'h00,8'h02,
                  8'hFF,8'h00,8'h01),
            8'd1, 9'sd0,
            8'd200, 1'b0, "TC3_sobel_gx     "
        );

        // =====================================================================
        // TC4: Upper clamp — result > 255
        //      Sharpening kernel: 0 -1 0 / -1 5 -1 / 0 -1 0
        //      window: centre = 255, all neighbours = 0
        //      MAC = 5 * 255 = 1275   clamped to 255, overflow = 1
        // =====================================================================
        $display("\n--- TC4: Upper clamp (result > 255) ---");
        run_and_check(
            pack9(0,  0,  0,
                  0,255,  0,
                  0,  0,  0), 1'b1,
            pack9(8'h00,8'hFF,8'h00,
                  8'hFF,8'h05,8'hFF,
                  8'h00,8'hFF,8'h00),
            8'd1, 9'sd0,
            8'd255, 1'b1, "TC4_upper_clamp  "
        );

        // =====================================================================
        // TC5: Lower clamp — result < 0
        //      Sobel Gx, reversed gradient (large values on left, zeros on right)
        //      window: 200 0 0 / 200 0 0 / 200 0 0
        //      MAC = -200 + (-400) + (-200) = -800   clamped to 0, overflow = 1
        // =====================================================================
        $display("\n--- TC5: Lower clamp (result < 0) ---");
        run_and_check(
            pack9(200,0,0, 200,0,0, 200,0,0), 1'b1,
            pack9(8'hFF,8'h00,8'h01,
                  8'hFE,8'h00,8'h02,
                  8'hFF,8'h00,8'h01),
            8'd1, 9'sd0,
            8'd0, 1'b1, "TC5_lower_clamp  "
        );

        // =====================================================================
        // TC6: Emboss bias — uniform black window, BIAS = 128
        //      kernel: -2 -1 0 / -1 1 1 / 0 1 2   (sums to 1)
        //      window: all zeros
        //      MAC = 0   scaled = 0   biased = 0 + 128 = 128   no clamp
        // =====================================================================
        $display("\n--- TC6: Emboss bias (all-zero window + BIAS=128 -> 128) ---");
        run_and_check(
            pack9(0,0,0, 0,0,0, 0,0,0), 1'b1,
            pack9(8'hFE,8'hFF,8'h00,
                  8'hFF,8'h01,8'h01,
                  8'h00,8'h01,8'h02),
            8'd1, 9'sd128,
            8'd128, 1'b0, "TC6_emboss_bias  "
        );

        // =====================================================================
        // TC7: window_valid = 0 — output must be suppressed (pix_valid = 0)
        // =====================================================================
        $display("\n--- TC7: window_valid=0 suppresses output ---");
        run_and_check(
            pack9(200,200,200, 200,200,200, 200,200,200), 1'b0,
            pack9(1,1,1, 1,1,1, 1,1,1),
            8'd9, 9'sd0,
            8'd0, 1'b0, "TC7_win_invalid  "
        );
        // pix_valid check is inside run_and_check; for this case exp_pix is
        // irrelevant since win_valid=0 means we only verify pix_valid=0.

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
