`include "uart.vh"

/* Modulo generador de baudios*/
module BaudClock #(parameter BAUD=115200)
  (
    input clk,
    input clk_ena,
    output clk_out
  );
  //-- Constante para calcular los baudios
  localparam BAUDRATE = (BAUD==115200) ? `B115200 : //-- OK
                        (BAUD==57600)  ? `B57600  : //-- OK
                        (BAUD==38400)  ? `B38400  : //-- Ok
                        (BAUD==19200)  ? `B19200  : //-- OK
                        (BAUD==9600)   ? `B9600   : //-- OK
                        (BAUD==4800)   ? `B4800   : //-- OK 
                        (BAUD==2400)   ? `B2400   : //-- OK
                        (BAUD==1200)   ? `B1200   : //-- OK
                        (BAUD==600)    ? `B600    : //-- OK
                        (BAUD==300)    ? `B300    : //-- OK
                        `B115200 ;  //-- Por defecto 115200 baudios

  //---- GENERADOR DE BAUDIOS
  //-- Calcular el numero de bits para almacenar el divisor
  localparam N = $clog2(BAUDRATE);

  //-- Contador para implementar el divisor
  //-- Es un contador modulo BAUDRATE
  reg [N-1:0] divcounter = 0;

  //-- Cable de reset para el contador
  wire reset = clk_out | (!clk_ena);

  //-- Contador con reset
  always @(posedge clk)
    if (reset)
      divcounter <= 0;
    else
      divcounter <= divcounter + 1;

  //-- Tic de salida
  wire clk_out = (divcounter == BAUDRATE-1);

endmodule

