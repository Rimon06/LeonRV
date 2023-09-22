`include "Procesador_V2.1b/registros_32.v"
`include "Procesador_V2.1b/ALU.v"
`include "Procesador_V2.1b/interfaz_mem.v"
`include "Procesador_V2.1b/RV32nexpo.v"

/*top*/
module SOCnexpo(
  input clk12MHz,
  // Perifericos dentro de la placa icefun
  input [3:0] key,
  output [7:0] led,
  output [3:0] lcol,
  // Transmision Serial
  input RXD,
  output TXD,
  // SPI
  output SCK,
  output SDA,
  output RES,
  output SS_,
  output D_C
  );//#############################################################################################
  

  wire error,end_prog;
  wire [31:0] pc, DataRead, DatatoWrite, mem_address;
  wire [3:0] Wmask;
  wire mem_read,mem_write;

  // --- inicializador ---
  reg rst=1;
  reg [7:0] Espera=8'b0; // La espera es de 256 ciclos de reloj para que la memoria BRAM esté funcional
  always @(posedge clk12MHz) begin // (TODO) pueden ser menos ciclos....
    if (Espera == 8'hFF) 
      rst <= 0;
    else  Espera <= Espera+1;
  end
  
  // --- Espacio para memoria de programa ---
  // --* Direccion de programa: 0x0000_0000 al 0x0000_1FFF (8 KiB === 2048 instrucciones)
  localparam TAM_ROM = 2048; // instrucciones (8192 bytes, si).
  localparam TAM_BUS_ROM = $clog2(TAM_ROM); // debe dar 11
  // -- De solo lectura por el pc
   wire [TAM_BUS_ROM-1:0] ROM_address = pc[TAM_BUS_ROM+1:2]; // [12:2] pues utiliza bus de tamaño [12:0] para direccionar 8192 bytes
  
  // -- Bloque ROM
  reg [31:0] MEMROM [0:TAM_ROM-1];
  reg [31:0] instr;
  initial begin // datos iniciales indicados por un archivo program.hex
    $readmemh("program.hex", MEMROM);
  end
  // (TODO) Agregar escritura a memoria de programa. (Planificar, tener cuidado)
  always @(posedge clk12MHz)
    instr <= MEMROM[ROM_address];
  
  // --*(TODO) Asignar resto del espacio de programa a partir del 0x0001_0000 .....

  //----------------------------------------------------

  // --- Procesador (RV32i_Zicsr)
  RV32nexpo RV32I (
    .clk(clk12MHz),
    .rst(rst), // Control entrada
    .error(error), // Control salida
    .end_prog(end_prog),
    .InstrData(instr), // Bus de memoria de instrucciones
    .InstrAddr(pc),
    .mem_in(DataRead), // datos de entrada    
    .mem_out(DatatoWrite), //datos de salida
    .mem_address(mem_address),  // bus de direcciones
    .mem_mask(Wmask), // mascara del byte a escribir
    .mem_read(mem_read),// señal de lectura de memoria
    .mem_write(mem_write) // señal de escritura de la memoria
  );//----------------------------------------------------

  // --- Espacio para memoria de datos ---
  
  localparam TAM_RAM = 1536; // 6144 bytes - 1536 palabras //2048; // palabras (8192 bytes, si)
  localparam TAM_BUS_RAM = $clog2(TAM_RAM); // El cual debe dar 11
  wire [TAM_BUS_RAM-1:0] RAM_address = mem_address[TAM_BUS_RAM+1:2];
  wire [15:0] IO_address = mem_address[17:2];
  
  // -- Decodificacion de las direcciones
  wire ram_valid        = (mem_address[31:13] == 'b0);
  wire io_valid         = (mem_address[31]  ==  1'b1);

  wire boton_val        = (IO_address == 16'd0);
  wire leds_val         = (IO_address == 16'd1);
  wire leds_config_val  = (IO_address == 16'd2);
  wire uart_val         = (IO_address == 16'd3);
  wire oled_comm_val    = (IO_address == 16'b0111111);  
  wire oled_data_val    = (IO_address == 16'b1000000);
  
  wire [31:0] RAM_data, LEDS_data, LEDS_config_data, UART_data;

  // -- Registro de lectura de I/O, con io multiplexado
  reg [31:0] IO_data;
  reg IO_sig, ram_sig;
  // los datos I/O pasaran a través de un registro de lectura, esto para que la etapa Wb tenga el valor correcto...
  always @(posedge clk12MHz) begin // Etapa M que hay que validar (supongo) (TODO) mejorar
    if (rst) begin
      IO_sig <= 0;
      ram_sig <= 0;
    end else begin
      IO_sig <= io_valid;
      ram_sig <= ram_valid;
      IO_data <= (boton_val)      ? {24'b0,4'b0,~key}: // Lee botones aqui
                 (leds_val)       ? LEDS_data        :
                 (leds_config_val)? LEDS_config_data :
                 (uart_val)       ? UART_data        : // agregar mas IO
                                      32'b0          ;
    end
  end
  // -- multiplexor final...
  assign DataRead = ((ram_sig) ? RAM_data: 32'b0) |
                    ((IO_sig)  ? IO_data : 32'b0) ;


  // --- Espacio para memoria de datos ---
  
  // --> Lectura y escritura por mem_address
  // --* memoria BRAM: 0x0000_0000 al 0x0000_1FFF (8KiB)
  
  // -- Bloque RAM
  memory #(
    .TAM(TAM_RAM)
  )RAM(
    .clk(clk12MHz),
    .rst(rst),
    .valid(ram_valid),
    .read(mem_read),
    .WRmask(Wmask),
    // Bus de direcciones
    .Addr(RAM_address), 
    .DataIn(DatatoWrite),
    .DataOut(RAM_data)
  );
  
  // --* Espacio de memoria para la matriz led
  // 0x8000_0004 al 0x8000_0007: Registros de datos (leds)
  // 0x8000_0008 al 0x8000_000B: Registro de configuracion

  // -- registro de datos leds1 a leds4
  reg [7:0] leds1,leds2,leds3,leds4;
  always @(posedge clk12MHz) begin 
    if (rst) begin
      {leds4,leds3,leds2,leds1} <= 32'h00000000;
    end else if (error) begin // Error :C
      {leds4,leds3,leds2,leds1} <= 32'hFF898981;
    end else if (end_prog) begin // Fin de programa :D
      {leds4,leds3,leds2,leds1} <= 32'hFF090901;
    end else if (leds_val) begin
      if (Wmask[3]) leds4<=DatatoWrite[31:24];
      if (Wmask[2]) leds3<=DatatoWrite[23:16];
      if (Wmask[1]) leds2<=DatatoWrite[15:8];
      if (Wmask[0]) leds1<=DatatoWrite[7:0];
      end
  end
  assign LEDS_data = {leds4,leds3,leds2,leds1};
  
  // -- Registro de control .... leds_en
  reg leds_en=1;
  always @(posedge clk12MHz) begin
    if (rst) begin
      leds_en<=1;
    end else if (leds_config_val&Wmask[0]) begin
      leds_en <= DatatoWrite[0];
    end
  end
  assign LEDS_config_data={24'b0,7'b0,leds_en};

  // -- Controlador de Matrices led ...
  ControladorMatrizLed LEDS8_4(
    .clk12Mhz(clk12MHz),
    .rst(rst),//&(!leds_en)), 
    .leds1(leds1),    
    .leds2(leds2),
    .leds3(leds3),
    .leds4(leds4),
    .leds(led), 
    .lcol(lcol)
  );
  
  // --* Espacio de Bloque UART 
  // (TODO) Mejorar implementacion de tx y rx
  // TX/RX: 0x8000_000C
  // control-estado: 0x8000_000D al 0x8000_000F
  wire txBusy,txDone;
  reg tx_ready;
  // -- Bloque emisor
  serialTX UART_TX(
  .clk(clk12MHz),
  .data(DatatoWrite[7:0]),
  .txmit(uart_val&Wmask[0]),
  .TX(TXD),
  .busy(txBusy),
  .done(txDone)
  );
  // registro tx_ready
  always @(posedge clk12MHz)
    if (rst)
      tx_ready <= 1;
    else if (txBusy)
      tx_ready <= 0;
    else if (txDone)
      tx_ready <= 1;

  wire rxBusy,rxRCV;
  wire [7:0] rxData;
  reg [7:0] SerialData;

  // -- Bloque receptor
  serialRX UART_RX(
    .clk(clk12MHz),
    .RX(RXD),
    .data(rxData),
    .busy(rxBusy),
    .rcv(rxRCV));

  /* habría que asignar un estado de "lectura", que SerialData se leyó una vez y retorne a cero....
     seria así, si tan solo la implementación de serialRX la manejase yo......  */
  reg rx_readed; 
  always @(posedge clk12MHz)
    if (rst)
      rx_readed<=1;
    else if (rxRCV)
      rx_readed <= 0;
    else if (mem_read&uart_val)
      rx_readed <= 1;

  // idealmente, cuando ocurre un rxRCV, SerialData debe colocar su nuevo valor...
  // always @(posedge clk12MHz)
  //   if (rst)
  //     SerialData <= 0;
  //   else begin
  //     if (rx_readed)
  //       SerialData <= 8'b0;
  //     else if (rxRCV)
  //       SerialData <= rxData;
  //   end
    
  assign UART_data = {16'b0,6'b0,1'b0/*rx_readed*/,tx_ready,rxData}; // No implementado RX todavia 

// --* Espacio de memoria para la pantalla oled
  // 0x8000_00FC al 0x8000_00FF: Seccion para enviar comando por oled 
  // 0x8000_0100 al 0x8000_01FF: Registro de caracteres (leds) (256*8) (128*64)
  wire busy;
  SSD1306_SPI oled(
  .clk(clk12MHz),
  .rst(rst),
  .done(),
  .data_in(DatatoWrite), 
  .valid_comm(oled_comm_val),
  .valid_data(oled_data_val),
  .data_address(mem_address),
  .Wmask(Wmask),
  .busy(busy),

  .ss_(SS_), // chip select activo en bajo
  .sck(SCK), // reloj 
  .sda(SDA), // mosi
  .res(RES), // señal de reset (posible borrar)
  .d_c(D_C) // data_control
  );

endmodule //#########################################################################################

// memory instancia un bloque de TAM x 32. Este debe de ser menor a 16384
module memory #(
  parameter TAM = 2048,
  parameter Addrbits =$clog2(TAM) // bit mas significativo de la direccion de memoria
  )(
  input clk,
  // Señales de control
  input rst,
  input [3:0] WRmask, // Señales de escritura
  input valid, // señal si dato es valido
  input read, // Señal de lectura
  // Bus de direcciones
  input [Addrbits-1:0] Addr, 
  // Bus de Datos de entrada/salida
  input  [31:0] DataIn,
  output [31:0] DataOut
  );//################################################################################################

  reg [31:0] memArray [TAM-1:0]; // Bloque de memoria de TAMx32 bits

  // La memoria de datos solo escribe si WRmask!=0 y es valido 
  wire dWE = (!rst) & (|WRmask) & valid;  // Write Enable
  wire dRE = (!rst) & read & valid; // Read Enable
  reg [31:0] DataOut;
  
  initial begin
    $readmemh("data.hex", memArray);
  end
  
  // Bloque de escritura de datos
  always @(posedge clk) begin
    if (dWE) begin
      if (WRmask[0]) memArray[Addr][7:0]   <= DataIn[7:0]; 
      if (WRmask[1]) memArray[Addr][15:8]  <= DataIn[15:8];
      if (WRmask[2]) memArray[Addr][23:16] <= DataIn[23:16];
      if (WRmask[3]) memArray[Addr][31:24] <= DataIn[31:24];
    end
    DataOut <= memArray[Addr];
  end


endmodule //######################################################################################

