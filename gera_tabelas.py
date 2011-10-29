# coding=utf-8
#
# Nosso objetivo é escrever 3 dígitos (D0, D1 e D2) usando
# o playfield do Atari.
#
# A "fonte" usada contém os caracteres "0" a "9" do ZX Spectrum
# (retirados do tilewriter, em http://bit.ly/tfAzR5), que
# são 8x8, mas com uma "borda" que os deixa efetivamente 6x6
#
# O playfield do Atari tem 20 bits de largura (4 bits no PF0
# + 8 bits no PF1 + 8 bits no PF2), o que permite desenhar
# 3 caracteres de 6 bits e deixar 1 bit de espaço entre
# eles (6 + 1 + 6 + 1 + 6 = 20), no seguinte arranjo (0, 1
# e 2 representam os bits do D0, D1 e D2):
#
#    [0000    ][00_11111][1_222222]
#       PF0       PF1       PF2
#
# Note que o D0 está dividido entre o PF0 e o PF1, o D1 entre
# o PF1 e o PF2, e o D2 está inteiro no PF2. Além disso, é
# o PF0 e o PF2 são desenhados "ao contrário".
#
# Isso é muita manipulação de bits pra fazer on-the-fly, então
# vamos gerar tabelas na ROM com os bits que cada registrador
# PFn precisa receber de cada dígito Dn. As tabelas serão:
#
# IMGD0PF0
# IMGD0PF1
# IMGD1PF1
# IMGD2PF2
# IMGD2PF2
#
# Apesar de a primeira e última linha de um caractere sempre
# serem zero, vamos mantê-las para alinhar a tabela em
# múltiplos de 8 (permitindo achar o caractere com ROL/ASL)
#

fonte_original = [
    '003C464A52623C00',
    '0018280808083E00',
    '003C42023C407E00',
    '003C420C02423C00',
    '00081828487E0800',
    '007E407C02423C00',
    '003C407C42423C00',
    '007E020408101000',
    '003C423C42423C00',
    '003C42423E023C00']
    
def inverte(byte):
    invertido = 0
    for bit in range(8):
        invertido = invertido + ((byte & (2**bit)) >> bit << (7-bit))
    return invertido
    
def imprime_tabela(nome):
    tabela = eval(nome)
    print(nome + ":")
    for byte in tabela:
        print("    .BYTE %"+bin(byte)[2:].zfill(8))        

IMGD0PF0 = []
IMGD0PF1 = []
IMGD1PF1 = []
IMGD1PF2 = []
IMGD2PF2 = []

for digito in range(10):
    for linha in range(8):
        byte = int(fonte_original[digito][linha*2:linha*2+2],16)
        IMGD0PF0.append(inverte((byte & 0b01111000) >> 3))
        IMGD0PF1.append((byte & 0b00000110) << 5)        
        IMGD1PF1.append((byte & 0b01111100) >> 2)
        IMGD1PF2.append(inverte((byte & 0b00000010) << 6))
        IMGD2PF2.append(inverte((byte & 0b01111110) >> 1))

imprime_tabela("IMGD0PF0")
imprime_tabela("IMGD0PF1")
imprime_tabela("IMGD1PF1")
imprime_tabela("IMGD1PF2")
imprime_tabela("IMGD2PF2")
