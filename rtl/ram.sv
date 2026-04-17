module ram #(
    parameter int DATA_WIDTH     = 8,
    parameter int DEPTH          = 8,
    parameter int ADDRESS_WIDTH  = $clog2(DEPTH)
) (
    input logic clk,
    input logic rst,

    
    input  logic wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    input  logic wr_reset_ptr,
    
    input  logic rd_advance,
    input  logic rd_reset_ptr,
    output logic [DATA_WIDTH-1:0] rd_data
);

    logic [DATA_WIDTH-1:0] mem [DEPTH];
    logic [ADDRESS_WIDTH-1:0] rd_ptr, wr_ptr;

    assign rd_data = mem[rd_ptr];

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin

            if(wr_reset_ptr) wr_ptr <= '0;
            else if(wr_en) begin
                mem[wr_ptr] <= wr_data;
                if(wr_ptr == $bits(wr_ptr)'(DEPTH - 1)) wr_ptr <= '0;
                else wr_ptr <= wr_ptr + 1;
            end
        
            if(rd_reset_ptr) rd_ptr <= '0;
            else if(rd_advance) begin
                if(rd_ptr == $bits(rd_ptr)'(DEPTH - 1)) rd_ptr <= '0;
                else rd_ptr <= rd_ptr + 1;
            end
        end
    end
endmodule
