/* ============================================================
   cursor.js — círculo que sigue el puntero (solo mouse/trackpad)
   Evita el error de consola en páginas sin #cursor y no hace
   nada en pantallas táctiles, donde el cursor CSS no aplica.
   ============================================================ */
(function () {
  var cursor = document.getElementById('cursor');
  if (!cursor) return;

  var fino = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  if (!fino) return;

  window.addEventListener('mousemove', function (e) {
    cursor.style.top = e.clientY + 'px';
    cursor.style.left = e.clientX + 'px';
  }, { passive: true });
})();
