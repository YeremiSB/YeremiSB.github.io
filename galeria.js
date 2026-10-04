/* ============================================================
   galeria.js — filtros por categoría + lightbox
   ============================================================ */
(function () {
  var grid = document.getElementById('galeria');
  if (!grid) return;

  var items = Array.prototype.slice.call(grid.querySelectorAll('.foto-item'));
  var botones = Array.prototype.slice.call(document.querySelectorAll('.filtro'));

  /* ---------- Filtros ---------- */
  function aplicar(cat) {
    items.forEach(function (item) {
      var cats = (item.dataset.cat || '').split(' ');
      var visible = cat === 'todas' || cats.indexOf(cat) !== -1;
      item.classList.toggle('oculto', !visible);
    });
    botones.forEach(function (b) {
      b.classList.toggle('activo', b.dataset.filtro === cat);
    });
  }

  botones.forEach(function (b) {
    b.addEventListener('click', function () {
      aplicar(b.dataset.filtro);
    });
  });

  /* ---------- Lightbox ---------- */
  var lb = document.getElementById('lightbox');
  if (!lb) return;

  var lbImg = document.getElementById('lb-img');
  var lbTitulo = document.getElementById('lb-titulo');
  var lbTexto = document.getElementById('lb-texto');
  var lbNum = document.getElementById('lb-num');
  var visibles = [];
  var actual = 0;

  function listaVisible() {
    return items.filter(function (i) { return !i.classList.contains('oculto'); });
  }

  function pintar() {
    var item = visibles[actual];
    if (!item) return;
    var img = item.querySelector('img');
    lbImg.src = img.getAttribute('src');
    lbImg.alt = img.getAttribute('alt') || '';
    lbTitulo.textContent = item.dataset.titulo || '';
    lbTexto.textContent = item.dataset.texto || '';
    lbNum.textContent = (actual + 1) + ' / ' + visibles.length;
  }

  function abrir(indice) {
    visibles = listaVisible();
    actual = indice;
    pintar();
    lb.classList.add('abierto');
    lb.setAttribute('aria-hidden', 'false');
    document.body.style.overflow = 'hidden';
    document.getElementById('lb-cerrar').focus();
  }

  function cerrar() {
    lb.classList.remove('abierto');
    lb.setAttribute('aria-hidden', 'true');
    document.body.style.overflow = '';
    if (visibles[actual]) visibles[actual].focus();
  }

  function mover(paso) {
    if (!visibles.length) return;
    actual = (actual + paso + visibles.length) % visibles.length;
    pintar();
  }

  items.forEach(function (item) {
    item.addEventListener('click', function () {
      abrir(listaVisible().indexOf(item));
    });
  });

  document.getElementById('lb-cerrar').addEventListener('click', cerrar);
  document.getElementById('lb-prev').addEventListener('click', function () { mover(-1); });
  document.getElementById('lb-next').addEventListener('click', function () { mover(1); });

  lb.addEventListener('click', function (e) {
    if (e.target === lb) cerrar();
  });

  document.addEventListener('keydown', function (e) {
    if (!lb.classList.contains('abierto')) return;
    if (e.key === 'Escape') cerrar();
    if (e.key === 'ArrowLeft') mover(-1);
    if (e.key === 'ArrowRight') mover(1);
  });
})();
