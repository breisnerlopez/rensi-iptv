/// Posición de inicio (ms) para un episodio NO-actual de la cola de reproducción.
///
/// Si el episodio ya se vio prácticamente entero (≥95% del total) devuelve 0; si
/// no, la posición guardada. Sin este tope, al auto-avanzar media_kit haría seek
/// cerca del final de un episodio ya visto → emite `completed` al instante → lo
/// salta y cascada al episodio equivocado (el usuario percibe "no continúa" o
/// "salta al episodio equivocado"). El ítem SELECCIONADO no usa esto (reanuda
/// donde quedó); solo los de más adelante en la cola.
int queuedItemStartMs(int watchedMs, int totalMs) {
  if (totalMs > 0 && watchedMs >= totalMs * 0.95) return 0;
  return watchedMs;
}
