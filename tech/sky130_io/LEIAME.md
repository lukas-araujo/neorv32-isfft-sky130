# tech/sky130_io/ — modelos Verilog dos pads de I/O (sky130_fd_io / sky130_ef_io)

Usados na simulação do chip com os pads (etapa 10, `layout/chip/10_simula.sh`)
e, os dois primeiros da tabela, como `PAD_VERILOG_MODELS` do LibreLane
(etapa 11, `layout/chip/config.json`; DIARIO_GDSII L61).
Licença Apache-2.0 (cabeçalhos mantidos). Cópia **sem modificação**, exceto o
último arquivo da tabela, que é nosso.

| Arquivo | De onde | O quê |
|---|---|---|
| `verilog/sky130_ef_io.v` | open_pdks `8afc8346`, `sky130/custom/sky130_fd_io/verilog/` | wrappers da Efabless: pads de alimentação `*_clamped_pad`, canto, fatias |
| `verilog/sky130_ef_io__gpiov2_pad_wrapped.v` | idem | o pad de GPIO que usamos (`gpiov2` + barramentos em met5) |
| `verilog/sky130_fd_io__top_gpiov2.functional.pp.v` | `google/skywater-pdk-libs-sky130_fd_io` `63752cd`, `cells/top_gpiov2/` | modelo funcional do pad de GPIO, **com pinos de alimentação** (é ele que decide `IN`/`PAD` a partir de `DM`, `OE_N`, `INP_DIS`, `ENABLE_H`…) |
| `verilog/sky130_fd_io__top_power_lvc_wpad.functional.pp.v` | idem, `cells/top_power_lvc_wpad/` | pad de alimentação de baixa tensão (`P_CORE = P_PAD`) |
| `verilog/sky130_fd_io__top_power_hvc_wpadv2.functional.pp.v` | idem, `cells/top_power_hvc_wpadv2/` | pad de alimentação de alta tensão (`tran P_CORE, P_PAD`) |
| `verilog/sky130_fd_io__top_ground_lvc_wpad.functional.pp.v`, `…_hvc_wpad…` | idem, `cells/top_ground_{lvc,hvc}_wpad/` | pads de terra (VSSD; VSSIO e VSSA) |
| `verilog/sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um.v` | **nosso** (35ª sessão) | o PDK traz LEF/GDS desta fatia, mas não o modelo: `VCCHIB ← VCCD`, `VSWITCH ← VDDIO` |

Compilar com `-DUSE_POWER_PINS` (os wrappers só ligam os pads de alimentação ao
anel com essa macro).
