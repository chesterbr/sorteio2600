;
; sorteio.asm
;
; Programa que sorteia um número de três dígitos, feito para o
; evento Dev In Vale
;
; O código é livre (vide final do arquivo). Para compilar use o DASM
; (http://dasm-dillon.sourceforge.net/), através do comando:
;
;   dasm sorteio.asm -osorteio.bin -f3
;

    PROCESSOR 6502
    INCLUDE "vcs.h"

; Constantes
SCANLINES_POR_LINHA       = 6       ; Quantas scanlines cada linha do desenho do dígito deve ter
MODO_SELECT               = %0001   ; Mostra/altera o limite superior (GAME_SELECT)
MODO_RODANDO              = %0010   ; Incrementa os dígitos a cada scanline vazia da tela
MODO_PARANDO              = %0100   ; Incrementa um dígito a cada n frames (FIRE)
MODO_PARADO               = %1000   ; Não incrementa mais os dígitos
CHAVE_GAME_SELECT         = %10
CHAVE_GAME_RESET          = %01
CHAVES_GAME_SELECT_RESET  = %11
MAX_FRAMES_POR_INCREMENTO = 25

; RAM (variáveis)
digito0              = $80         ; Centena (0 a 9) exibida na tela usando PF0+PF1
digito1              = $81         ; Dezena  (0 a 9) exibida na tela usando PF1+PF2
digito2              = $82         ; Unidade (0 a 9) exibida na tela usando PF2
indiceIMGD0          = $83         ; Índice dos dígitos 0, 1 e 2 nas tabelas de
indiceIMGD1          = $84         ;   imagens para a scanline atual
indiceIMGD2          = $85
contadorAlturaLinha  = $86         ; Contador de altura (em scanlines) da linha atual
modoAtual            = $87         ; Indica se estamos em MODO_SELECT (escolhendo o limite
                                   ;   máximo do sorteio), MODO_RODANDO (animando em velocidade
                                   ;   total), MODO_PARANDO (reduzindo até parar) ou MODO_PARADO
limiteDigito0        = $88         ; Valor máximo para a centena do número sorteado
valorSelectReset     = $89         ; Guarda status das chaves select/reset no frame anterior
                                   ;   (armazenando os bits correspondentes a eles do SWCHB)
framesPorIncremento  = $8A         ; Quantidade de frames que vamos aguardar antes de um incremento
                                   ;   (apenas no MODO_PARANDO)
contadorFrames       = $8B         ; Contador regressivo de frames (framesPorIncremento a 0) para
                                   ;   o MODO_PARANDO
flagAtualizaDigito   = $8C         ; No MODO_PARANDO, informa ao kernel que o dígito deve ser
                                   ;   incrementado (uma única vez). 
flagResetDigitos    = $8D          ; No MODO_RESET, informa que
                                   ;   os digitos devem ser inicializados com as sementes.
contadorSom          = $8E         ; Conta # de frames em que o som deve se manter ligado
sementeRandom        = $8F         ; Semente usada para inicializar a dezena/unidade e garantir a
                                   ;   aleatoriedade. É necessário porque incrementamos a cada
                                   ;   scanline e paramos a contagem sempre no início da tela -
                                   ;   se começarmos sempre no final 00, vamos ter um subconjungo
                                   ;   fixo de possíveis resultados

; ROM    
    ORG $F000                     ; Início do cartucho (vide Mapa de Memória do Atari)

;;;;; Inicialização do cartucho (roda só uma vez) ;;;;;

InicializaRAM:
    ldx #0                        ; Começa limpando toda a RAM e registros do TIA
    lda #0
LoopZeraVariaveisERegistros:
    sta 0,x
    inx
    bne LoopZeraVariaveisERegistros
VariaveisNaoZero:
    lda #MODO_SELECT              ; Ao ligar o Atari, vamos começar no modo select...
    sta modoAtual
    lda #1                        ; ...e com o limite em 100 (i.e., sorteando de 000 a 099)
    sta limiteDigito0
    sta digito0
    
InicializaSom:
    lda #10                       ; Som mais "percussivo"
    sta AUDC0
    lda #40                       ; Pitch escolhido bem aleatoriamente, confesso
    sta AUDF0
    lda #0                        ; Vamos variar o volume para fazer o som, começa desligado
    sta AUDV0 
    
InicializaGraficos:
    sta WSYNC                     ; Vamos usar um missle para cobrir um pedacinho do playfield
    ldy #8                        ;   que aparece por conta da imprecisão do Score Mode, e pra
LoopPosicaoMissile:               ;   isso é preciso contar os ciclos para posicionar
    dey
    bne LoopPosicaoMissile
    sta RESM0                     ; Posiciona o missile *quase* no lugar certo
    lda #%00110000                ; Stretch do missile 
    sta NUSIZ0                    
    lda #%11000000                ; Deslocamento para corrigir o "quase" acima
    sta WSYNC
    sta HMM0
    sta HMOVE                     ; Executa o deslocamento
    sta WSYNC
    lda #$FF                      
    sta COLUP1                    ; Playfield amarelo
    sta ENAM0                     ; Habilita missile
    lda #%00000010                ; Score mode=1; 
    sta CTRLPF    
    


;;;;; VSYNC ;;;;;

InicioFrame:
    lda #%00000010                ; VSYNC inicia setando o bit 1 deste endereço
    sta VSYNC
    REPEAT 3                      ; ...e dura 3 scanlines (WSYNC=fim da scanline)
        sta WSYNC
    REPEND
    lda #0
    sta VSYNC                     ; VSYNC finaliza limpando o bit 1

;;;;; VBLANK ;;;;;    

ProcessaChavesSelectEReset:       ; Primeira linha do VBLANK
    lda SWCHB                     ; Carrega status das chaves GAME SELECT/GAME RESET no A,
    and #CHAVES_GAME_SELECT_RESET ;   zerando bits que não sejam estes
    eor #CHAVES_GAME_SELECT_RESET ; Inverte status (para ficar 1=pressionado, 0=solto)
    tax                           ; Copia pro X para guardar o valor no final
    cmp valorSelectReset
    beq FimProcessaChaves         ; Nenhuma chave pressionada/solta, vai pra próxima
DefineChavePressionada:
    cmp #CHAVE_GAME_RESET
    beq ResetPressionado
    cmp #CHAVE_GAME_SELECT
    bne FimProcessaChaves
SelectPressionado:
    lda #MODO_SELECT              ; GAME SELECT pressionada - se já estivermos em modo select,
    cmp modoAtual                 ;   incrementa o limite, senão só muda para este modo
    bne SetaModoSelect
    inc limiteDigito0             ; Incrementa o limite do dígito da centena, que é o valor que
    ldy #11                       ;   ele não pode atingir. Se passar de 10 (limite para
    cpy limiteDigito0             ;   centena = 9), volta ele para 1
    bne FimProcessaChaves
    sta limiteDigito0             ; "lda #1" suprimido, aproveitando que MODO_SELECT=1
