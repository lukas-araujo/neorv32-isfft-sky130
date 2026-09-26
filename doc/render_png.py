#!/usr/bin/env python3
"""Converte um SVG de doc/ em PNG (Chromium do Playwright).
Uso: python3 render_png.py [diagrama_chip.svg]"""
import os, re, sys
from playwright.sync_api import sync_playwright
d = os.path.dirname(os.path.abspath(__file__))
nome = sys.argv[1] if len(sys.argv) > 1 else "diagrama_chip.svg"
svg = open(os.path.join(d, nome)).read()
w, h = (int(v) for v in re.search(r'width="(\d+)" height="(\d+)"', svg).groups())
png = os.path.join(d, nome[:-4] + ".png")
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": w, "height": h})
    pg.set_content(f"<html><body style='margin:0'>{svg}</body></html>")
    pg.screenshot(path=png, clip={"x": 0, "y": 0, "width": w, "height": h})
    b.close()
print(os.path.basename(png))
