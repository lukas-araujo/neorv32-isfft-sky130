# Slides extras: PDK SkyWater, OpenRAM e energia por matriz na FPGA.
src = open("/home/claude/apres/build.py").read().split("C, L, R = PP_ALIGN")[0]
exec(src)
OUT = "/home/claude/apres/slides_extras.pptx"
I2 = "/home/claude/apres/img2/"
C, L, R = PP_ALIGN.CENTER, PP_ALIGN.LEFT, PP_ALIGN.RIGHT
final = []

# ------------------------------------------------------------------ PDK
s = new_slide(); title(s, "PDK: SKYWATER 130 nm")
text(s, 0.8, 2.1, 11.4, 7.3, [
    [("PDK aberto: ", {"bold": True, "color": AMBER}),
     ("SkyWater + Google, licença Apache 2.0. Células, regras de DRC/LVS e modelos sem NDA: "
      "layout, macros e diários podem virar aula.", {})],
    [("Fluxo inteiro até o GDSII: ", {"bold": True, "color": AMBER}),
     ("o PDK traz os arquivos de que as ferramentas abertas precisam (LEF, Liberty, GDS, regras do "
      "Magic, Netgen e KLayout). O Cadence da VM não tem as regras físicas do sky130.", {})],
    [("Biblioteca sky130_fd_sc_hd ", {"bold": True, "color": AMBER}),
     ("(alta densidade), 1,8 V. Síntese no canto típico: TT, 25 °C.", {})],
    [("Nó maduro: ", {"bold": True, "color": AMBER}),
     ("130 nm é barato, bem documentado e usado em tapeouts educacionais abertos.", {})]],
    size=23, bullet=True, space=16)
for i, (n, lab) in enumerate([("130 nm", "nó da SkyWater\n(CMOS, 1,8 V no núcleo)"),
                              ("li1 + 5", "camadas de metal\n(met1 a met5)")]):
    stat(s, 12.9, 2.1 + i * 2.55, 6.3, 2.3, n, lab, numsize=48, labsize=19)
card(s, 12.9, 7.2, 6.3, 2.25, fill=AMBER, alpha=22, line=False)
text(s, 13.1, 7.25, 5.9, 2.15, [
    [("Dois PDKs no projeto", {"bold": True, "color": AMBER})],
    [("open_pdks de 2022 para a OpenRAM e a .lib do Genus; a versão fixada pelo LibreLane para o layout.", {"size": 18})]],
    size=21, space=4, anchor=MSO_ANCHOR.MIDDLE)
notes(s, "(45 s) Por que SkyWater 130: é o PDK aberto. Sem NDA, com tudo de que o fluxo aberto precisa "
         "para chegar ao GDSII, e o projeto pode ser mostrado por inteiro.")
final.append(s)

# ------------------------------------------------------------------ OpenRAM
s = new_slide(); title(s, "MEMÓRIAS: OPENRAM")
text(s, 0.8, 2.1, 9.6, 4.6, [
    [("Problema: ", {"bold": True, "color": AMBER}),
     ("memória em flip-flop custa ~43,9 µm²/bit; a macro SRAM de 4 kB, 8,7 µm²/bit — 5× menos.", {})],
    [("O sky130 aberto não traz compilador de memória da foundry. ", {"bold": True, "color": AMBER}),
     ("A OpenRAM é um compilador aberto (Python): de um arquivo de configuração (palavra, profundidade, "
      "portas, escrita por byte) sai a macro inteira.", {})],
    [("Saídas: ", {"bold": True, "color": AMBER}),
     ("GDS e LEF (layout), Liberty (timing para o Genus), Verilog (simulação) e SPICE.", {})],
    [("Bitcells da SkyWater ", {"bold": True, "color": AMBER}),
     ("de 1 porta (1rw) e de 2 portas (1rw1r).", {})]],
    size=21, bullet=True, space=10)
ix, iy, iw, ih = picture(s, I2 + "m4k_full_c.png", 10.9, 2.15, 8.3, 3.55, white_card=True)
caption(s, ix - 0.12, iy + ih + 0.17, iw + 0.24,
        "Macro de 4 kB (DMEM), 808,8 × 351,3 µm: matriz de bitcells (rosa) e periferia gerada pela OpenRAM.")
