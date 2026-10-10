# -*- coding: utf-8 -*-
"""
revisar_plantillas.py - Valida las plantillas web antes de publicarlas.

Comprueba: estructura HTML, enlaces internos rotos, metadatos, enlaces de
WhatsApp, responsive y peso de cada archivo.
"""

import os
import re
import sys
from html.parser import HTMLParser

RAIZ = os.path.dirname(os.path.abspath(__file__))
SALTO = "\n"

VACIAS = {"meta", "link", "br", "hr", "img", "input", "source", "area", "base",
          "col", "embed", "param", "track", "wbr"}


class Revisor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.pila = []
        self.errores = []
        self.etiquetas = {}
        self.hay_viewport = False
        self.hay_title = False
        self.hay_descripcion = False
        self.enlaces = []
        self.enlaces_whatsapp = 0

    def handle_starttag(self, etiqueta, atributos):
        atributos = dict(atributos)
        self.etiquetas[etiqueta] = self.etiquetas.get(etiqueta, 0) + 1

        if etiqueta == "title":
            self.hay_title = True
        if etiqueta == "meta":
            nombre = (atributos.get("name") or "").lower()
            if nombre == "viewport":
                self.hay_viewport = True
            if nombre == "description":
                self.hay_descripcion = True
        if etiqueta == "a" and atributos.get("href"):
            self.enlaces.append(atributos["href"])
        if atributos.get("href", "").startswith("https://wa.me/") or \
           atributos.get("action", "").startswith("https://wa.me/"):
            self.enlaces_whatsapp += 1
        if etiqueta == "form" and "wa.me" in str(atributos):
            self.enlaces_whatsapp += 1

        if etiqueta in VACIAS:
            return
        self.pila.append((etiqueta, self.getpos()[0]))

    def handle_endtag(self, etiqueta):
        if etiqueta in VACIAS:
            return
        if not self.pila:
            self.errores.append("Cierre de </%s> sin apertura (linea %d)"
                                % (etiqueta, self.getpos()[0]))
            return
        abierta, linea = self.pila.pop()
        if abierta != etiqueta:
            self.errores.append("Se esperaba </%s> (abierta en linea %d) pero se "
                                "encontro </%s> en linea %d"
                                % (abierta, linea, etiqueta, self.getpos()[0]))

    def cerrar(self):
        for etiqueta, linea in self.pila:
            self.errores.append("Etiqueta <%s> abierta en linea %d sin cerrar"
                                % (etiqueta, linea))
        return self.errores


def revisar_archivo(ruta):
    with open(ruta, encoding="utf-8") as f:
        contenido = f.read()

    revisor = Revisor()
    revisor.feed(contenido)
    errores = revisor.cerrar()

    # Enlaces internos
    base = os.path.dirname(ruta)
    rotos = []
    for enlace in revisor.enlaces:
        if enlace.startswith(("http", "mailto:", "tel:", "#", "javascript:")):
            continue
        destino = os.path.normpath(os.path.join(base, enlace.split("#")[0]))
        if enlace.split("#")[0] and not os.path.exists(destino):
            rotos.append(enlace)

    peso = os.path.getsize(ruta) / 1024
    estilos = contenido.count("<style")
    scripts = contenido.count("<script")
    responsive = "@media" in contenido
    colores = len(set(re.findall(r"#[0-9a-fA-F]{6}", contenido)))

    return {
        "ruta": os.path.relpath(ruta, RAIZ),
        "peso": peso,
        "errores_estructura": errores,
        "enlaces_rotos": rotos,
        "viewport": revisor.hay_viewport,
        "title": revisor.hay_title,
        "descripcion": revisor.hay_descripcion,
        "whatsapp": revisor.enlaces_whatsapp,
        "responsive": responsive,
        "estilos": estilos,
        "scripts": scripts,
        "secciones": revisor.etiquetas.get("section", 0),
        "colores": colores,
        "lineas": contenido.count("\n") + 1,
    }


def main():
    archivos = []
    for raiz, _, nombres in os.walk(RAIZ):
        for nombre in nombres:
            if nombre.endswith(".html"):
                archivos.append(os.path.join(raiz, nombre))
    archivos.sort()

    if not archivos:
        print("No se encontraron archivos .html")
        return 1

    print("=" * 74)
    print("REVISION DE PLANTILLAS WEB")
    print("=" * 74)

    problemas = 0
    for ruta in archivos:
        r = revisar_archivo(ruta)
        print(SALTO + "-" * 74)
        print("ARCHIVO:", r["ruta"])
        print("-" * 74)
        print("  Peso            : %.1f KB (%d lineas)" % (r["peso"], r["lineas"]))
        print("  Secciones       : %d" % r["secciones"])
        print("  Responsive      : %s" % ("SI" if r["responsive"] else "NO"))
        print("  Viewport movil  : %s" % ("SI" if r["viewport"] else "NO"))
        print("  Titulo          : %s" % ("SI" if r["title"] else "NO"))
        print("  Meta descripcion: %s" % ("SI" if r["descripcion"] else "NO"))
        print("  Enlaces WhatsApp: %d" % r["whatsapp"])
        print("  Colores unicos  : %d" % r["colores"])

        if r["errores_estructura"]:
            problemas += len(r["errores_estructura"])
            print("  ERRORES DE ESTRUCTURA:")
            for e in r["errores_estructura"]:
                print("    - " + e)
        else:
            print("  Estructura HTML : CORRECTA")

        if r["enlaces_rotos"]:
            problemas += len(r["enlaces_rotos"])
            print("  ENLACES ROTOS: " + ", ".join(r["enlaces_rotos"]))

        if r["peso"] > 120:
            print("  AVISO: pesa mas de 120 KB")

    print(SALTO + "=" * 74)
    if problemas:
        print("RESULTADO: %d problema(s) encontrado(s)." % problemas)
    else:
        print("RESULTADO: todas las plantillas estan correctas.")
    print("=" * 74)
    return 0 if problemas == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
