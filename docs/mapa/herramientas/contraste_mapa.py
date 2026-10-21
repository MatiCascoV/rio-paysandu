"""Contraste WCAG y simulación de daltonismo (Machado 2009, severidad 1) de la paleta del mapa."""
import math, sys

def hx(h):
    h = h.lstrip('#')
    if len(h) == 8:  # AARRGGBB
        a = int(h[:2], 16) / 255; h = h[2:]
    else:
        a = 1.0
    return [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)], a

def lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def delin(c): return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
def lum(rgb): r, g, b = (lin(c) for c in rgb); return 0.2126 * r + 0.7152 * g + 0.0722 * b
def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
def over(fg, a, bg): return [f * a + b * (1 - a) for f, b in zip(fg, bg)]  # mezcla en sRGB, como Skia
def col(h, bg=None):
    rgb, a = hx(h)
    return over(rgb, a, bg) if bg is not None and a < 1 else rgb
def tohex(rgb): return '#' + ''.join(f'{round(max(0, min(1, c)) * 255):02X}' for c in rgb)

M = {
    'protan': [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    'deutan': [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    'tritan': [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}
def sim(rgb, t):
    l = [lin(c) for c in rgb]
    o = [sum(M[t][i][j] * l[j] for j in range(3)) for i in range(3)]
    return [delin(max(0, min(1, c))) for c in o]

def lab(rgb):
    r, g, b = (lin(c) for c in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = (0.2126 * r + 0.7152 * g + 0.0722 * b)
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
def de(a, b): return math.dist(lab(a), lab(b))

PALETAS = {
  'claro': dict(
    terreno='#F3F0E8', cauce='#BCD7EF', orilla='#3F7FBF', arroyo='#3F7FBF',
    margen='#421F6FC0', agua='#801F6FC0', rayado='#B30B3C5D', borde='#0B3C5D', bordeMargen='#0B3C5D',
    contorno='#5E2F00', calle1='#9C8F76', calle2='#B3A890', calle3='#CEC6B6',
    texto='#0B2A3F', textoCalle='#33434F', textoCurso='#164A7A', halo='#F3F0E8'),
  'oscuro': dict(
    terreno='#1B2A37', cauce='#173F63', orilla='#5B9BD5', arroyo='#5B9BD5',
    margen='#3D6CB4FF', agua='#736CB4FF', rayado='#C7E3F4FF', borde='#E3F1FF', bordeMargen='#BFE0FF',
    contorno='#FFD89E', calle1='#7A90A4', calle2='#61778B', calle3='#46596B',
    texto='#EAF2F8', textoCalle='#C9D7E2', textoCurso='#9CCBFF', halo='#1B2A37'),
}

def main():
    for nombre, p in PALETAS.items():
        T = col(p['terreno'])
        margen = col(p['margen'], T)
        agua = col(p['agua'], margen)            # el agua va encima del margen (capa anidada)
        aguaSola = col(p['agua'], T)
        ray_rgb, ray_a = hx(p['rayado'])
        rayado = over(ray_rgb, ray_a, agua)
        # proporción de rayado: 1,4 px de cada 7 px
        prom = [a * 0.8 + r * 0.2 for a, r in zip(agua, rayado)]
        cauce = col(p['cauce'])
        filas = {
            'terreno': T, 'cauce': cauce, 'orilla/arroyo': col(p['orilla']), 'margen (sobre terreno)': margen,
            'agua (sobre margen)': agua, 'rayado (sobre agua)': rayado, 'agua+rayado promedio': prom,
            'borde agua': col(p['borde']), 'borde margen': col(p['bordeMargen']), 'contorno crecida': col(p['contorno']),
            'calle k1': col(p['calle1']), 'calle k2': col(p['calle2']), 'calle k3': col(p['calle3']),
            'texto barrio': col(p['texto']), 'texto calle': col(p['textoCalle']), 'texto arroyo': col(p['textoCurso']),
        }
        print(f'\n=== {nombre} ===')
        print(f'{"elemento":26} {"hex":8} {"vs terreno":>10}')
        for k, v in filas.items():
            print(f'{k:26} {tohex(v):8} {ratio(v, T):10.2f}')
        pares = [
            ('borde agua', 'agua (sobre margen)'), ('borde agua', 'cauce'), ('borde margen', 'margen (sobre terreno)'),
            ('borde margen', 'cauce'), ('contorno crecida', 'agua+rayado promedio'), ('contorno crecida', 'agua (sobre margen)'),
            ('contorno crecida', 'margen (sobre terreno)'), ('rayado (sobre agua)', 'agua (sobre margen)'),
            ('orilla/arroyo', 'cauce'), ('cauce', 'agua (sobre margen)'), ('cauce', 'agua+rayado promedio'),
            ('margen (sobre terreno)', 'agua (sobre margen)'),
            ('texto barrio', 'terreno'), ('texto calle', 'terreno'), ('texto arroyo', 'terreno'),
        ]
        print(f'\n{"par":58} {"WCAG":>6} {"dE":>6} {"dE prot":>8} {"dE deut":>8} {"dE trit":>8}')
        for a, b in pares:
            A, B = filas[a], filas[b]
            print(f'{a + " / " + b:58} {ratio(A, B):6.2f} {de(A, B):6.1f} '
                  f'{de(sim(A, "protan"), sim(B, "protan")):8.1f} {de(sim(A, "deutan"), sim(B, "deutan")):8.1f} '
                  f'{de(sim(A, "tritan"), sim(B, "tritan")):8.1f}')

main()
