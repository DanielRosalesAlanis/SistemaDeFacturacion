// Confirmación antes de acciones irreversibles (botones con data-confirmar).
// Archivo externo: la política CSP no permite JavaScript en línea.
document.addEventListener("submit", (evento) => {
  const boton = evento.submitter;
  const mensaje = boton && boton.dataset.confirmar;
  if (mensaje && !window.confirm(mensaje)) {
    evento.preventDefault();
  }
});