module serialTX #(parameter BAUD=115200)
  ( input clk,
    input [7:0] data,
    input txmit,
    output TX,
    output busy,
    output done
  );

  reg state = 0;
  wire shift;
  //--
  BaudClock #(BAUD) bclk (
    .clk(clk),
    .clk_ena(state),
    .clk_out(shift));

  //-- Detector de flancos de subida
  reg q_re = 0;
  wire txmit_tic;
  always @(posedge clk)  q_re <= txmit;

  assign txmit_tic = (~q_re & txmit); 

  //-- Controlador: Estado de transmisor
  //-- 0: Parado; 1: Ocupado (transmitiendo)
  always @(posedge clk)
    if (txmit) //-- Empieza la transmision: ocupado
      state <= 1'b1;
    else if (ov) //-- Acaba la transmision: libre    
      state <= 1'b0;

  //-- REGISTRO DESPLAZAMIENTO
  //-- Registro de desplazamiento de 9 bits
  reg [8:0] q = 9'h1FF; //-- Inicializado todo a 1s
  always @(posedge clk)
    if (txmit_tic) //-- Carga del registro
      q <= {data, 1'b0};    
    else if (shift) //-- Desplazamiento. Rellenar con 1 (bit de stop)
      q <= {1'b1, q[8:1]};
      
  //-- Salida serie. Inicialmete a 1 (reposo) 
  reg TX = 1;
  always @(posedge clk)
    TX <= q[0]; //-- Sacar el bit de menor peso por serial-out    

  //-- Contador de bits enviados
  reg [3:0] bits = 0;
  always @(posedge clk)
    if (ov) //-- Si la cuenta ha terminado... volver a 0
      bits <= 2'b00;
    else if (shift)
      bits <= bits + 1;

  //-- Comprobar si se ha transmitido el último bit (overflow)
  wire ov = (bits == 10);   //-- 1 bit de start + 8 bits de datos + 1 bit de stop

  //-- La señal de ocupado es el estado del transmisor
  assign busy = state;

  //-- Registro done; Con un ciclo de retraso
  reg done=0;
  always @(posedge clk)
    done <= ov;

endmodule

module serialRX #(parameter BAUD=115200)(
  input clk,
  input RX,
  output [7:0] data,
  output busy,
  output rcv
  );
  //-- Constante para calcular los baudios
  localparam BAUDRATE = (BAUD==115200) ? `B115200 : //-- OK
                        (BAUD==57600)  ? `B57600  : //-- OK
                        (BAUD==38400)  ? `B38400  : //-- Ok
                        (BAUD==19200)  ? `B19200  : //-- OK
                        (BAUD==9600)   ? `B9600   : //-- OK
                        (BAUD==4800)   ? `B4800   : //-- OK 
                        (BAUD==2400)   ? `B2400   : //-- OK
                        (BAUD==1200)   ? `B1200   : //-- OK
                        (BAUD==600)    ? `B600    : //-- OK
                        (BAUD==300)    ? `B300    : //-- OK
                        `B115200 ;  //-- Por defecto 115200 baudios

  //-- Calcular el numero de bits para almacenar el divisor
  localparam N = $clog2(BAUDRATE);

  // Sincronizacion. Evitar problema de la metaestabilidad
  reg d1;
  reg din;
  always @(posedge clk)
   d1 <= RX;
  //-- Din contiene el dato serie de entrada listo para usarse   
  always @(posedge clk)
    din <= d1;
    
  //------ Detector de flanco de bajada
  reg q_t0 = 0;
  always @(posedge clk)
    q_t0 <= din;
  wire din_fe = (q_t0 & ~din); // bit de start

  //-------- ESTADO DEL RECEPTOR
  //-- 0: Apagado. Esperando
  //-- 1: Encendido. Activo. Recibiendo dato  
  reg state = 0;
  wire rst_state;
  always @(posedge clk)
    if (din_fe)
      state <= 1'b1;
    else if (rst_state) //-- Se pasa al estado inactivo al detectar la señal rst_state   
      state<=1'b0;

//------------------ GENERADOR DE BAUDIOS -----------------------------
  // Genera retraso de BAUD/2 antes de iniciar la recepcion
  localparam BAUD2 = (BAUDRATE >> 1);

  //-- Contador del sistema, para esperar un tiempo de medio bit (BAUD2)
  reg [N-1: 0] div2counter = 0; //-- NOTA: podria tener N-2 bits en principio

  always @(posedge clk)
    if (state) begin  //-- Contar
      if (div2counter < BAUD2) // conteo solo al inicio de una transmision
        div2counter <= div2counter + 1;
    end else
      div2counter <= 0;

  wire ena2 = (div2counter == BAUD2);

  //--- GENERADOR DE BAUDIOS PRINCIPAL
  wire bit_tic;
  BaudClock #(BAUD) bclk (
    .clk(clk),
    .clk_ena(ena2),
    .clk_out(bit_tic));

//-------- REGISTRO DE DESPLAZAMIENTO -----------
  //-- Es un registro de 9 bits: 8 bits de datos + bit de stop
  //-- El bit de start no se almacena, es el que ha servido para
  //-- arrancar el receptor

  reg [8:0] sr = 0;
  always @(posedge clk) 
    if (bit_tic & state)
      sr <= {din, sr[8:1]};
      
  //-- El dato recibido se encuentran en los 8 bits menos significativos
  //-- una vez recibidos los 9 bits

//-------- CONTADOR de bits recibidos

  //-- Internamente usamos un bit mas -- (N+1) bits
  reg [4:0] cont = 0;
  always @(posedge clk)
    if ((state==0)| fin)
      cont <= 0;
    else
      if (bit_tic)  //-- Receptor activado: Si llega un bit se incrementa
        cont <= cont + 1;
        
  //-- Comprobar overflow, indica el final de recepcion
  wire fin = (cont == 9);

  //-- Se conecta al reset el biestable de estado
  assign rst_state = fin;

//----- REGISTRO DE DATOS -------------------
  //-- Registro de 8 bits que almacena el dato final

  //-- Bus de salida con el dato recibido
  reg data = 0;

  always @(posedge clk)
    if (fin)
      data <= sr[7:0];

  //-- Comunicar que se ha recibido un dato
  reg rcv = 0;
  always @(posedge clk)
    rcv <= fin;

  //-- La señal de busy es directamente el estado del receptor
  assign busy = state;


endmodule