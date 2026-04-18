module argmax #(
    parameter int TOTAL_OUTPUT_NEURONS = 10,
    parameter int PARALLEL_OUTPUT_NEURONS = 10,
    parameter int POPCOUNT_WIDTH = 10,
    parameter int OUTPUT_BUS_WIDTH = 8,
    parameter int NUM_BEATS = (TOTAL_OUTPUT_NEURONS + PARALLEL_OUTPUT_NEURONS - 1) / PARALLEL_OUTPUT_NEURONS
) (
    input logic                               clk,
    input logic                               rst,
    input logic [           POPCOUNT_WIDTH:0] popcount[PARALLEL_OUTPUT_NEURONS],
    input logic [PARALLEL_OUTPUT_NEURONS-1:0] valid_in,

    output logic                          data_out_valid,
    input  logic                          data_out_ready,
    output logic [  OUTPUT_BUS_WIDTH-1:0] data_out_data,
    output logic [OUTPUT_BUS_WIDTH/8-1:0] data_out_keep,
    output logic                          data_out_last
);

    logic [                POPCOUNT_WIDTH:0] max_popcount_r;
    logic [$clog2(TOTAL_OUTPUT_NEURONS)-1:0] max_neuron_r;

    logic [                POPCOUNT_WIDTH:0] beat_max_popcount;
    logic [$clog2(TOTAL_OUTPUT_NEURONS)-1:0] beat_max_neuron;

    logic [             $clog2(NUM_BEATS):0] beat_count_r;
    logic                                    beat_has_valid;

    assign data_out_keep  = {(OUTPUT_BUS_WIDTH / 8) {1'b1}};
    assign data_out_valid = beat_count_r >= $bits(beat_count_r)'(NUM_BEATS);
    assign data_out_last  = data_out_valid;
    assign data_out_data  = $bits(data_out_data)'(max_neuron_r);

    always_comb begin
        beat_max_popcount = '0;
        beat_max_neuron   = '0;
        beat_has_valid    = 1'b0;

        for (int i = 0; i < PARALLEL_OUTPUT_NEURONS; i++) begin
            if (valid_in[i] && ((beat_count_r * PARALLEL_OUTPUT_NEURONS + i) < TOTAL_OUTPUT_NEURONS)) begin
                if (!beat_has_valid || (popcount[i] > beat_max_popcount)) begin
                    beat_has_valid    = 1'b1;
                    beat_max_popcount = popcount[i];
                    beat_max_neuron   = i[$bits(beat_max_neuron)-1:0];
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            max_popcount_r <= '0;
            max_neuron_r   <= '0;
            beat_count_r   <= '0;
        end else begin
            if(data_out_ready && data_out_valid) begin
                max_popcount_r <= '0;
                max_neuron_r   <= '0;
                beat_count_r   <= '0;
            end else if (!data_out_valid) begin
                if (beat_max_popcount > max_popcount_r) begin
                    max_popcount_r <= beat_max_popcount;
                    max_neuron_r <= beat_max_neuron + $bits(max_neuron_r)'(beat_count_r * PARALLEL_OUTPUT_NEURONS);
                end

                beat_count_r <= beat_count_r + 1'b1;
            end
            
        end
    end

endmodule