SetaModoSelect:
    sta modoAtual
    jmp FimProcessaChaves
ResetPressionado:
    lda #MODO_RODANDO             ; Começa a rodar os dígitos
    sta modoAtual
    sta flagResetDigitos          ; ...mas antes garante que eles serão ressetados com a semente
FimProcessaChaves:
    stx valorSelectReset          ; Guarda o status das chaves pro próximo frame
    sta WSYNC
    
ProcessaBotaoJoystick:            ; Segunda linha do VBLANK
    lda modoAtual                 ; Se estamos no MODO_RODANDO...
    cmp #MODO_RODANDO
    bne FimProcessaBotaoJoystick
    lda INPT4                     ; ...e o botão do joystick foi presionado...
    bmi FimProcessaBotaoJoystick
    lda #MODO_PARANDO             ; ...muda para o modo parando, começando por 2 frames
    sta modoAtual                 ;   por incremento
    lda #2
    sta framesPorIncremento
    sta contadorFrames
FimProcessaBotaoJoystick:
    sta WSYNC
    
ModoParando:                      ; Terceira linha do VBLANK
    lda modoAtual
    cmp #MODO_PARANDO
    bne FimModoParando
    dec contadorFrames            ; Marca que um frame dos que faltavam passou
    bne FimModoParando            ; Se passamos os frames que faltavam, aumenta a quantidade
    inc framesPorIncremento       ;   de frames por incremento
    lda framesPorIncremento
    cmp #MAX_FRAMES_POR_INCREMENTO
    bne ResetContadorFrames
