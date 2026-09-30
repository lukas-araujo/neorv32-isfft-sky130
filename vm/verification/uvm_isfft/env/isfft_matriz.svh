//=============================================================================
// isfft_matriz.svh -- matriz 8x8 complexa (int16) e o modelo numerico
//
// Formato (igual ao da Kria e ao evm.py):
//   elemento i (linha-major, i = linha*8 + coluna) = palavra de 32 bits
//   (imag << 16) | real. Palavra de 64 bits k = {elem 2k+1, elem 2k}.
//   Uma matriz = 32 palavras de 64 bits.
// Saida do DUT: mesma embalagem, mas em ordem de COLUNA:
//   palavra de 32 bits j  <->  Y[j % 8][j / 8]      (reshape(8,8).T)
// Modelo: Y = fft_colunas( ifft_linhas(X) ) / 8   (numpy: fft(ifft(m,1),0)/8)
//=============================================================================

typedef enum { AMP_BAIXA, AMP_MEDIA, AMP_ALTA, AMP_CHEIA } isfft_amp_e;
typedef enum { MAT_ALEATORIA, MAT_IMPULSO, MAT_SENOIDE, MAT_RAMPA,
               MAT_CONSTANTE, MAT_KRIA_IMPULSO, MAT_KRIA_SENOIDE, MAT_KRIA_RAMPA } isfft_tipo_e;

