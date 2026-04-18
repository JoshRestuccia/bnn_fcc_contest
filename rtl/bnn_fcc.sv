module bnn_fcc #(
    parameter int INPUT_DATA_WIDTH  = 8,
    parameter int INPUT_BUS_WIDTH   = 64,
    parameter int CONFIG_BUS_WIDTH  = 64,
    parameter int OUTPUT_DATA_WIDTH = 4,
    parameter int OUTPUT_BUS_WIDTH  = 8,

    parameter int TOTAL_LAYERS = 4,  // Includes input, hidden, and output
    parameter int TOPOLOGY[TOTAL_LAYERS] = '{
        0: 784,
        1: 256,
        2: 256,
        3: 10,
        default: 0
    },  // 0: input, TOTAL_LAYERS-1: output

    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[TOTAL_LAYERS-1] = '{default: 8}
) (
    input logic clk,
    input logic rst,

    // AXI streaming configuration interface (consumer)
    input  logic                          config_valid,
    output logic                          config_ready,
    input  logic [  CONFIG_BUS_WIDTH-1:0] config_data,
    input  logic [CONFIG_BUS_WIDTH/8-1:0] config_keep,
    input  logic                          config_last,

    // AXI streaming image input interface (consumer)
    input  logic                         data_in_valid,
    output logic                         data_in_ready,
    input  logic [  INPUT_BUS_WIDTH-1:0] data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0] data_in_keep,
    input  logic                         data_in_last,

    // AXI streaming classification output interface (producer)
    output logic                          data_out_valid,
    input  logic                          data_out_ready,
    output logic [  OUTPUT_BUS_WIDTH-1:0] data_out_data,
    output logic [OUTPUT_BUS_WIDTH/8-1:0] data_out_keep,
    output logic                          data_out_last
);
    localparam int LAYERS = TOTAL_LAYERS - 1;
    function automatic int get_max_parallel_inputs();
        int max_v = PARALLEL_INPUTS;
        for (int i = 0; i < LAYERS; i++) begin
            if (PARALLEL_NEURONS[i] > max_v) max_v = PARALLEL_NEURONS[i];
        end
        return max_v;
    endfunction

    localparam int MAX_PARALLEL_INPUTS = get_max_parallel_inputs();

    logic [          INPUT_DATA_WIDTH-1:0] pixels            [INPUT_BUS_WIDTH/INPUT_DATA_WIDTH];

    logic                                  bnn_ready;
    logic [           PARALLEL_INPUTS-1:0] bnn_data_in;
    logic                                  bnn_data_in_valid;
    logic [PARALLEL_NEURONS[LAYERS-1]-1:0] bnn_result;
    logic [PARALLEL_NEURONS[LAYERS-1]-1:0] bnn_valid_out;
    logic [$clog2(TOPOLOGY[LAYERS-2]+1):0] popcount         [PARALLEL_NEURONS[LAYERS-1]];

    //Config signals
    logic                                  config_wr_en;
    logic [       MAX_PARALLEL_INPUTS-1:0] wr_weight_data;
    logic [                          31:0] wr_threshold_data;
    logic [              $clog2(LAYERS):0] layer_id;
    logic [                          15:0] neuron_id;
    logic                                  weight_sel;

    assign pixels = {<<INPUT_DATA_WIDTH{data_in_data}};
    assign data_in_ready = bnn_ready && config_ready;

    always_ff @(posedge clk) begin : binarization
        if (data_in_ready) begin
            for (int i = 0; i < INPUT_BUS_WIDTH / INPUT_DATA_WIDTH; i++) bnn_data_in[i] <= pixels[i] >= 128;
            bnn_data_in_valid <= data_in_valid;
        end
    end

    config_manager #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .TOTAL_LAYERS    (TOTAL_LAYERS),
        .PARALLEL_INPUTS (PARALLEL_INPUTS),
        .PARALLEL_NEURONS(PARALLEL_NEURONS),
        .MAX_P_W         (MAX_PARALLEL_INPUTS)
    ) config_manager (
        .clk              (clk),
        .rst              (rst),
        .config_data      (config_data),
        .config_valid     (config_valid),
        .config_keep      (config_keep),
        .config_last      (config_last),
        .config_ready     (config_ready),
        .wr_en            (config_wr_en),
        .wr_weight_data   (wr_weight_data),
        .wr_threshold_data(wr_threshold_data),
        .layer_id         (layer_id),
        .neuron_id        (neuron_id),
        .weight_sel       (weight_sel)
    );

    bnn #(
        .LAYERS             (TOTAL_LAYERS - 1),
        .PARALLEL_INPUTS    (PARALLEL_INPUTS),
        .PARALLEL_NEURONS   (PARALLEL_NEURONS),
        .TOPOLOGY           (TOPOLOGY),
        .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS)
    ) u_bnn (
        .clk              (clk),
        .rst              (rst),
        .wr_en            (config_wr_en),
        .wr_weight_data   (wr_weight_data),
        .wr_threshold_data(wr_threshold_data),
        .weight_sel       (weight_sel),
        .np_id            (neuron_id[$clog2(MAX_PARALLEL_INPUTS):0]),
        .layer_id         (layer_id[$clog2(LAYERS):0]),
        .input_data       (bnn_data_in),
        .valid_in         (bnn_data_in_valid),
        .result           (bnn_result),
        .popcount         (popcount),
        .valid_out        (bnn_valid_out),
        .ready            (bnn_ready)
    );

    always_ff @(posedge clk) begin
        for(int i = 0; i < PARALLEL_NEURONS[LAYERS-1]; i++) begin
            if(bnn_valid_out[i]) begin
                $display("bnn_valid_out[%0d] = %b, popcount = %d", i, bnn_valid_out[i], popcount[i]);
            end
        end
    end

    argmax #(
        .TOTAL_OUTPUT_NEURONS(TOPOLOGY[LAYERS]),
        .PARALLEL_OUTPUT_NEURONS(PARALLEL_NEURONS[LAYERS-1]),
        .POPCOUNT_WIDTH($clog2(TOPOLOGY[LAYERS-1]+1)),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) u_argmax (
        .clk(clk),
        .rst(rst),
        .popcount(popcount),
        .valid_in(bnn_valid_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready),
        .data_out_data(data_out_data),
        .data_out_keep(data_out_keep),
        .data_out_last(data_out_last)
    );

endmodule
