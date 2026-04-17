module neuron_processor #(
    parameter int INPUT_WIDTH = 8,
    parameter int PARALLEL_INPUTS = 8
) (
    input logic clk,
    input logic rst,

    input logic [      PARALLEL_INPUTS-1:0] weight,
    input logic [      PARALLEL_INPUTS-1:0] data,
    input logic [                     31:0] threshold,
    input logic                             valid_in,
    input logic                             last,

    output logic [$clog2(INPUT_WIDTH+1):0] popcount,
    output logic                           valid_out,
    output logic                           result
);
    logic [$clog2(INPUT_WIDTH+1):0] accum_r;
    logic [$clog2(INPUT_WIDTH+1):0] popcount_r;
    logic                           valid_out_r;

    assign popcount  = popcount_r;
    assign valid_out = valid_out_r;

    assign result    = (valid_out_r && $bits(threshold)'(popcount_r) >= threshold) ? 1'b1 : 1'b0;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out_r <= 1'b0;
            popcount_r  <= '0;
            accum_r     <= '0;
        end else begin
            valid_out_r <= valid_in && last;

            if (valid_in) accum_r <= $countones(~(weight ^ data)) + accum_r;

            if (valid_in && last) begin
                popcount_r <= $countones(~(weight ^ data)) + accum_r;
                accum_r    <= '0;
            end
        end
    end
endmodule
