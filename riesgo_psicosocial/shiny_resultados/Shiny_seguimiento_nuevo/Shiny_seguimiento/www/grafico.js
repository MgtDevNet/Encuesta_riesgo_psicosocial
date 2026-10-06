/* grafico.js
   Cruceta, tooltip y recorrido con el teclado del grafico de avance acumulado
   que dibuja grafico_acumulado() en Modules/mod_seguimiento.R. Lleva dos series:
   la cobertura (x, y) y las encuestas efectivas (y2), que puede no venir.

   Todo pasa en el navegador: mover el cursor no le habla al servidor, o cada
   pixel seria un viaje a R y el tooltip iria a tirones.

   El manejador se instala una sola vez sobre document y trabaja delegado, como
   el del listado: renderUI() rehace el grafico entero cada vez que cambia un
   filtro, y un listener pegado al nodo se iria con el nodo viejo.

   Las coordenadas y los textos vienen ya resueltos en data-serie: R los calculo
   con fmt_num()/fmt_pct(), asi que aqui no se formatea ningun numero. Los
   textos entran con textContent y nunca con innerHTML. */

(function () {
  "use strict";

  var SEL = ".grafico-acum";

  function caja_de(e) {
    return (e.target && e.target.closest) ? e.target.closest(SEL) : null;
  }

  function serie(caja) {
    if (caja._serie === undefined) {
      try { caja._serie = JSON.parse(caja.getAttribute("data-serie")); }
      catch (err) { caja._serie = null; }
    }
    return caja._serie;
  }

  function piezas(caja) {
    if (!caja._p) {
      caja._p = {
        svg:  caja.querySelector(".graf-svg"),
        guia: caja.querySelector(".graf-guia"),
        pto:  caja.querySelector(".graf-punto-cursor:not(.comp):not(.cit)"),
        pto2: caja.querySelector(".graf-punto-cursor.comp"),
        pto3: caja.querySelector(".graf-punto-cursor.cit"),
        tip:  caja.querySelector(".grafico-tip"),
        voz:  caja.querySelector(".grafico-voz")
      };
    }
    return caja._p;
  }

  function util(caja) {
    var s = serie(caja), p = piezas(caja);
    return s && s.x && s.x.length && p.svg && p.tip;
  }

  /* El SVG escala uniforme (preserveAspectRatio + height:auto), asi que basta
     una regla de tres entre el ancho pintado y el del viewBox. */
  function escala(p) {
    var r = p.svg.getBoundingClientRect();
    var vb = p.svg.viewBox.baseVal;
    return (r.width && vb.width) ? r.width / vb.width : 0;
  }

  /* El puntero apunta a una fecha, no a una linea de 2 pixeles: se toma el dia
     mas cercano en el eje x y no hace falta acertarle al punto. */
  function indice(caja, clientX) {
    var s = serie(caja), p = piezas(caja);
    var esc = escala(p);
    if (!esc) return 0;
    var vx = (clientX - p.svg.getBoundingClientRect().left) / esc;
    var mejor = 0, dmin = Infinity;
    for (var i = 0; i < s.x.length; i++) {
      var d = Math.abs(s.x[i] - vx);
      if (d < dmin) { dmin = d; mejor = i; }
    }
    return mejor;
  }

  function fila(clase, valor, rotulo) {
    var f = document.createElement("div");
    f.className = "tip-fila " + clase;
    var v = document.createElement("span");
    v.className = "tip-valor";
    v.textContent = valor;
    f.appendChild(v);
    if (rotulo) {
      var r = document.createElement("span");
      r.className = "tip-rotulo";
      r.textContent = rotulo;
      f.appendChild(r);
    }
    return f;
  }

  function mostrar(caja, i, con_voz) {
    if (!util(caja)) return;
    var s = serie(caja), p = piezas(caja);
    i = Math.max(0, Math.min(s.x.length - 1, i));
    caja._i = i;

    var x = s.x[i], y = s.y[i];
    p.guia.setAttribute("x1", x);
    p.guia.setAttribute("x2", x);
    p.pto.setAttribute("cx", x);
    p.pto.setAttribute("cy", y);
    /* La segunda serie --las encuestas efectivas-- solo existe en el grafico de
       cobertura; cuando no viene, el punto de abajo tampoco esta. */
    if (p.pto2 && s.y2) {
      p.pto2.setAttribute("cx", x);
      p.pto2.setAttribute("cy", s.y2[i]);
    }
    /* La de citados (y3) solo viene cuando hay agenda cargada. */
    if (p.pto3 && s.y3) {
      p.pto3.setAttribute("cx", x);
      p.pto3.setAttribute("cy", s.y3[i]);
    }
    caja.classList.add("activo");

    /* El valor manda y el rotulo lo acompana: quien mira ya sabe que serie es,
       lo que busca es el numero. */
    var t = p.tip;
    t.textContent = "";
    t.appendChild(fila("tip-fecha", s.t[i], ""));
    /* Los citados arriba, como su curva, y pegados a los que de ellos no han
       respondido, que es la cifra de control. */
    if (s.ci) {
      t.appendChild(fila("tip-cit", s.ci[i], "citados"));
      t.appendChild(fila("tip-sr", s.sr[i], "sin responder"));
    }
    t.appendChild(fila("tip-acum", s.a[i], "cobertura"));
    t.appendChild(fila("tip-dia", s.nu[i], "ese día"));
    if (s.p[i] !== "—") t.appendChild(fila("tip-pct", s.p[i], "de la meta"));
    if (s.c) {
      t.appendChild(fila("tip-comp", s.c[i], "efectivas"));
      t.appendChild(fila("tip-ef", s.ef[i], "efectividad"));
    }
    t.hidden = false;

    var esc = escala(p);
    var rs = p.svg.getBoundingClientRect();
    var rc = caja.getBoundingClientRect();
    var ox = rs.left - rc.left, oy = rs.top - rc.top;
    var w = t.offsetWidth, h = t.offsetHeight;

    var izq = ox + x * esc;
    izq = Math.max(w / 2 + 2, Math.min(rc.width - w / 2 - 2, izq));

    /* Encima del punto mientras quepa; si no, debajo, para no salirse de la
       tarjeta ni tapar la propia curva. */
    var arr = oy + y * esc - h - 12;
    t.classList.toggle("abajo", arr < 0);
    t.style.left = izq + "px";
    t.style.top  = (arr < 0 ? oy + y * esc + 14 : arr) + "px";

    /* Solo con el teclado: anunciar en cada pixel del raton seria un chorro de
       voz que nadie pidio. */
    if (con_voz && p.voz) {
      p.voz.textContent = s.t[i] + ": " +
                          (s.ci ? s.ci[i] + " citados, " + s.sr[i] +
                                  " sin responder, " : "") +
                          s.a[i] + " de cobertura, " +
                          s.nu[i] + " ese día" +
                          (s.c ? ", " + s.c[i] + " efectivas, " + s.ef[i] +
                                 " de efectividad" : "") + ".";
    }
  }

  function ocultar(caja) {
    caja.classList.remove("activo");
    var p = piezas(caja);
    if (p.tip) p.tip.hidden = true;
  }

  document.addEventListener("pointermove", function (e) {
    var caja = caja_de(e);
    if (caja) mostrar(caja, indice(caja, e.clientX), false);
  }, { passive: true });

  /* pointerleave no burbujea; pointerout si, y basta con descartar los saltos
     entre hijos del mismo grafico. */
  document.addEventListener("pointerout", function (e) {
    var caja = caja_de(e);
    if (!caja) return;
    if (e.relatedTarget && caja.contains(e.relatedTarget)) return;
    ocultar(caja);
  });

  document.addEventListener("keydown", function (e) {
    var caja = caja_de(e);
    if (!caja || !util(caja)) return;
    var n = serie(caja).x.length;
    var i = (typeof caja._i === "number") ? caja._i : n - 1;

    switch (e.key) {
      case "ArrowRight": i = Math.min(n - 1, i + 1); break;
      case "ArrowLeft":  i = Math.max(0, i - 1);     break;
      case "Home":       i = 0;                      break;
      case "End":        i = n - 1;                  break;
      case "Escape":     ocultar(caja); caja.blur(); return;
      default: return;
    }
    e.preventDefault();
    mostrar(caja, i, true);
  });

  document.addEventListener("focusout", function (e) {
    var caja = caja_de(e);
    if (caja) ocultar(caja);
  });

  /* Al cambiar el ancho las coordenadas guardadas quedan viejas. */
  window.addEventListener("resize", function () {
    var cajas = document.querySelectorAll(SEL + ".activo");
    for (var i = 0; i < cajas.length; i++) ocultar(cajas[i]);
  });
})();