MudaParaModoParado:              
    lda #MODO_PARADO              ; Se chegamos no limite de lentidão, muda para o modo parado
    sta modoAtual
    jmp FimModoParando
ResetContadorFrames:    
    lda framesPorIncremento       ; Garante que iremos aguardar tantos frames quanto indicado
    sta contadorFrames            ;   pelo valor atual de framesPorIncremento antes de incrementar
    sta flagAtualizaDigito        ; Executa um incremento no frame atual
FimModoParando:
    sta WSYNC    

MiscStuff:                        ; Quarta linha do VBlank
IncrementaSemente:        
    sed                           ; Modo decimal (para termos dois dígitos)
    lda sementeRandom
    clc
    adc #1
    sta sementeRandom
    cld                           ; Volta ao modo de aritmética normal
DesligaSom:
    lda contadorSom
    beq FimMiscStuff
    dec contadorSom
    lda #0
    sta AUDV0
FimMiscStuff:
    sta WSYNC



    
AjustaDigitos                     ; Quinta linha do VBLANK
    lda modoAtual
    cmp #MODO_SELECT
    beq AjustaDigitosSelect
    cmp #MODO_RODANDO
    bne FimAjustaDigitos
AjustaDigitosAposReset
    lda flagResetDigitos          ; Se acabamos de dar um RESET, a flag estará ligado, e vamos
    beq FimAjustaDigitos          ;   colocar cada nibble de uma semente (BCD) no dígito apropriado
    lda sementeRandom             ; digito1 = nibble da direita da semente
    and #%00001111 
    sta digito1
    lda sementeRandom             ; digito2 = nibble da esquerda da semente
    lsr
    lsr
    lsr
    lsr
    sta digito2
    lda #0                        
    sta digito0                   ; digito0 = 0 (depende do limite, e não tem prob de entropia)
    sta flagResetDigitos          ; Reset da flag
    jmp FimAjustaDigitos
AjustaDigitosSelect
    lda limiteDigito0             ; Os dígitos do MODO_SELECT informam o limite superior, i.e.:
    sta digito0                   ;   a centena tem que ser um a menos que o limite
    dec digito0
    lda #9                        ;   e a dezena/unidade têm que ser "9"
    sta digito1
    sta digito2
FimAjustaDigitos:
    sta WSYNC

PreparaIndicesEContadores:        ; Sexta linha do VBLANK
    lda digito0                   ; Posicao na tabela é 8 vezes o valor do dígito
    asl                           ; 3 shifts = 8 vezes
    asl
    asl
    sta indiceIMGD0
    lda digito1                   ; Mesma coisa para os dígitos 1 e 2
    asl
    asl
    asl
    sta indiceIMGD1
    lda digito2     
    asl
    asl
    asl
    sta indiceIMGD2
    lda #SCANLINES_POR_LINHA      ; Inicaliza contador de altura da linha
    sta contadorAlturaLinha
    ldx #0                        ; X é o nosso contador de scanlines (0-191)
    sta WSYNC

FinalizaVBLANK:
    REPEAT 31                     ; VBLANK tem 37 linhas, mas usamos 6 acima
        sta WSYNC     
    REPEND
    lda #0                        ; Finaliza o VBLANK, "ligando o canhão"
    sta VBLANK  

;;;;; DISPLAY KERNEL ;;;;;
    
Scanline:
    cpx #[SCANLINES_POR_LINHA*8]  ; Se estamos na parte superior desenha os digitos, caso
    bcs DecideIncremento          ;   contrário incrementa (ou não, conforme o modo atual)
    
