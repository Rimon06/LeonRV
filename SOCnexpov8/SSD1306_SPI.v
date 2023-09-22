
`define SSD1306_SETCONTRAST         8'h81
`define SSD1306_DISPLAYALLON_RESUME 8'hA4
`define SSD1306_DISPLAYALLON        8'hA5
`define SSD1306_NORMALDISPLAY       8'hA6
`define SSD1306_INVERTDISPLAY       8'hA7
`define SSD1306_DISPLAYOFF          8'hAE
`define SSD1306_DISPLAYON           8'hAF
`define SSD1306_SETDISPLAYOFFSET    8'hD3
`define SSD1306_SETCOMPINS          8'hDA
`define SSD1306_SETVCOMDETECT       8'hDB
`define SSD1306_SETDISPLAYCLOCKDIV  8'hD5
`define SSD1306_SETPRECHARGE        8'hD9
`define SSD1306_SETMULTIPLEX        8'hA8
`define SSD1306_SETLOWCOLUMN        8'h00
`define SSD1306_SETHIGHCOLUMN       8'h10
`define SSD1306_SETSTARTLINE        8'h40
`define SSD1306_MEMORYMODE          8'h20
`define SSD1306_COMSCANINC          8'hC0
`define SSD1306_COMSCANDEC          8'hC8
`define SSD1306_SEGREMAP            8'hA0
`define SSD1306_CHARGEPUMP          8'h8D
`define SSD1306_EXTERNALVCC         8'h01
`define SSD1306_INTERNALVCC         8'h02
`define SSD1306_SWITCHCAPVCC        8'h02
`define SSD1306_NOP_DATA            8'hE3                

module SSD1306_SPI(
  // sistema
  input clk,
  input rst,
  // control del modulo
  input CharMode,
  output done,
  // interfaz con el bus riscv
  input [31:0] data_in, 
  input valid_comm,
  input valid_data,
  input [31:0] data_address,
  input [3:0] Wmask,
  output busy,
  // interfaz spi 
  output ss_, // chip select activo en bajo
  output sck, // reloj 
  output sda, // mosi
  output res, // señal de reset (posible borrar)
  output d_c // data_control
  );

  localparam S_init = 0;
  localparam S_rst = 1;
  localparam S_init_config = 2;
  localparam S_idle = 3;
  localparam S_Data = 4;
  localparam S_command = 5;

  reg [2:0] state, nextState;

  
  reg [31:0] counter=0;
  reg d_c, res, ss_, work, done;
  reg [3:0] RDmask = 4'b0;
  

  assign busy = spi_working || (state != S_init) || (state != S_idle);


  //~~~ SPI master ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Si trabaja en modo continuo, dura 35 ciclos en total, con una frecuencia de 12MHz (y SCLK trabajando a 3MHz)
  wire [7:0] spi_in = (state == S_init_config)? init_comm : 
                      (state == S_Data)?          Columna : data_in[7:0] ;
  wire spi_working, next;
  SPI_master uut(
    .clk(clk),
    .rst(rst),
    .start(work),
    .busy(spi_working),
    .done(next),
    .D_in(spi_in),
    // .D_out(D_out),

    .CPHA(1'b0),
    .CPOL(1'b0),
    .MSBfirst(1'b1),

    .MISO(1'b1),
    .MOSI(sda),
    .SCLK(sck)
    //.SS() // ?
  );

  //~~~~~~~~~ init routine ~~~~~~~~~~~~~~~~~~~~~~
  wire [4:0] count_init = counter[4:0];
  reg [7:0] init_comm;
  always @* case(count_init)
    0: init_comm = `SSD1306_DISPLAYOFF;         // 0xAE
    1: init_comm = `SSD1306_SETDISPLAYCLOCKDIV; // 0xD5
    2: init_comm = 8'h80;
    3: init_comm = `SSD1306_SETMULTIPLEX;       // 0x A8
    4: init_comm = 8'h3F;
    5: init_comm = `SSD1306_SETDISPLAYOFFSET;   // 0xD3
    6: init_comm = 8'h00;
    7: init_comm = `SSD1306_SETSTARTLINE;       // 0x40
    8: init_comm = `SSD1306_CHARGEPUMP;         // 0x8D
    9: init_comm = 8'h14;
   10: init_comm = `SSD1306_MEMORYMODE;         // 0x20
   11: init_comm = 8'h00;
   12: init_comm = `SSD1306_SEGREMAP | 8'h01;   // 0xA0 | 0x01
   13: init_comm = `SSD1306_COMSCANDEC;         // 0xC8
   14: init_comm = `SSD1306_SETCOMPINS;         // 0xDA
   15: init_comm = 8'h12;
   16: init_comm = `SSD1306_SETCONTRAST;        // 0x81
   17: init_comm = 8'hCF;
   18: init_comm = `SSD1306_SETPRECHARGE;       //0xD9
   19: init_comm = 8'hF1;
   20: init_comm = `SSD1306_SETVCOMDETECT;      //0xDB
   21: init_comm = 8'h40;
   22: init_comm = `SSD1306_DISPLAYALLON_RESUME; // 0xA4
   23: init_comm = `SSD1306_NORMALDISPLAY;      //0xA6
   24: init_comm = `SSD1306_DISPLAYON;          //0xAF
   25: init_comm = 8'h00;
   26: init_comm = 8'h10;
   27: init_comm = 8'h40;
   default: init_comm = 8'h00;
  endcase
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  
  //~~~~~~~~~~~ Memoria ~~~~~~~~~~~~~~~~~~~~~~~~~~
   reg [7:0] RAM_CHAR [0:255];
  reg [7:0] character;
  wire [1:0] decod_byte = (Wmask[3] ? 2'd3 :
                           Wmask[2] ? 2'd2 :
                           Wmask[1] ? 2'd1 : 2'd0);
  wire [7:0] Waddr = data_address[7:0] + decod_byte;
  integer i;
  initial  begin
    for (i=0;i<256;i=i+1)  RAM_CHAR[i]=8'b0;

    RAM_CHAR[0] = "H";
    RAM_CHAR[1] = "o";
    RAM_CHAR[2] = "l";
    RAM_CHAR[3] = "a";
    RAM_CHAR[4] = " ";
    RAM_CHAR[5] = "M";
    RAM_CHAR[6] = "u";
    RAM_CHAR[7] = "n";
    RAM_CHAR[8] = "d";
    RAM_CHAR[9] = "o";
    RAM_CHAR[10] = "!";
  end



  wire Wr_char = (|Wmask) && valid_data;
  always @(posedge clk) begin
    if (Wr_char)
      RAM_CHAR[Waddr] <= Wmask[0]? data_in[7:0] : Wmask[1]? data_in[15:8] : Wmask[2]? data_in[23:16] : data_in[31:24];
  end

  //~~~~~~~~~~~~~~ Caracter decodificado ~~~~~~~~~~~~~~~~~~~~~~~  
  // character guarda lo leido en RAM_CHAR. Esta descrito en la FSM
  wire [31:0] letra;
  reg [7:0] Columna;
  ascciTo4x8 MM (
   .character(character),
   .letra(letra));

  always @(*) begin
    if      (RDmask[0]) Columna = letra[7:0];
    else if (RDmask[1]) Columna = letra[15:8];
    else if (RDmask[2]) Columna = letra[23:16]; 
    else if (RDmask[3]) Columna = letra[31:24];
    else                Columna = 0;
  end

  // Este decodificador no está guardado por filas, sino por columnas...
  // Los otros conseguidos, necesitan decodificar cada columna (6 columnas en total)

  // Cambio de estado por comando mandado
  wire display_on   = valid_comm && Wmask[0] && (data_in[7:0] == `SSD1306_DISPLAYON);
  wire display_data = valid_comm && Wmask[0] && (data_in[7:0] == `SSD1306_NOP_DATA);
  wire comando = valid_comm;

  wire next_char = (next && RDmask==4'b0) || (counter == 0 && RDmask==4'b0);
  wire [7:0] addr_char = counter[7:0];

  //~~~~~~~ Maquina de estado ~~~~~~~~~~~~~~~~~~~~~~~~~~
  always @(posedge clk) begin
    if (rst) begin
      state <= S_init;
      counter <= 0;
      d_c <= 0;
      res <= 1;
      ss_<=1;
    end else begin
      case (state)
        S_init: // Estado inicial
          if (display_on) 
            state <= S_rst;
        S_rst: begin // Estado que se genera un reset
          counter <= counter+1;
          res <= 0;
          if (counter == 119999) begin// 120000 ciclos ~ 10mseg
            state <= S_init_config;
            counter <= 0;
            res <= 1;
            ss_ <= 0;
          end
        end
        S_init_config: begin // Estado de rutina de configuracion
          work <= 1;
          ss_ <= 0; // iniciamos spi
          if (next) begin
            counter <= counter+1;
            if (count_init == 25) begin
              state <= S_idle;
              work <= 0;
              done <= 1;
            end
          end
        end
        S_idle: begin
          ss_ <= 1;
          counter <= 0;
          work <= 0;
          done <= 0;
          if (display_data) begin
            state <= S_Data;
            RDmask <= 4'b0;
          end
          // if (command)
            // state <= 
        end
        S_Data: begin
          ss_ <= 0;
          d_c <= 1;
          work <= 0;
          if (next) begin
            RDmask <= {1'b0,RDmask[3:1]};
            work <= 1;
          end

          if (next_char) begin
            counter   <=  counter+1;
            character <=  RAM_CHAR[addr_char];
            RDmask    <= 4'b1000;
            work      <= 1;
          end

          if (addr_char == 8'd201) begin
            state <= S_idle;
            work <= 0;
            done <= 1;
          end
        end
        S_command: begin
          ss_ <= 0;
          d_c <= 1;
          work<= 0;
          state <= S_idle;
        end
        default: state <= S_init;
      endcase
    end
  end
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
endmodule

module ascciTo4x8(
    input [7:0] character,
    output reg [31:0] letra
  );
  `include "../scroll_char/4x8font.vh"
  always @(*) begin
    case (character)
      "a","A": letra <= _cA;
      "b","B": letra <= _cB;
      "c","C": letra <= _cC;
      "d","D": letra <= _cD;
      "e","E": letra <= _cE;
      "f","F": letra <= _cF;
      "g","G": letra <= _cG;
      "h","H": letra <= _cH;
      "i","I": letra <= _cI;
      "j","J": letra <= _cJ;
      "k","K": letra <= _cK;
      "l","L": letra <= _cL;
      "m","M": letra <= _cM;
      "n","N": letra <= _cN;
      "o","O": letra <= _cO;
      "p","P": letra <= _cP;
      "q","Q": letra <= _cQ;
      "r","R": letra <= _cR;
      "s","S": letra <= _cS;
      "t","T": letra <= _cT;
      "u","U": letra <= _cU;
      "v","V": letra <= _cV;
      "w","W": letra <= _cW;
      "x","X": letra <= _cX;
      "y","Y": letra <= _cY;
      "z","Z": letra <= _cZ;

      "0": letra <= _c0;
      "1": letra <= _c1;
      "2": letra <= _c2;
      "3": letra <= _c3;
      "4": letra <= _c4;
      "5": letra <= _c5;
      "6": letra <= _c6;
      "7": letra <= _c7;
      "8": letra <= _c8;
      "9": letra <= _c9;
      
      " ": letra <= _cSP; // space
      "!": letra <= _cEX;
      "?": letra <= _cQQ;
      ":": letra <= _cCO;
      ";": letra <= _cSC;
      ".": letra <= _cFS;

      "+": letra <= _cPLUS; // plus + 
      "-": letra <= _cMINUS;
      "/": letra <= _cDIVIDE; // divide / 
      "*": letra <= _cMULTIPLY; // multiply x
      "=": letra <= _cEQUALS; // equals = 

     "\\": letra <= _cFWDSLASH; // fwd slash \
      "[": letra <= _cOPENSQ; // open sq [
      "]": letra <= _cCLOSESQ; // close sq ]
      "(": letra <= _cOPENBR; // open br (
      ")": letra <= _cCLOSEBR; // close br )

      default:
        letra <= _cSP; 
    endcase
  end
endmodule
