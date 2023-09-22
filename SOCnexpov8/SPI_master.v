
module SPI_master(
  input clk,
  input rst,
  // interfaz con el mundo externo
  input start,
  output busy,
  output done,
  input [7:0] D_in,
  output [7:0] D_out,
  // señal de configuracion
  input CPOL,     
  input CPHA,     
  input MSBfirst,
  // interfaz SPI
  input  MISO,
  output MOSI,
  output SCLK,
  output SS // TODO posiblemente cambiarlo
);
  // modo 0: CPOL = 0 CPHA = 0 
    //div[1] =0|00|11|00|11|00|11|00|11|00|11|00|11|00|11|00|11|000000...
    //div[0] = |01|01|01|01|01|01|01|01|01|01|01|01|01|01|01|01|000000...
    //count  = -- 0 -|--1--|--2--|--3--|--4--|--5--|--6--|--7--|--0---...
    //slck   =____↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|______...
    //mosi   = |- d7-|- d6-|- d5-|- d4-|- d3-|- d2-|- d1-|- d0-|- xxx-...
  
  // modo 1: CPOL = 0 CPHA = 1 
    //div[1] =0|00|11|00|11|00|11|00|11|00|11|00|11|00|11|00|11|000000...
    //div[0] = |01|01|01|01|01|01|01|01|01|01|01|01|01|01|01|01|000000...
    //count  = -- 0 --|--1--|--2--|--3--|--4--|--5--|--6--|--7--|--0--...
    //slck   =____|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓______...
    //mosi   = |-- d7 --|- d6-|- d5-|- d4-|- d3-|- d2-|- d1-|- d0-|- xxx-...

  // modo 2: CPOL = 1 CPHA = 0 
    //div[1] =0|00|11|00|11|00|11|00|11|00|11|00|11|00|11|00|11|000000...
    //div[0] = |01|01|01|01|01|01|01|01|01|01|01|01|01|01|01|01|000000...
    //count  =--0--|--1--|--2--|--3--|--4--|--5--|--6--|--7--|--0---...
    //slck   =¯¯¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯↓__|¯¯¯¯¯¯...
    //mosi   = |- d7-|- d6-|- d5-|- d4-|- d3-|- d2-|- d1-|- d0-|- xxx-...

  // modo 3: CPOL = 1 CPHA = 1 
    //div[1] =0|00|11|00|11|00|11|00|11|00|11|00|11|00|11|00|11|000000...
    //div[0] = |01|01|01|01|01|01|01|01|01|01|01|01|01|01|01|01|000000...
    //count  = -- 0 --|--1--|--2--|--3--|--4--|--5--|--6--|--7--|--0---...
    //slck   =¯¯¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯|__↑¯¯¯¯¯¯...
    //mosi   = |-- d7 --|- d6-|- d5-|- d4-|- d3-|- d2-|- d1-|- d0-|-x xxx-...

  reg [1:0] state,nextState;
  localparam S_inicio   = 0;
  localparam S_bajoSCLK = 1;
  localparam S_altoSCLK = 2;
  localparam S_detenido = 3;
  
  //-- FSM
  always @(posedge clk)
    if (rst)
      state <= S_inicio;
    else 
      state <= nextState;
  //---------------------
  
  //-- logica combinacional para el estado actual
  reg shift, load, nextcount, stop_SCKL;
  
  //--- divisor de frecuencia div[1],div[0]
  reg [1:0] div;
  always @(posedge clk)
    if (stop_SCKL)
      div <= 2'b0;
    else // o si ocurre overflow de un divisor externo (TODO)
      div <= div+1;
  //--------------------

  //-- indicador de Overflow
  wire change = (div[0]==1);
  
  //-- Registro de desplazamiento
  reg [7:0] SPIBUFF;
  always @(posedge clk) 
    if (load)
      SPIBUFF<=D_in;
    else if (shift) begin
      if (MSBfirst)
        SPIBUFF <= {SPIBUFF[6:0],MISO};
      else
        SPIBUFF <= {MISO,SPIBUFF[7:1]};
    end
  //-----------------------------------

  //-- Bloque contador
  reg [2:0] count=0; 
  always @(posedge clk)
    if (nextcount)
      count<= count+1;
  //-------------------

  //-- sck
  assign SCLK = div[1] ^ CPOL; // clk/4 = 12MHZ/4 = 3MHz (pudiese configurarse para menor freq...(TODO))
  // sdo
  assign MOSI = MSBfirst? SPIBUFF[7] : SPIBUFF[0];
  // \cs
  assign SS = (state == S_inicio); //
  // D_out
  assign D_out = SPIBUFF;

  reg done, busy;
  //-- Logica combinacional
  always @(*) begin  
    nextState = state;
    shift = 0; stop_SCKL=1;  load=0; nextcount=0;
    done = 0; busy = 1;
    case (state)
    S_inicio: begin
      busy=0;
      if (start) begin
        nextState = S_bajoSCLK;
        load = 1; // Carga valor al buffer
      end
    end
    S_bajoSCLK: begin
      stop_SCKL=0;
      if (change) begin
        nextState = S_altoSCLK;
        // la primera transicion no se toma en cuenta
        shift = (CPHA && count != 0); // en modo 1 y 3 SCLK          
      end
    end
    S_altoSCLK:begin
      stop_SCKL=0;
      if (change) begin
        nextcount = 1;
        if (count==7)
          nextState = S_detenido;
        else
          nextState = S_bajoSCLK;

        shift = ~CPHA;
      end
    end
    S_detenido: begin
      stop_SCKL=0;
      if (change) begin
        stop_SCKL=1;
        shift = CPHA; // se realiza un ultimo shift
        nextState = S_inicio;
        done = 1;
      end
    end
    endcase
  end

endmodule