DesenhaDigitos:
    ldy indiceIMGD0               ; Parte do D0 vai no PF0
    lda (IMGD0PF0,y)
    sta PF0
    lda (IMGD0PF1,y)              ; O restante do D0 vai no PF1, junto com parte do D1...
    ldy indiceIMGD1
    ora (IMGD1PF1,y)
    sta PF1
    lda (IMGD1PF2,y)              ; ...e o restante do D1 vai no PF2, junto o D2
    ldy indiceIMGD2
    ora (IMGD2PF2,y)
    sta PF2
    dec contadorAlturaLinha       ; Quando ultrapassarmos SCANLINES_POR_LINHA de altura
    bne FimScanline               ;   incrementamos os índices de linha e zeramos
    lda #SCANLINES_POR_LINHA      ;   o contador de altura
    sta contadorAlturaLinha
    inc indiceIMGD0
    inc indiceIMGD1
    inc indiceIMGD2
    jmp FimScanline
    
DecideIncremento:
    lda modoAtual
    cmp #MODO_RODANDO             ; No MODO_RODANDO incrementamos o dígito para cada scanline
    beq IncrementaDigitos
    beq FimScanline
    cmp #MODO_PARANDO             ; No MODO_SELECT e MODO_PARADO nunca incrementamos o dígito
    bne FimScanline
    lda flagAtualizaDigito        ; No MODO_PARANDO incrementamos o dígito apenas quando a
    beq FimScanline               ;   flag indicar que isso deve ser feito (com valor não-zero)   
    
IncrementaDigitos:
SomIncremento:
    lda #8                        ; Basta aumentar o volume (no final do frame ele vai ser desligado)
    sta AUDV0
    lda #200
    sta contadorSom
LogicaIncremento:
    lda #10                           ; Dígitos "estouram" quando chegam a 10
    ldy #0
    sty flagAtualizaDigito            ; Se incrementou porque a flag foi acionada, desliga
    inc digito2                       ; Incrementa unidade
    cmp digito2
    bne FimScanline
    sty digito2                       ; Estourou unidade, incrementa dezena
    inc digito1
    cmp digito1
    bne FimScanline
    sty digito1                       ; Estourou dezena, incrementa centena
    inc digito0
    lda limiteDigito0                 ; (o estouro da centena não é no 10, e sim no limte)
    cmp digito0
    bne FimScanline
    sty digito0                       ; Estourou centena, zera todo mundo
    sty digito1
    sty digito2

FimScanline:
    sta WSYNC                     ; Aguarda o final do scanline
    inx                           ; Incrementa o contador e repete até completar a tela
    cpx #191
    bne Scanline
 
;;;;; OVERSCAN ;;;;;

Overscan:
    lda #%01000010                ; "Desliga o canhão:"
    sta VBLANK                    
    REPEAT 30                     ; 30 scanlines de overscan...
        sta WSYNC
    REPEND
    jmp InicioFrame ; ...e começamos tudo de novo!

; Tabelas de bits que devem ser setados para desenhar cada um dos dígitos
; em cada registro do playfield (construídas pelo gera_tabelas.py) a partir
; da fonte do ZX Spectrum

#include "tabelas.asm"

; Configurações no finalzinho do cartucho:

    ORG $FFFA                           
    .WORD InicializaRAM                   ;     NMI
    .WORD InicializaRAM                   ;     RESET
    .WORD InicializaRAM                   ;     IRQ
    
    END

; 
; Copyright 2011 Carlos Duarte do Nascimento (Chester). All rights reserved.
; 
; Redistribution and use in source and binary forms, with or without modification, are
; permitted provided that the following conditions are met:
; 
;    1. Redistributions of source code must retain the above copyright notice, this list of
;       conditions and the following disclaimer.
; 
;    2. Redistributions in binary form must reproduce the above copyright notice, this list
;       of conditions and the following disclaimer in the documentation and/or other materials
;       provided with the distribution.
; 
; THIS SOFTWARE IS PROVIDED BY CHESTER ''AS IS'' AND ANY EXPRESS OR IMPLIED
; WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
; FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> OR
; CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
; SERVICES;  LOSS OF USE, DATA, OR PROFITS;  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
; ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
; ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
; 
; The views and conclusions contained in the software and documentation are those of the
; authors and should not be interpreted as representing official policies, either expressed
; or implied, of Chester.
;
