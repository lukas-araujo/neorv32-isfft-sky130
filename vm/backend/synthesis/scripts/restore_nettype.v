// Restaura o modo padrao de rede.
//
// Os arquivos do sky130 declaram `default_nettype none, e a diretiva
// VAZA para os arquivos lidos em seguida -- inclusive o netlist. Sem
// isto, centenas de conexoes do netlist nao se formam e o circuito
// fica todo em X, SEM nenhum erro de compilacao (so avisos NODNTW).
//
// Ler DEPOIS dos modelos das celulas e ANTES do netlist.
//
// NAO existe opcao de linha de comando equivalente no Xcelium 23.09
// (-default_nettype e -mfcu nao existem; -helpall nao lista nada de
// unidade de compilacao). E nao existe por bom motivo: o padrao
// Verilog especifica que a diretiva vale da posicao em diante,
// atravessando arquivos. Um arquivo posicionado na ordem de leitura e
// o mecanismo CORRETO, nao um contorno.
`default_nettype wire
