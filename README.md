# RutaMisiones

Addon para World of Warcraft: Forever que te dice **en qué orden hacer las misiones para subir más rápido**:
qué recoger, qué objetivo hacer y dónde entregar, con la flecha del mapa en el siguiente paso.

## Qué hace

- Mira tu diario, tu nivel, tus misiones completadas y dónde estás, y busca en la base de datos de Questie las
  misiones que puedes coger en el mapa actual.
- Calcula la ruta que más experiencia da por hora: agrupa recogidas y entregas en el mismo PNJ, hace los
  objetivos cercanos de una tirada y no te hace ir y volver entre campamentos.
- Entiende las **cadenas**: si entregar una misión abre otra en el mismo sitio, la tiene en cuenta (marca
  «[cadena]») y valora una misión floja si desbloquea una buena.
- Descarta lo que no compensa (poca XP para el desvío, más de 2 niveles por encima, de otra zona) y te dice **qué
  misiones evitar**: bajo la ruta, una sección «Evitar» lista hasta 5, primero las de tu diario que conviene
  abandonar o dejar para luego y después las cercanas que no merecen el desvío, con su XP por hora (el tooltip la
  compara con la de tu ruta). Clic derecho en una la oculta. `/ruta debug` da la lista completa con motivos.
- **Acepta y entrega las misiones sola** al hablar con el PNJ: las que convienen (no grises ni repetibles, salvo
  que la ruta las pida; nunca las ignoradas ni las de «Evitar»). Si hay que elegir recompensa o pagar, lo dejas
  tú, igual que las de JcJ y las que da un objeto. Mantén **Mayús** al hablar para hacerlo a mano.
- **Aprende las misiones nuevas de Forever** que la base de Questie no tiene: al hacerlas guarda dónde se cogen,
  dónde se terminan y dónde se entregan, y se las propone a tus otros personajes (misma facción y, mientras solo
  la haya cogido una clase, esa clase).
- **Te dice a qué zona ir después**: cuando en la tuya quedan pocos pasos, la ventana propone la zona con más XP
  de misiones para tu nivel (con dador amistoso para tu facción). `/ruta zonas` da las tres mejores.
- Se recalcula sola al aceptar, avanzar o entregar misiones, al subir de nivel y al cambiar de zona; nunca en
  combate.

- **Completa con datos de guías de subida** lo que la base de Questie no ubica: dónde se coge, dónde se hacen los
  objetivos y dónde se entrega cada misión (opción «Usar datos de guías», activada por defecto). Si Questie sabe
  dónde está algo, manda Questie.
- **La siguiente zona sigue el orden de zonas de las guías de subida** para tu facción y nivel. Si no hay
  ninguna de la guía a tu nivel, elige por XP disponible como antes.

**Requisito:** Questie (trae QuestieDB). Sin él, el addon avisa y no dibuja nada. No copia datos de Questie: los
consulta en el juego con la API pública de QuestieDB.

`GuideData.lua` se regenera con `tools/extraer_guias.py`.

## Uso

- `/ruta`: muestra u oculta la ventana. Clic izquierdo en un paso (o en una misión de «Evitar») pone la flecha
  de navegación allí y abre el mapa en esa zona (fuera de combate); clic derecho ignora esa misión (se guarda
  por personaje).
- Si tienes **TomTom** instalado, su flecha también apunta al paso (se puede desactivar).
- El addon no mueve al personaje: Blizzard bloquea el movimiento desde addons y su EULA lo considera un bot.
- `/ruta zonas`, `/ruta recalcular`, `/ruta ignorar [ID]`, `/ruta restaurar` (devuelve las ignoradas), `/ruta config`,
  `/ruta debug`, `/ruta reset confirmar`.
- Botón del compartimento de addons: clic para mostrar u ocultar; clic derecho para las opciones.
- Opciones: flecha automática, abrir el mapa al hacer clic, usar TomTom, mostrar misiones a evitar, aceptar
  solo, entregar solo, proponer misiones aprendidas, pasos visibles, niveles máximos por encima, usar las reglas
  de Questie y escala.

## Cómo calcula (y sus límites)

Es una heurística, no un óptimo exacto: inserción más barata con orden recoger < objetivos < entregar (y entre
misiones de una cadena), mejora local moviendo pasos y misiones enteras, y estabilidad respecto al plan anterior.

- Distancias en línea recta dentro del mapa: no conoce montañas, caminos ni vuelos.
- El tiempo de cada objetivo es una estimación (unos 14 s por enemigo, 24 s por objeto de botín).
- Solo planifica el mapa en el que estás; las misiones del diario de otras zonas salen como «fuera de este mapa».
  La siguiente zona se elige por XP disponible, sin contar el viaje (no conoce vuelos ni caminos).
- Las misiones nuevas de Forever que QuestieDB aún no tiene se ven si están en tu diario (con el punto de interés
  de Blizzard o, si no lo hay, los objetivos de la guía). Se proponen para recoger si salen en los datos de guías o
  después de que algún personaje tuyo las haya hecho.
- Con los datos de guías, el nivel de una misión que Questie no conoce es el tramo de la guía donde aparece, su
  XP es una estimación (la mediana de su nivel) y sus previas se deducen del orden de la guía.
- Con montura usa la velocidad real; a pie, la de las opciones (7 yardas/s).

## Desarrollo

Proyecto creado con la plantilla de la skill `wow-addons`. Comprobaciones fuera del juego:

```powershell
C:\Users\Nico\.claude\skills\wow-addons\scripts\verificar-addon.ps1 -Carpeta .
```

Simulación con la QuestieDB real instalada (orco de nivel 1 en el Valle de los Retos, por defecto):

```powershell
python -I -B tools\simular_ruta.py --pasos 200 --hasta-nivel 10
python -I -B tools\simular_ruta.py --mapa 1412 --x 44.2 --y 76 --raza 6 --clase 1
python -I -B tools\simular_ruta.py --mapa 1437 --x 10.6 --y 59.7 --nivel 27 --raza 1 --faccion Alliance --raza-token Human --guias
```