class isfft_matriz extends uvm_object;
    `uvm_object_utils(isfft_matriz)

    rand isfft_amp_e  amp;
    rand isfft_tipo_e tipo;
    shortint re[64];
    shortint im[64];

    // So os tipos gerais; as matrizes da Kria sao escolhidas pelo teste
    constraint c_tipo { tipo dist { MAT_ALEATORIA := 70, MAT_IMPULSO := 10,
                                    MAT_SENOIDE := 10, MAT_RAMPA := 5, MAT_CONSTANTE := 5 }; }
    constraint c_amp  { amp  dist { AMP_BAIXA := 20, AMP_MEDIA := 30,
                                    AMP_ALTA := 40, AMP_CHEIA := 10 }; }

    function new(string name = "isfft_matriz");
        super.new(name);
    endfunction

    static function int limite(isfft_amp_e a);
        case (a)
            AMP_BAIXA: return 64;
            AMP_MEDIA: return 1024;
            AMP_ALTA:  return 8192;
            default:   return 32767;
        endcase
    endfunction

    function void post_randomize();
        preenche();
    endfunction

    // Gera os 64 elementos a partir de tipo e amp
    function void preenche();
        int lim = limite(amp);
        real pi = 3.14159265358979;
        int a, r, c;
        case (tipo)
            MAT_ALEATORIA: foreach (re[i]) begin
                re[i] = $signed($urandom_range(2*lim)) - lim;
                im[i] = $signed($urandom_range(2*lim)) - lim;
            end
            MAT_IMPULSO: begin
                foreach (re[i]) begin re[i] = 0; im[i] = 0; end
                a = $urandom_range(63);
                re[a] = lim; im[a] = ($urandom_range(1)) ? -lim/2 : 0;
            end
            MAT_SENOIDE: begin
                a = $urandom_range(1, 3);             // ciclos na linha
                foreach (re[i]) begin
                    re[i] = shortint'($rtoi(lim * $sin(2.0 * pi * a * (i % 8) / 8.0)));
                    im[i] = shortint'($rtoi(lim * $cos(2.0 * pi * a * (i / 8) / 8.0)));
                end
            end
            MAT_RAMPA: foreach (re[i]) begin
                re[i] = shortint'((i * lim) / 64);
                im[i] = shortint'(-(i * lim) / 128);
            end
            MAT_CONSTANTE: begin
                a = $signed($urandom_range(2*lim)) - lim;
                foreach (re[i]) begin re[i] = a; im[i] = -a; end
            end
            // As 3 do processamento_otfs.ipynb (Kria), iguais ao evm.py
            MAT_KRIA_IMPULSO: begin
                foreach (re[i]) begin re[i] = 0; im[i] = 0; end
                re[3*8 + 3] = 1000;
            end
            MAT_KRIA_SENOIDE: foreach (re[i]) begin
                // x = linspace(0, 2*pi, 8); sin(X)*500 -> depende da coluna
                c = i % 8;
                re[i] = shortint'($rtoi(500.0 * $sin(2.0 * pi * c / 7.0)));
                im[i] = 0;
            end
            MAT_KRIA_RAMPA: foreach (re[i]) begin
                re[i] = i * 10;
                im[i] = 0;
            end
        endcase
    endfunction

    // Valores antes de truncar para int16 (so a senoide da Kria tem fracao)
    function void ideal(output real xr[64], output real xi[64]);
        real pi = 3.14159265358979;
        foreach (xr[i]) begin
            xr[i] = re[i];
            xi[i] = im[i];
            if (tipo == MAT_KRIA_SENOIDE) xr[i] = 500.0 * $sin(2.0 * pi * (i % 8) / 7.0);
        end
    endfunction

    // Maior |re| ou |im|
    function int amplitude();
        int m = 0, v;
        foreach (re[i]) begin
            v = re[i]; if (v < 0) v = -v; if (v > m) m = v;
            v = im[i]; if (v < 0) v = -v; if (v > m) m = v;
        end
        return m;
    endfunction

    function bit [63:0] palavra(int k);
        return { im[2*k+1], re[2*k+1], im[2*k], re[2*k] };
    endfunction

    virtual function string convert2string();
        return $sformatf("%s %s amplitude=%0d", tipo.name(), amp.name(), amplitude());
    endfunction
endclass

//=============================================================================
// Modelo numerico em ponto flutuante + EVM. Independente do RTL: e a checagem
// da MATEMATICA (o scoreboard ja compara bit a bit com o wrapper da etapa 1).
//=============================================================================
class isfft_modelo;
    // x: 32 palavras de ENTRADA; y: 32 palavras de SAIDA do DUT
    // Devolve EVM (%), o maior erro e o erro medio (LSB)
    static function void avalia(input bit [63:0] x[32], input bit [63:0] y[32],
                                output real evm, output real erro_max,
                                output real erro_medio);
        real xr[64], xi[64];
        bit [31:0] w;
        for (int i = 0; i < 64; i++) begin
            w = (i % 2) ? x[i/2][63:32] : x[i/2][31:0];
            xr[i] = $itor($signed(w[15:0]));
            xi[i] = $itor($signed(w[31:16]));
        end
        avalia_real(xr, xi, y, evm, erro_max, erro_medio);
    endfunction

    // Mesma conta, com a entrada em ponto flutuante (elemento i = linha*8 +
    // coluna). O notebook da Kria calcula o EVM contra a matriz ANTES de
    // truncar para int16 -- o teste da Kria usa esta versao.
    static function void avalia_real(input real xin_r[64], input real xin_i[64],
                                     input bit [63:0] y[32],
                                     output real evm, output real erro_max,
                                     output real erro_medio);
        real xr[8][8], xi[8][8], ar[8][8], ai[8][8], yr, yi, hr, hi;
        real pi = 3.14159265358979;
        real s_err = 0.0, s_ref = 0.0, e, s_abs = 0.0, ang;
        bit [31:0] w;
        int i, j, r, c, k, m;

        for (i = 0; i < 64; i++) begin
            xr[i/8][i%8] = xin_r[i];
            xi[i/8][i%8] = xin_i[i];
        end
        // ifft nas linhas (com 1/8): A[r][k] = 1/8 sum_c X[r][c] e^{+j2pi ck/8}
        for (r = 0; r < 8; r++)
            for (k = 0; k < 8; k++) begin
                ar[r][k] = 0.0; ai[r][k] = 0.0;
                for (c = 0; c < 8; c++) begin
                    ang = 2.0 * pi * c * k / 8.0;
                    ar[r][k] += xr[r][c] * $cos(ang) - xi[r][c] * $sin(ang);
                    ai[r][k] += xr[r][c] * $sin(ang) + xi[r][c] * $cos(ang);
                end
                ar[r][k] /= 8.0; ai[r][k] /= 8.0;
            end
        // fft nas colunas e /8: Y[m][k] = 1/8 sum_r A[r][k] e^{-j2pi rm/8}
        erro_max = 0.0;
        for (j = 0; j < 64; j++) begin
            m = j % 8;  k = j / 8;          // saida em ordem de coluna
            yr = 0.0; yi = 0.0;
            for (r = 0; r < 8; r++) begin
                ang = 2.0 * pi * r * m / 8.0;
                yr += ar[r][k] * $cos(ang) + ai[r][k] * $sin(ang);
                yi += ai[r][k] * $cos(ang) - ar[r][k] * $sin(ang);
            end
            yr /= 8.0; yi /= 8.0;
            w  = (j % 2) ? y[j/2][63:32] : y[j/2][31:0];
            hr = $itor($signed(w[15:0]));
            hi = $itor($signed(w[31:16]));
            e  = (hr - yr) * (hr - yr) + (hi - yi) * (hi - yi);
            s_err += e;
            s_ref += yr * yr + yi * yi;
            s_abs += $sqrt(e);
            if ($sqrt(e) > erro_max) erro_max = $sqrt(e);
        end
        evm        = (s_ref > 0.0) ? $sqrt(s_err / s_ref) * 100.0 : 0.0;
        erro_medio = s_abs / 64.0;
    endfunction

    static function int amplitude(input bit [63:0] x[32]);
        int m = 0, v;
        bit [31:0] w;
        for (int i = 0; i < 64; i++) begin
            w = (i % 2) ? x[i/2][63:32] : x[i/2][31:0];
            v = $signed(w[15:0]);  if (v < 0) v = -v;  if (v > m) m = v;
            v = $signed(w[31:16]); if (v < 0) v = -v;  if (v > m) m = v;
        end
        return m;
    endfunction
endclass
