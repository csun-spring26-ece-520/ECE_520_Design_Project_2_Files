//==============================================================================
// Testbench:   tb_image_filter
// Description: Top-level simulation testbench for the complete image
//              processing pipeline.
//
// Hierarchy exercised:
//   tb_image_filter
//   └── image_filter          (top-level DUT)
//       ├── line_buffer
//       └── conv_engine
//
// Flow:
//   1. Reads image_in.hex  into pixel memory via $readmemh.
//   2. Reads image_info.txt (width, height) via $fscanf.
//   3. Configures the kernel, scale, and bias for the selected FILTER.
//   4. Streams every pixel through image_filter in raster order.
//   5. Captures pix_out whenever pix_valid is asserted.
//   6. Writes the filtered pixels to image_out.hex (one 2-digit hex per line).
//      Border pixels (top 2 rows, left 2 columns) that have no valid window
//      are filled with the original pixel value to preserve image dimensions.
//
// Filter selection:
//   Set the FILTER parameter at compile / elaboration time.
//
//   FILTER value  | Description
//   --------------|------------------------------------
//   "BLUR"        | 3x3 box blur  (scale=9, bias=0)
//   "INVERT"      | Intensity invert - bypass mode
//   "SOBEL_X"     | Sobel horizontal gradient Gx
//   "SOBEL_Y"     | Sobel vertical gradient Gy
//   "SHARPEN"     | Unsharp sharpening
//   "EMBOSS"      | Emboss with bias=128
//
// Prerequisites:
//   image_in.hex   and  image_info.txt  must exist in the simulation
//   working directory.  Generate them with:
//     python image_to_hex.py <image> --width W --height H
//==============================================================================

