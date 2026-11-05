# Changelog

## Unreleased

- Aceptar y entregar misiones solo al hablar con el PNJ (opciones separadas; Mayús para hacerlo a mano). Acepta
  lo que conviene (no grises ni repetibles, salvo que la ruta las pida; nunca las ignoradas ni las de «Evitar») y
  deja al jugador las de JcJ, las que da un objeto, las que piden elegir recompensa o pagar.
- Misiones aprendidas: las nuevas de Forever que QuestieDB no tiene se aprenden al hacerlas (dónde se cogen, dónde
  se terminan los objetivos, dónde se entregan y su XP) y se proponen a los demás personajes de la cuenta, con la
  misma facción y, hasta que la acepte otra, la misma clase.
- Siguiente zona: un solo recorrido de la base indexa todos los mapas (troceado por fotogramas) y recomienda las
  zonas con más XP de misiones disponibles para tu nivel, facción, raza y clase. Sale en la ventana cuando quedan
  3 pasos o menos; `/ruta zonas` da las 3 mejores. Cambiar de zona ya no vuelve a recorrer la base.
- Con montura, los tiempos se estiman con la velocidad real (`GetUnitSpeed`) en vez de la de a pie.
- Clic en un paso o en «Evitar»: flecha allí y mapa abierto en la zona (no en combate); flecha de TomTom si
  está instalado. Opciones para ambas cosas.
- Sección «Evitar» bajo la ruta: misiones del diario que conviene abandonar o dejar para luego y cercanas que
  no merecen el desvío, con su XP por hora; opción para ocultarla. Poda final del planificador para que las del
  diario también puedan salir de la ruta.
- Primera versión: ruta de misiones por mapa con QuestieDB, cadenas, descarte de lo que no compensa, flecha al
  siguiente paso, ventana con los próximos pasos, ignorar misiones y opciones.
