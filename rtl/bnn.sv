module bnn #(
    parameter int TOTAL_LAYERS = 4,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[TOTAL_LAYERS] = '{default: 8},
    parameter int TOPOLOGY[TOTAL_LAYERS] = '{0: 784, 1: 256, 2: 256, 3: 10, default: 0},
    parameter int MAX_PARALLEL_INPUTS = 8
) (
    input  logic                                        clk,
    input  logic                                        rst,
    input  logic                                        wr_en,
    input  logic [             MAX_PARALLEL_INPUTS-1:0] wr_weight_data,
    input  logic [                                31:0] wr_threshold_data,
    input  logic                                        weight_sel,
    input  logic [       $clog2(MAX_PARALLEL_INPUTS):0] np_id,
    input  logic [              $clog2(TOTAL_LAYERS):0] layer_id,
    input  logic [                 PARALLEL_INPUTS-1:0] input_data,
    input  logic                                        valid_in,
    output logic [PARALLEL_NEURONS[TOTAL_LAYERS-1]-1:0] result,
    output logic [$clog2(TOPOLOGY[TOTAL_LAYERS-2]+1):0] popcount         [PARALLEL_NEURONS[TOTAL_LAYERS-1]],
    output logic [PARALLEL_NEURONS[TOTAL_LAYERS-1]-1:0] valid_out,
    output logic                                        ready
);

    logic [MAX_PARALLEL_INPUTS-1:0] layer_input_data[TOTAL_LAYERS];
    logic                           layer_valid_in  [TOTAL_LAYERS];
    logic [MAX_PARALLEL_INPUTS-1:0] layer_result    [TOTAL_LAYERS];
    logic [MAX_PARALLEL_INPUTS-1:0] layer_valid_out [TOTAL_LAYERS];
    logic                           layer_wr_en     [TOTAL_LAYERS];

    genvar i;

    assign layer_input_data[0]  = input_data;
    assign layer_valid_in[0]    = valid_in;

    generate
        for (i = 0; i < TOTAL_LAYERS; i++) begin : g_layers
            assign layer_wr_en[i] = wr_en && (layer_id == i);

            if (i > 0) begin : data_pass
                assign layer_input_data[i] = layer_result[i-1];
                assign layer_valid_in[i]   = |layer_valid_out[i-1];
            end

            if (i == 0) begin : g_input_layer
                logic [$clog2(TOPOLOGY[i]+1):0] unused_popcount[PARALLEL_NEURONS[i]];

                layer #(
                    .PARALLEL_INPUTS (PARALLEL_INPUTS),
                    .PARALLEL_NEURONS(PARALLEL_NEURONS[i]),
                    .INPUT_WIDTH     (TOPOLOGY[0]),
                    .TOTAL_NEURONS   (TOPOLOGY[i])
                ) layer (
                    .clk              (clk),
                    .rst              (rst),
                    .input_data       (PARALLEL_INPUTS'(layer_input_data[i])),
                    .valid_in         (layer_valid_in[i]),
                    .wr_en            (layer_wr_en[i]),
                    .wr_weight_data   (PARALLEL_INPUTS'(wr_weight_data)),
                    .wr_threshold_data(wr_threshold_data),
                    .np_id            (np_id[$clog2(PARALLEL_NEURONS[i]):0]),
                    .weight_sel       (weight_sel),
                    .result           (layer_result[i][PARALLEL_NEURONS[i]-1:0]),
                    .popcount         (unused_popcount),
                    .valid_out        (layer_valid_out[i][PARALLEL_NEURONS[i]-1:0]),
                    .ready            (ready)
                );
            end else if (i < TOTAL_LAYERS - 1) begin : g_hidden_layer
                logic [$clog2(TOPOLOGY[i-1]+1):0] unused_popcount[PARALLEL_NEURONS[i]];
                logic unused_ready;

                layer #(
                    .PARALLEL_INPUTS (PARALLEL_NEURONS[i-1]),
                    .PARALLEL_NEURONS(PARALLEL_NEURONS[i]),
                    .INPUT_WIDTH     (TOPOLOGY[i-1]),
                    .TOTAL_NEURONS   (TOPOLOGY[i])
                ) layer (
                    .clk              (clk),
                    .rst              (rst),
                    .input_data       (PARALLEL_NEURONS[i-1]'(layer_input_data[i])),
                    .valid_in         (layer_valid_in[i]),
                    .wr_en            (layer_wr_en[i]),
                    .wr_weight_data   (PARALLEL_NEURONS[i-1]'(wr_weight_data)),
                    .wr_threshold_data(wr_threshold_data),
                    .np_id            (np_id[$clog2(PARALLEL_NEURONS[i]):0]),
                    .weight_sel       (weight_sel),
                    .result           (layer_result[i][PARALLEL_NEURONS[i]-1:0]),
                    .popcount         (unused_popcount),
                    .valid_out        (layer_valid_out[i][PARALLEL_NEURONS[i]-1:0]),
                    .ready            (unused_ready)
                );
            end else begin : g_output_layer
                logic unused_ready;

                layer #(
                    .PARALLEL_INPUTS (PARALLEL_NEURONS[i-1]),
                    .PARALLEL_NEURONS(PARALLEL_NEURONS[i]),
                    .INPUT_WIDTH     (TOPOLOGY[i-1]),
                    .TOTAL_NEURONS   (TOPOLOGY[i])
                ) layer (
                    .clk              (clk),
                    .rst              (rst),
                    .input_data       (PARALLEL_NEURONS[i-1]'(layer_input_data[i])),
                    .valid_in         (layer_valid_in[i]),
                    .wr_en            (layer_wr_en[i]),
                    .wr_weight_data   (PARALLEL_NEURONS[i-1]'(wr_weight_data)),
                    .wr_threshold_data(wr_threshold_data),
                    .np_id            (np_id[$clog2(PARALLEL_NEURONS[i]):0]),
                    .weight_sel       (weight_sel),
                    .result           (result),
                    .popcount         (popcount),
                    .valid_out        (valid_out),
                    .ready            (unused_ready)
                );
            end
        end
    endgenerate

endmodule