`timescale 1ns / 1ps

module tb_image_filter;

    // =========================================================================
    // Compile-time filter selection
    // =========================================================================
    parameter FILTER = "BLUR";

    // =========================================================================
    // File paths (relative to simulation working directory)
    // =========================================================================
    localparam INPUT_HEX  = "image_in.hex";
    localparam OUTPUT_HEX = "image_out.hex";
    localparam INFO_FILE  = "image_info.txt";

    // Maximum image size (pixels) for memory allocation
    localparam MAX_PIXELS = 640 * 480;

    // =========================================================================
    // Clock
    // =========================================================================
    localparam CLK_HALF = 5;   // 5 ns → 100 MHz
    reg clk = 1'b0;
    always #CLK_HALF clk = ~clk;

    // =========================================================================
    // DUT port signals
    // =========================================================================
    reg        rst_n;
    reg  [7:0] pix_in;
    reg        pix_wr;
    reg [15:0] img_width;
    reg [71:0] kernel;
    reg  [7:0] scale;
    reg signed [8:0] bias;

    wire [7:0] pix_out;
    wire       pix_valid;
    wire       overflow;

    // =========================================================================
    // DUT instantiation - image_filter is the top-level under test
    // =========================================================================
    image_filter #(
        .IMG_WIDTH_MAX (640)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .pix_in    (pix_in),
        .pix_wr    (pix_wr),
        .img_width (img_width),
        .kernel    (kernel),
        .scale     (scale),
        .bias      (bias),
        .pix_out   (pix_out),
        .pix_valid (pix_valid),
        .overflow  (overflow)
    );

    // =========================================================================
    // Pixel memories
    // =========================================================================
    reg [7:0] pix_mem_in  [0:MAX_PIXELS-1];   // input image
    reg [7:0] pix_mem_out [0:MAX_PIXELS-1];   // filtered output

    // Initialise output memory to 0 so that unwritten entries produce a
    // valid hex value (00) rather than xx in the output file.
    integer init_i;
    initial begin
        for (init_i = 0; init_i < MAX_PIXELS; init_i = init_i + 1)
            pix_mem_out[init_i] = 8'h00;
    end

    // =========================================================================
    // Output pixel capture (driven by pix_valid from conv_engine)
    // =========================================================================
    integer out_idx;

    always @(posedge clk) begin
        if (!rst_n) begin
            out_idx <= 0;
        end else if (pix_valid) begin
            pix_mem_out[out_idx] <= pix_out;
            out_idx              <= out_idx + 1;
        end
    end

    // =========================================================================
    // Task: configure kernel, scale, and bias for the selected filter
    // =========================================================================
    task configure_filter;
        begin
            case (FILTER)
                "BLUR" : begin
                    $display("[tb] Filter: BOX BLUR  (scale=9, bias=0)");
                    // All coefficients = 1, divide by 9
                    kernel = {8'd1,8'd1,8'd1, 8'd1,8'd1,8'd1, 8'd1,8'd1,8'd1};
                    scale  = 8'd9;
                    bias   = 9'sd0;
                end

                "SOBEL_X" : begin
                    $display("[tb] Filter: SOBEL Gx  (scale=1, bias=0)");
                    // -1  0 +1 / -2  0 +2 / -1  0 +1
                    kernel = {8'hFF,8'h00,8'h01,
                              8'hFE,8'h00,8'h02,
                              8'hFF,8'h00,8'h01};
                    scale  = 8'd1;
                    bias   = 9'sd0;
                end

                "SOBEL_Y" : begin
                    $display("[tb] Filter: SOBEL Gy  (scale=1, bias=0)");
                    // +1 +2 +1 /  0  0  0 / -1 -2 -1
                    kernel = {8'h01,8'h02,8'h01,
                              8'h00,8'h00,8'h00,
                              8'hFF,8'hFE,8'hFF};
                    scale  = 8'd1;
                    bias   = 9'sd0;
                end

                "SHARPEN" : begin
                    $display("[tb] Filter: SHARPEN  (scale=1, bias=0)");
                    //  0 -1  0 / -1 +5 -1 /  0 -1  0
                    kernel = {8'h00,8'hFF,8'h00,
                              8'hFF,8'h05,8'hFF,
                              8'h00,8'hFF,8'h00};
                    scale  = 8'd1;
                    bias   = 9'sd0;
                end

                "EMBOSS" : begin
                    $display("[tb] Filter: EMBOSS  (scale=1, bias=128)");
                    // -2 -1  0 / -1 +1 +1 /  0 +1 +2
                    kernel = {8'hFE,8'hFF,8'h00,
                              8'hFF,8'h01,8'h01,
                              8'h00,8'h01,8'h02};
                    scale  = 8'd1;
                    bias   = 9'sd128;
                end

                default : begin  // "INVERT" and anything else
                    $display("[tb] Filter: INVERT  (passthrough, computed in TB)");
                    kernel = 72'd0;
                    scale  = 8'd1;
                    bias   = 9'sd0;
                end
            endcase
        end
    endtask

    // =========================================================================
    // Main stimulus
    // =========================================================================
    integer img_width_i;
    integer img_height_i;
    integer total_pixels;
    integer fd_info;
    integer fd_out;
    integer scan_ret;
    integer row, col, pix_idx;
    integer i;

    initial begin
        // ---- Initialise signals ---------------------------------------------
        rst_n    = 1'b0;
        pix_wr   = 1'b0;
        pix_in   = 8'd0;
        img_width = 16'd0;
        kernel   = 72'd0;
        scale    = 8'd1;
        bias     = 9'sd0;

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ---- Read image dimensions ------------------------------------------
        fd_info = $fopen(INFO_FILE, "r");
        if (fd_info == 0) begin
            $display("[tb] ERROR: Cannot open '%s'. Run image_to_hex.py first.", INFO_FILE);
            $finish;
        end
        scan_ret = $fscanf(fd_info, "%d\n%d\n", img_width_i, img_height_i);
        $fclose(fd_info);

        total_pixels = img_width_i * img_height_i;
        img_width    = img_width_i[15:0];

        $display("[tb] Image: %0d x %0d  (%0d pixels)", img_width_i, img_height_i, total_pixels);

        // ---- Load input image -----------------------------------------------
        $readmemh(INPUT_HEX, pix_mem_in);
        $display("[tb] Loaded '%s'", INPUT_HEX);

        // ---- Configure filter -----------------------------------------------
        configure_filter();

        // ---- Stream pixels through the pipeline ----------------------------
        $display("[tb] Streaming pixels ...");
        pix_idx = 0;

        for (row = 0; row < img_height_i; row = row + 1) begin
            for (col = 0; col < img_width_i; col = col + 1) begin

                if (FILTER == "INVERT") begin
                    // Invert is pointwise - compute directly, no need to feed
                    // the convolution pipeline.
                    pix_mem_out[pix_idx] = 8'hFF - pix_mem_in[pix_idx];
                end else begin
                    // Write pixel into image_filter on a negative clock edge
                    // so it is stable when sampled on the next rising edge.
                    @(negedge clk);
                    pix_in <= pix_mem_in[pix_idx];
                    pix_wr <= 1'b1;
                    @(posedge clk); #1;
                    pix_wr <= 1'b0;
                end

                pix_idx = pix_idx + 1;
            end
        end

        // ---- Flush pipeline (line_buffer + conv_engine latency) -------------
        repeat(8) @(posedge clk);

        $display("[tb] Stream complete.  Convolution outputs captured: %0d", out_idx);

        // ---- Write output hex file ------------------------------------------
        // The convolution pipeline does not produce output for the top 2 rows
        // and left 2 columns (the line_buffer fill period).  For those border
        // positions we copy the original pixel so the output image is the same
        // size as the input.
        //
        // Valid conv outputs are indexed from 0 and correspond to image
        // position (row=2, col=2) onward, so:
        //   out_mem index = (row - 2) * img_width + (col - 2)

        fd_out = $fopen(OUTPUT_HEX, "w");
        if (fd_out == 0) begin
            $display("[tb] ERROR: Cannot create '%s'.", OUTPUT_HEX);
            $finish;
        end

        for (i = 0; i < total_pixels; i = i + 1) begin
            row = i / img_width_i;
            col = i % img_width_i;

            if (FILTER == "INVERT") begin
                $fdisplay(fd_out, "%02X", pix_mem_out[i]);
            end else if (row < 2 || col < 2) begin
                // Border: no valid window - use original pixel
                $fdisplay(fd_out, "%02X", pix_mem_in[i]);
            end else begin
                $fdisplay(fd_out, "%02X", pix_mem_out[(row - 2) * img_width_i + (col - 2)]);
            end
        end

        $fclose(fd_out);
        $display("[tb] Wrote '%s'", OUTPUT_HEX);
        $display("[tb] Done.");
        $finish;
    end

endmodule
