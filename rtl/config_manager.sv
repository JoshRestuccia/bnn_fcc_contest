module config_manager #(
    parameter int TOTAL_LAYERS                     = 4,
    parameter int CONFIG_BUS_WIDTH                 = 64,
    parameter int PARALLEL_INPUTS                  = 8,
    parameter int PARALLEL_NEURONS[TOTAL_LAYERS-1] = '{default: 8},
    parameter int MAX_P_W                          = 8,
    parameter int BYTES_PER_BEAT                   = CONFIG_BUS_WIDTH / 8,
    parameter int HEADER_BYTES                     = 16
) (
    input                                 clk,
    input                                 rst,
    input  logic                          config_valid,
    output logic                          config_ready,
    input  logic [  CONFIG_BUS_WIDTH-1:0] config_data,
    input  logic [CONFIG_BUS_WIDTH/8-1:0] config_keep,
    input  logic                          config_last,

    output logic                            wr_en,
    output logic [             MAX_P_W-1:0] wr_weight_data,
    output logic [                    31:0] wr_threshold_data,
    output logic [$clog2(TOTAL_LAYERS-1):0] layer_id,
    output logic [                    15:0] neuron_id,
    output logic                            weight_sel
);
    //Config beat signals
    logic [      CONFIG_BUS_WIDTH-1:0] beat_data_r;
    logic [        BYTES_PER_BEAT-1:0] beat_keep_r;
    logic                              beat_last_r;
    logic [$clog2(BYTES_PER_BEAT)-1:0] beat_byte_idx_r;
    logic                              beat_loaded_r;

    //Track single bytes
    logic [                       7:0] cur_byte;
    logic                              cur_byte_valid;

    //Header fields
    logic                              weight_sel_r;
    logic [                       7:0] layer_id_r;
    logic [                      15:0] layer_inputs_r;
    logic [                      15:0] bytes_per_neuron_r;
    logic [                      15:0] num_neurons_r;
    logic [                      31:0] total_bytes_r;

    //Tracking signals
    logic [                       4:0] header_byte_count_r;
    logic [                      31:0] payload_byte_count_r;
    logic [                      15:0] neuron_idx_r;
    logic [                      15:0] byte_idx_in_neuron_r;

    //Weight packer
    logic [                 MAX_P_W:0] weight_shift_r;
    logic [     $clog2(MAX_P_W+1)-1:0] weight_bit_count_r;
    logic [     $clog2(MAX_P_W+1)-1:0] p_w_r;
    logic                              weight_write;

    //Threshold packer
    logic [                      31:0] threshold_shift_r;
    logic [                       1:0] threshold_byte_count_r;
    logic                              threshold_write;

    typedef enum logic [2:0] {
        S_IDLE,
        S_READ_HEADER,
        S_STREAM_WEIGHTS,
        S_STREAM_THRESHOLDS
    } state_t;

    state_t state_r;

    assign layer_id = layer_id_r[$bits(layer_id)-1:0];
    assign neuron_id = neuron_idx_r;
    assign weight_sel = weight_sel_r;

    assign config_ready = !beat_loaded_r;

    assign cur_byte = beat_data_r[beat_byte_idx_r*8+:8];
    assign cur_byte_valid = beat_loaded_r && beat_keep_r[beat_byte_idx_r];

    assign threshold_write = threshold_byte_count_r == 2'd3 && state_r == S_STREAM_THRESHOLDS;
    assign weight_write = (weight_bit_count_r + 8 >= p_w_r) && state_r == S_STREAM_WEIGHTS;

    assign wr_en = (threshold_write || weight_write) && cur_byte_valid;

    assign wr_weight_data = weight_shift_r | (cur_byte << weight_bit_count_r);
    assign wr_threshold_data = {
        cur_byte, threshold_shift_r[23:16], threshold_shift_r[15:8], threshold_shift_r[7:0]
    };

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r            <= S_IDLE;
            weight_sel_r       <= '0;
            layer_id_r         <= '0;
            layer_inputs_r     <= '0;
            num_neurons_r      <= '0;
            bytes_per_neuron_r <= '0;
            total_bytes_r      <= '0;
            beat_byte_idx_r    <= '0;
            beat_loaded_r      <= '0;
        end else begin
            if (config_valid && config_ready) begin
                beat_data_r     <= config_data;
                beat_keep_r     <= config_keep;
                beat_last_r     <= config_last;
                beat_byte_idx_r <= '0;
                beat_loaded_r   <= 1'b1;
            end

            if (beat_loaded_r) begin
                case (state_r)
                    S_IDLE: begin
                        header_byte_count_r    <= '0;
                        payload_byte_count_r   <= '0;
                        neuron_idx_r           <= '0;
                        byte_idx_in_neuron_r   <= '0;
                        threshold_shift_r      <= '0;
                        threshold_byte_count_r <= '0;
                        weight_shift_r         <= '0;
                        weight_bit_count_r     <= '0;

                        weight_sel_r           <= !cur_byte[0];
                        header_byte_count_r    <= 1;
                        state_r                <= S_READ_HEADER;

                    end
                    S_READ_HEADER: begin
                        case (header_byte_count_r)
                            5'd1:  layer_id_r <= cur_byte;
                            5'd2:  layer_inputs_r[7:0] <= cur_byte;
                            5'd3:  layer_inputs_r[15:8] <= cur_byte;
                            5'd4:  num_neurons_r[7:0] <= cur_byte;
                            5'd5:  num_neurons_r[15:8] <= cur_byte;
                            5'd6:  bytes_per_neuron_r[7:0] <= cur_byte;
                            5'd7:  bytes_per_neuron_r[15:8] <= cur_byte;
                            5'd8:  total_bytes_r[7:0] <= cur_byte;
                            5'd9:  total_bytes_r[15:8] <= cur_byte;
                            5'd10: total_bytes_r[23:16] <= cur_byte;
                            5'd11: total_bytes_r[31:24] <= cur_byte;
                            default: begin
                            end
                        endcase

                        if (header_byte_count_r == $bits(header_byte_count_r)'(HEADER_BYTES - 1)) begin
                            payload_byte_count_r <= '0;
                            neuron_idx_r <= '0;
                            byte_idx_in_neuron_r <= '0;
                            threshold_byte_count_r <= '0;
                            weight_bit_count_r <= '0;
                            p_w_r <= layer_id_r == 0 ? $bits(
                                p_w_r
                            )'(PARALLEL_INPUTS) : $bits(
                                p_w_r
                            )'(PARALLEL_NEURONS[$clog2(
                                TOTAL_LAYERS
                            )'(layer_id_r)]);

                            if (weight_sel_r) state_r <= S_STREAM_WEIGHTS;
                            else state_r <= S_STREAM_THRESHOLDS;
                        end

                        header_byte_count_r <= header_byte_count_r + 1'b1;
                    end

                    S_STREAM_WEIGHTS: begin
                        weight_shift_r[weight_bit_count_r+:8] <= cur_byte;
                        weight_bit_count_r <= weight_bit_count_r + 8;

                        if (weight_bit_count_r + 8 >= p_w_r) begin
                            weight_shift_r     <= '0;
                            weight_bit_count_r <= '0;
                        end

                        if (byte_idx_in_neuron_r + 1 >= bytes_per_neuron_r) begin
                            neuron_idx_r         <= neuron_idx_r + 1'b1;
                            byte_idx_in_neuron_r <= '0;
                        end else begin
                            byte_idx_in_neuron_r <= byte_idx_in_neuron_r + 1'b1;
                        end

                        if (payload_byte_count_r + 1 >= total_bytes_r) begin
                            state_r <= S_IDLE;
                        end
                        payload_byte_count_r <= payload_byte_count_r + 1'b1;
                    end

                    S_STREAM_THRESHOLDS: begin
                        threshold_shift_r[threshold_byte_count_r*8+:8] <= cur_byte;

                        if (threshold_byte_count_r == 2'd3) begin
                            threshold_shift_r <= '0;
                            threshold_byte_count_r <= '0;

                            neuron_idx_r <= neuron_idx_r + 1'b1;
                        end else begin
                            threshold_byte_count_r <= threshold_byte_count_r + 1'b1;
                        end


                        if (payload_byte_count_r + 1 >= total_bytes_r) begin
                            state_r <= S_IDLE;
                        end
                        payload_byte_count_r <= payload_byte_count_r + 1'b1;
                    end

                    default: state_r <= S_IDLE;
                endcase
            end

            if (beat_byte_idx_r == $bits(beat_byte_idx_r)'(BYTES_PER_BEAT - 1)) begin
                beat_loaded_r   <= 1'b0;
                beat_byte_idx_r <= '0;
            end else begin
                if (beat_loaded_r) beat_byte_idx_r <= beat_byte_idx_r + 1'b1;
            end

        end
    end

endmodule
