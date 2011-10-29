;
; sorteio.asm
;
; Programa que sorteia um número de três dígitos feito para o
; evento Dev In Vale
;
; O código é livre (vide final do arquivo). Para compilar use o DASM
; (http://dasm-dillon.sourceforge.net/), através do comando:
;
;   dasm hello.asm -ohello.bin -f3
;

    PROCESSOR 6502
    INCLUDE "vcs.h"

; Constantes
SCANLINES_POR_LINHA      = 4
MODO_SELECT              = %001
MODO_RODANDO             = %010
MODO_PARANDO             = %100
CHAVE_GAME_SELECT        = %10
CHAVE_GAME_RESET         = %01
CHAVES_GAME_SELECT_RESET = %11

; RAM (variáveis)
digito0             = $80         ; Centena (0 a 9) exibida na tela usando PF0+PF1
digito1             = $81         ; Dezena  (0 a 9) exibida na tela usando PF1+PF2
digito2             = $82         ; Unidade (0 a 9) exibida na tela usando PF2
indiceIMGD0         = $83         ; Índice dos dígitos 0, 1 e 2 nas tabelas de
indiceIMGD1         = $84         ;   imagens para a scanline atual
indiceIMGD2         = $85
contadorAlturaLinha = $86         ; Contador de altura (em scanlines) da linha atual
modoAtual           = $87         ; Indica se estamos em MODO_SELECT (escolhendo o limite
                                  ;   máximo do sorteio), MODO_RODANDO (animando em velocidade
                                  ;   total) ou MODO_PARANDO (reduzindo até sortear)
limiteDigito0       = $88         ; Valor máximo para a centena do número sorteado
valorSelectReset    = $89         ; Guarda status das chaves select/reset no frame anterior
                                  ;   (armazenando os bits correspondentes a eles do SWCHB)


; ROM    
    ORG $F000                     ; Início do cartucho (vide Mapa de Memória do Atari)
    
InicializaRAM:
    lda #MODO_SELECT              ; Ao ligar, começa em MODO_SELECT com o valor 100, i.e.:
    sta modoAtual
    lda #1                        ;   - centena (e limite máximo) no 1;
    sta limiteDigito0
    sta digito0
    lda #0                        ;   - dezena e unidade no 0.
    sta digito1
    sta digito2
    sta valorSelectReset          ; Console ligado sem nenhuma chave

;;;;; VSYNC ;;;;

InicioFrame:
    lda #%00000010                ; VSYNC inicia setando o bit 1 deste endereço
    sta VSYNC
    REPEAT 3                      ; ...e dura 3 scanlines (WSYNC=fim da scanline)
        sta WSYNC
    REPEND
    lda #0
    sta VSYNC                     ; VSYNC finaliza limpando o bit 1

;;;;; VBLANK ;;;;;    

DefineModoAtual:                  ; Primeira linha do VBLANK
    lda SWCHB                     ; Carrega status das chaves GAME SELECT/GAME RESET no A,
    and #CHAVES_GAME_SELECT_RESET ;   zerando bits que não sejam estes
    eor #CHAVES_GAME_SELECT_RESET ; Inverte status (para ficar 1=pressionado, 0=solto)
    tax                           ; Copia pro X para guardar o valor no final
    cmp valorSelectReset
    beq FimDefineModoAtual        ; Nenhuma chave pressionada/solta, vai pra próxima
DefineChavePressionada:
    cmp #CHAVE_GAME_RESET
    beq ResetPressionado
    cmp #CHAVE_GAME_SELECT
    bne FimDefineModoAtual
SelectPressionado:
    lda #MODO_SELECT              ; GAME SELECT pressionada - se já estivermos em modo select,
    cmp modoAtual                 ;   incrementa o limite, senão só muda para este modo
    bne DefineModoSelect
    inc limiteDigito0             ; incrementa o limite (TODO: checar overflow)
DefineModoSelect:
    sta modoAtual
    lda limiteDigito0
    sta digito0
    lda #0
    sta digito1
    sta digito2
    jmp FimDefineModoAtual ; TODO mudar pra beq (ganha 1 byte)
ResetPressionado:
    lda #MODO_RODANDO             ; Começa a rodar (TODO incluir semente de randomizacao)
    sta modoAtual
FimDefineModoAtual:
    stx valorSelectReset          ; Guarda o status das chaves pro próximo frame
    sta WSYNC

AjustaCores:                      ; Segunda linha do VBLANK
    lda #$00        
    sta ENABL                     ; Desliga a ball, os missiles e os players
    sta ENAM0
    sta ENAM1
    sta GRP0
    sta GRP1
    sta COLUBK                    ; Cor de fundo (preto)
    sta COLUP0                    ; Cor do P0 (preto, pro score mode)
    lda #$FF                      ; Cor do playfield (possivelmente amarelo)
    sta COLUP1      
    lda #$02                      ; Reflection=0, Score mode=1
    sta CTRLPF    
    ldx #0                        ; X é o nosso contador de scanlines (0-191)
    sta WSYNC
    
AjustaDigitos:                    ; Terceira linha do VBLANK
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
    sta WSYNC

FinalizaVBLANK:
    REPEAT 34                     ; VBLANK tem 37 linhas, mas usamos 3 acima
        sta WSYNC     
    REPEND
    lda #0                        ; Finaliza o VBLANK, "ligando o canhão"
    sta VBLANK  

;;;;; DISPLAY KERNEL ;;;;;
    
Scanline:
    cpx #[SCANLINES_POR_LINHA*8]  ; Se estamos na parte superior desenha os digitos, caso
    bcs DecideValorDigitos          ; contrário incrementa (ou não) conforme o modo atual
    
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
    
DecideValorDigitos:
    lda modoAtual
    cmp #MODO_SELECT
    beq FimScanline
    ; outros modos aqui
    
IncrementaRandom:
    lda #10
    ldy #0
    inc digito2                       ; Incrementa unidade
    cmp digito2
    bne FimScanline
    sty digito2                       ; Estourou unidade, incrementa dezena
    inc digito1
    cmp digito1
    bne FimScanline
    sty digito1                       ; Estourou dezena, incrementa centena
    inc digito0
    cmp digito0
    bne FimScanline
    sty digito0                       ; Estourou centena, zera todo mundo
    sty digito1
    sty digito2

;;;;; OVERSCAN ;;;;;

FimScanline:
    sta WSYNC                     ; Aguarda o final do scanline
    inx                           ; Incrementa o contador e repete até completar a tela
    cpx #191
    bne Scanline
 
Overscan:
    lda #%01000010                ; "Desliga o canhão:"
    sta VBLANK                    ; 
    REPEAT 30                     ; 30 scanlines de overscan...
        sta WSYNC
    REPEND
    jmp InicioFrame ; ...e começamos tudo de novo!

IMGD0PF0:
    .BYTE %00000000
    .BYTE %11100000
    .BYTE %00010000
    .BYTE %10010000
    .BYTE %01010000
    .BYTE %00110000
    .BYTE %11100000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11000000
    .BYTE %10100000
    .BYTE %10000000
    .BYTE %10000000
    .BYTE %10000000
    .BYTE %11100000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11100000
    .BYTE %00010000
    .BYTE %00000000
    .BYTE %11100000
    .BYTE %00010000
    .BYTE %11110000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11100000
    .BYTE %00010000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %00010000
    .BYTE %11100000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %11000000
    .BYTE %10100000
    .BYTE %10010000
    .BYTE %11110000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11110000
    .BYTE %00010000
    .BYTE %11110000
    .BYTE %00000000
    .BYTE %00010000
    .BYTE %11100000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11100000
    .BYTE %00010000
    .BYTE %11110000
    .BYTE %00010000
    .BYTE %00010000
    .BYTE %11100000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11110000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11100000
    .BYTE %00010000
    .BYTE %11100000
    .BYTE %00010000
    .BYTE %00010000
    .BYTE %11100000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11100000
    .BYTE %00010000
    .BYTE %00010000
    .BYTE %11100000
    .BYTE %00000000
    .BYTE %11100000
    .BYTE %00000000
IMGD0PF1:
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %11000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %11000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %01000000
    .BYTE %11000000
    .BYTE %01000000
    .BYTE %10000000
    .BYTE %00000000
IMGD1PF1:
    .BYTE %00000000
    .BYTE %00001111
    .BYTE %00010001
    .BYTE %00010010
    .BYTE %00010100
    .BYTE %00011000
    .BYTE %00001111
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000110
    .BYTE %00001010
    .BYTE %00000010
    .BYTE %00000010
    .BYTE %00000010
    .BYTE %00001111
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00001111
    .BYTE %00010000
    .BYTE %00000000
    .BYTE %00001111
    .BYTE %00010000
    .BYTE %00011111
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00001111
    .BYTE %00010000
    .BYTE %00000011
    .BYTE %00000000
    .BYTE %00010000
    .BYTE %00001111
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000010
    .BYTE %00000110
    .BYTE %00001010
    .BYTE %00010010
    .BYTE %00011111
    .BYTE %00000010
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00011111
    .BYTE %00010000
    .BYTE %00011111
    .BYTE %00000000
    .BYTE %00010000
    .BYTE %00001111
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00001111
    .BYTE %00010000
    .BYTE %00011111
    .BYTE %00010000
    .BYTE %00010000
    .BYTE %00001111
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00011111
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000010
    .BYTE %00000100
    .BYTE %00000100
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00001111
    .BYTE %00010000
    .BYTE %00001111
    .BYTE %00010000
    .BYTE %00010000
    .BYTE %00001111
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00001111
    .BYTE %00010000
    .BYTE %00010000
    .BYTE %00001111
    .BYTE %00000000
    .BYTE %00001111
    .BYTE %00000000
IMGD1PF2:
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000001
    .BYTE %00000000
    .BYTE %00000000
IMGD2PF2:
    .BYTE %00000000
    .BYTE %01111000
    .BYTE %11000100
    .BYTE %10100100
    .BYTE %10010100
    .BYTE %10001100
    .BYTE %01111000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00110000
    .BYTE %00101000
    .BYTE %00100000
    .BYTE %00100000
    .BYTE %00100000
    .BYTE %11111000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %01111000
    .BYTE %10000100
    .BYTE %10000000
    .BYTE %01111000
    .BYTE %00000100
    .BYTE %11111100
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %01111000
    .BYTE %10000100
    .BYTE %01100000
    .BYTE %10000000
    .BYTE %10000100
    .BYTE %01111000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %00100000
    .BYTE %00110000
    .BYTE %00101000
    .BYTE %00100100
    .BYTE %11111100
    .BYTE %00100000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11111100
    .BYTE %00000100
    .BYTE %01111100
    .BYTE %10000000
    .BYTE %10000100
    .BYTE %01111000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %01111000
    .BYTE %00000100
    .BYTE %01111100
    .BYTE %10000100
    .BYTE %10000100
    .BYTE %01111000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %11111100
    .BYTE %10000000
    .BYTE %01000000
    .BYTE %00100000
    .BYTE %00010000
    .BYTE %00010000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %01111000
    .BYTE %10000100
    .BYTE %01111000
    .BYTE %10000100
    .BYTE %10000100
    .BYTE %01111000
    .BYTE %00000000
    .BYTE %00000000
    .BYTE %01111000
    .BYTE %10000100
    .BYTE %10000100
    .BYTE %11111000
    .BYTE %10000000
    .BYTE %01111000
    .BYTE %00000000
    
    ORG $FFFA                           ; Configurações que ficam no finalzinho do cartucho:
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
