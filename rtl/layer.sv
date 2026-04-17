module layer #(
    parameter int   INPUT_WIDTH      = 784,
    parameter int   PARALLEL_INPUTS  = 8,
    parameter int   PARALLEL_NEURONS = 8,
    parameter int   TOTAL_NEURONS    = 256,
    parameter int   NUM_CHUNKS       = (INPUT_WIDTH + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS,
    parameter int   REMAINDER        = TOTAL_NEURONS % PARALLEL_NEURONS,
    parameter logic DOWNSIZE         = PARALLEL_NEURONS > TOTAL_NEURONS
) (
    input  logic                              clk,
    input  logic                              rst,
    input  logic [       PARALLEL_INPUTS-1:0] input_data,
    input  logic                              valid_in,
    input  logic                              wr_en,
    input  logic [       PARALLEL_INPUTS-1:0] wr_weight_data,
    input  logic [                      31:0] wr_threshold_data,
    input  logic [$clog2(PARALLEL_NEURONS):0] np_id,
    input  logic                              weight_sel,
    output logic [      PARALLEL_NEURONS-1:0] result,
    output logic [   $clog2(INPUT_WIDTH+1):0] popcount         [PARALLEL_NEURONS],
    output logic [      PARALLEL_NEURONS-1:0] valid_out,
    output logic                              ready
);
    genvar i;

    //NP Inputs
    logic [                31:0] threshold      [PARALLEL_NEURONS];
    logic [ PARALLEL_INPUTS-1:0] weights        [PARALLEL_NEURONS];

    //NP Outputs
    logic [PARALLEL_NEURONS-1:0] valid_out_np;

    //IO Buffer Outputs
    logic [ PARALLEL_INPUTS-1:0] buf_data;
    logic [PARALLEL_NEURONS-1:0] buf_valid_out;
    logic                        buf_last;

    //Intermediate Signals
    logic                        wr_threshold_en[PARALLEL_NEURONS];
    logic                        wr_weight_en   [PARALLEL_NEURONS];

    assign valid_out = valid_out_np;

    io_buffer #(
        .INPUT_WIDTH     (INPUT_WIDTH),
        .PARALLEL_INPUTS (PARALLEL_INPUTS),
        .PARALLEL_NEURONS(PARALLEL_NEURONS),
        .TOTAL_NEURONS   (TOTAL_NEURONS)
    ) io_buf (
        .clk        (clk),
        .rst        (rst),
        .input_data (input_data),
        .valid_in   (valid_in),
        .output_data(buf_data),
        .valid_out  (buf_valid_out),
        .last       (buf_last),
        .ready      (ready)
    );

    generate
        for (i = 0; i < PARALLEL_NEURONS; i++) begin : neurons
            assign wr_threshold_en[i] = !weight_sel && wr_en && (np_id % $bits(np_id)'(PARALLEL_NEURONS) == i);
            assign wr_weight_en[i] = weight_sel && wr_en && (np_id % $bits(np_id)'(PARALLEL_NEURONS) == i);

            ram #(
                .DATA_WIDTH(PARALLEL_INPUTS),
                .DEPTH     (DOWNSIZE ? 32'(NUM_CHUNKS) : ((TOTAL_NEURONS / PARALLEL_NEURONS) + int'(i < REMAINDER)) * (NUM_CHUNKS))
            ) weight_ram (
                .clk         (clk),
                .rst         (rst),
                .wr_en       (wr_weight_en[i]),
                .wr_data     (wr_weight_data),
                .wr_reset_ptr(rst),
                .rd_advance  (buf_valid_out[i]),
                .rd_reset_ptr(rst),
                .rd_data     (weights[i])
            );

            ram #(
                .DATA_WIDTH($bits(threshold[i])),
                .DEPTH     (DOWNSIZE ? 32'(NUM_CHUNKS) : ((TOTAL_NEURONS / PARALLEL_NEURONS) + int'(i < REMAINDER)))
            ) threshold_ram (
                .clk         (clk),
                .rst         (rst),
                .wr_en       (wr_threshold_en[i]),
                .wr_data     (wr_threshold_data),
                .wr_reset_ptr(rst),
                .rd_advance  (valid_out_np[i]),
                .rd_reset_ptr(rst),
                .rd_data     (threshold[i])
            );

            neuron_processor #(
                .INPUT_WIDTH    (INPUT_WIDTH),
                .PARALLEL_INPUTS(PARALLEL_INPUTS)
            ) u_neuron (
                .clk      (clk),
                .rst      (rst),
                .weight   (weights[i]),
                .data     (buf_data),
                .threshold(threshold[i]),
                .valid_in (buf_valid_out[i]),
                .last     (buf_last),
                .popcount (popcount[i]),
                .valid_out(valid_out_np[i]),
                .result   (result[i])
            );
        end
    endgenerate

endmodule