rows = [["Macro", "Uso", "Portas", "Área"],
        ["8 kB (32 × 2048)", "IMEM", "1rw", "448.827 µm²"],
        ["4 kB (32 × 1024)", "DMEM", "1rw", "284.139 µm²"],
        ["64 × 256", "FIFO de saída da ISFFT", "1rw1r", "296.939 µm²"],
        ["64 × 64", "buffer de entrada da ISFFT", "1rw1r", "152.932 µm²"],
        ["Total", "4 macros", "", "1,18 mm²"]]
table(s, 0.8, 6.85, 11.0, rows, [2.8, 4.0, 1.4, 2.8], rowh=0.43, size=16, bold_first_col=True,
      aligns=[L, L, C, R], highlight_last=True)
card(s, 12.3, 6.85, 6.9, 2.58)
text(s, 12.5, 6.92, 6.5, 2.45, [
    [("O preço", {"bold": True, "color": CYAN, "size": 21})],
    "Horas de geração por macro (a de 4 kB: 3 h 53 min).",
    "Ajustes antes do fluxo: .lib com 33 bits, LEF em 1000 DBU e com FOREIGN."], size=17, space=4)
notes(s, "(1 min) As memórias grandes vêm da OpenRAM, o compilador de SRAM aberto: gera layout, "
         "timing e modelo. As 4 macros ocupam 1,18 mm², 62 % do chip. O preço foi tempo de geração "
         "e alguns arquivos que precisaram de correção para entrar no fluxo.")
final.append(s)

# ------------------------------------------------------------------ Energia
s = new_slide(); title(s, "FPGA: ENERGIA POR MATRIZ")
card(s, 0.8, 2.1, 18.4, 1.25, fill=AMBER, alpha=22, line=False)
text(s, 1.0, 2.1, 18.0, 1.25, [
    [("Métrica: energia por matriz  E = P × t  (µJ/matriz). ", {"bold": True, "color": AMBER}),
     ("O inverso, matrizes por joule, diz o mesmo.", {})]], size=24, anchor=MSO_ANCHOR.MIDDLE)
cols = [("NEORV32 + ISFFT (hardware na PL)",
         [("P", "0,128 W — dinâmica da PL (2,545 − 2,417 W)"),
          ("t", "6,87 µs — 687 ciclos a 100 MHz, com a programação do DMA"),
          ("E", "≈ 0,88 µJ por matriz")]),
        ("ARM (ISFFT em numpy no Zynq PS)",
         [("P", "2,417 W — potência do PS"),
          ("t", "t_ARM — medir no notebook (modelo_isfft)"),
          ("E", "2,417 W × t_ARM")])]
for k, (head, items) in enumerate(cols):
    x = 0.8 + k * 9.45
    card(s, x, 3.65, 8.95, 3.75)
    text(s, x + 0.3, 3.75, 8.4, 0.65, head, size=24, bold=True, color=AMBER if k == 0 else CYAN)
    for i, (sym, val) in enumerate(items):
        y = 4.5 + i * 0.95
        text(s, x + 0.3, y, 0.8, 0.85, [[(sym, {"bold": True, "font": HEAD})]], size=30,
             color=AMBER if k == 0 else CYAN, anchor=MSO_ANCHOR.MIDDLE)
        text(s, x + 1.15, y, 7.6, 0.85, val, size=20, bold=(sym == "E"), anchor=MSO_ANCHOR.MIDDLE, space=0)
text(s, 0.8, 7.6, 18.4, 1.9, [
    "Potências da estimativa do Vivado (report_power, atividade padrão), não de medição na placa.",
    "Na Kria o ARM fica ligado nos dois casos: a conta compara o custo de cada caminho. No ASIC não existe ARM.",
    "Contando também a estática do chip inteiro (0,301 W), o hardware fica em ≈ 2,95 µJ por matriz."],
    size=19, bullet=True, space=6, color="E4E0FA")
notes(s, "(1 min) Energia por matriz é potência vezes tempo. No hardware: 0,128 W por 6,87 µs, menos de "
         "1 µJ. No ARM: a potência do PS vezes o tempo do numpy medido no notebook. Os valores de "
         "potência são estimativas do Vivado.")
final.append(s)

# ------------------------------------------------------------------ só os novos
sldIdLst = prs.slides._sldIdLst
keep_parts = {x.part for x in final}
for sldId in list(sldIdLst):
    if prs.part.related_part(sldId.rId) not in keep_parts:
        sldIdLst.remove(sldId)
for rel in list(prs.part.rels.values()):
    if rel.reltype.endswith("/slide") and rel.target_part not in keep_parts:
        prs.part.drop_rel(rel.rId)
prs.save(OUT)
print("ok", len(final))
