# Changelog

## 0.3.0 (06-11-2026)

- Datos de guías de subida como respaldo (`GuideData.lua`, 477 misiones): donde la base de Questie no ubica una
  misión, la ruta usa su recogida, sus objetivos y su entrega. Si Questie la ubica, manda Questie. Opción nueva
  «Usar datos de guías», activada por defecto.
- Siguiente zona según la secuencia de zonas por nivel de las guías de subida (las zonas que hacen a tu nivel van
  primero, aunque estén en otro continente). Antes, a nivel 20, un humano veía Los Baldíos como primera opción;
  ahora, Costa Oscura, Loch Modan y Crestagrana.
- La siguiente zona cuenta el viaje: a pie, con los vuelos que conoces (tiempos medidos de Forever en
  `FlightData.lua`) y en barco o zepelín entre continentes. A la XP de cada zona se le resta la que dejarías de
  ganar viajando, y una zona de otro continente a la que sabes llegar ya no va siempre detrás. `/ruta zonas`
  muestra los minutos de viaje.

## 0.2.0 (06-11-2026)

- Planificador más fino, calibrado con guías de subida de Forever (sus datos no van en el addon): cada misión
  vale también por lo que abre su cadena, las entregas se hacen al pasar, dos objetivos de misiones distintas a
  150 yd o menos cuentan como trabajo compartido y las misiones del mismo dador descartadas por ritmo se prueban
  juntas como campamento.

## 0.1.1 (05-11-2026)

- The addon list in game now shows its English name, **Fastest Quest Route** (the folder is still `RutaMisiones`, so your settings are kept). No other changes.

## 0.1.0 (05-11-2026)

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
