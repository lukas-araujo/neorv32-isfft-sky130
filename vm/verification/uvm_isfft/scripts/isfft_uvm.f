//=============================================================================
// isfft_uvm.f -- arquivos do testbench UVM (ordem importa: interfaces e
// pacotes antes de quem usa)
//
// ${UVM_DIR} e ${UVM_WORK} vem do run_first_uvm.tcl (ou do
// sim/run_uvm_verilator.sh). O RTL do DUT esta em isfft_dut.f, gerado na
// hora por gera_dut_f.sh a partir do frontend/ (o MESMO RTL que foi
// sintetizado).
//=============================================================================
+incdir+${UVM_DIR}/env
${UVM_DIR}/tb/axil_if.sv
${UVM_DIR}/tb/axis_if.sv
${UVM_DIR}/tb/isfft_sva.sv
${UVM_DIR}/agents/axil/axil_pkg.sv
${UVM_DIR}/agents/axis/axis_pkg.sv
${UVM_DIR}/env/isfft_env_pkg.sv
${UVM_DIR}/seq/isfft_seq_pkg.sv
${UVM_DIR}/tests/isfft_test_pkg.sv
${UVM_DIR}/tb/isfft_tb_top.sv
-f ${UVM_WORK}/isfft_dut.f
