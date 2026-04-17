module io_buffer #(
    parameter int INPUT_WIDTH      = 784,
    parameter int PARALLEL_INPUTS  = 8,
    parameter int PARALLEL_NEURONS = 8,
    parameter int TOTAL_NEURONS    = 256,
    parameter int NUM_CHUNKS       = (INPUT_WIDTH + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS,
    parameter int ITERATIONS       = (TOTAL_NEURONS + PARALLEL_NEURONS - 1) / PARALLEL_NEURONS,
    parameter int PADDED_INPUT_WIDTH = (NUM_CHUNKS * PARALLEL_INPUTS)
) (
    input  logic                        clk,
    input  logic                        rst,
    input  logic [ PARALLEL_INPUTS-1:0] input_data,
    input  logic                        valid_in,
    output logic [ PARALLEL_INPUTS-1:0] output_data,
    output logic [PARALLEL_NEURONS-1:0] valid_out,
    output logic                        last,
    output logic                        ready
);
    typedef enum logic [1:0] {
        S_LOAD,
        S_REPLAY
    } state_t;

    state_t state_r;

    logic [PADDED_INPUT_WIDTH-1:0] input_buffer;

    logic [$clog2(NUM_CHUNKS):0] load_count;
    logic [$clog2(NUM_CHUNKS):0] replay_count;
    logic [$clog2(ITERATIONS):0] iteration_count;

    always_comb begin
        output_data = '0;
        valid_out   = '0;
        last        = 1'b0;
        ready       = 1'b1;

        case (state_r)
            S_REPLAY: begin
                output_data = input_buffer[replay_count*PARALLEL_INPUTS-1-:PARALLEL_INPUTS];
                last = (replay_count == $bits(replay_count)'(1));
                ready = 1'b0;

                //Handle valid_out if PARALLEL_NEURONS is not a factor of TOTAL_NEURONS
                if(iteration_count == $bits(iteration_count)'(ITERATIONS - 1)) begin
                    if(TOTAL_NEURONS%PARALLEL_NEURONS == 0) begin
                        valid_out = '1;
                    end else begin
                        valid_out = '1 >> (PARALLEL_NEURONS - (TOTAL_NEURONS%PARALLEL_NEURONS));
                    end
                end else begin
                    valid_out = '1;
                end
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r         <= S_LOAD;
            load_count      <= $bits(load_count)'(NUM_CHUNKS);
            replay_count    <= $bits(replay_count)'(NUM_CHUNKS);
            iteration_count <= '0;
            input_buffer    <= '0;
        end else begin
            case (state_r)
                S_LOAD: begin
                    if (valid_in) begin
                        input_buffer[load_count*PARALLEL_INPUTS-1-:PARALLEL_INPUTS] <= input_data;

                        if (load_count == $bits(load_count)'(1)) begin
                            load_count      <= $bits(load_count)'(NUM_CHUNKS);
                            replay_count    <= $bits(replay_count)'(NUM_CHUNKS);
                            iteration_count <= '0;
                            state_r         <= S_REPLAY;
                        end else begin
                            load_count <= load_count - 1'b1;
                        end
                    end
                end

                S_REPLAY: begin
                    if (replay_count == $bits(replay_count)'(1)) begin
                        replay_count <= $bits(replay_count)'(NUM_CHUNKS);

                        if (iteration_count == $bits(iteration_count)'(ITERATIONS - 1)) begin
                            iteration_count <= '0;
                            state_r         <= S_LOAD;
                        end else begin
                            iteration_count <= iteration_count + 1'b1;
                        end
                    end else begin
                        replay_count <= replay_count - 1'b1;
                    end
                end

                default: begin
                    state_r <= S_LOAD;
                end
            endcase
        end
    end

endmodule
