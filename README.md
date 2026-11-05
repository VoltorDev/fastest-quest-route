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
- Descarta lo que no compensa (poca XP para el desvío, más de 2 niveles por encima, de otra zona) y lo explica en
  `/ruta debug`.
- Se recalcula sola al aceptar, avanzar o entregar misiones, al subir de nivel y al cambiar de zona; nunca en
  combate.

**Requisito:** Questie (trae QuestieDB). Sin él, el addon avisa y no dibuja nada. No copia datos de Questie: los
consulta en el juego con la API pública de QuestieDB.

## Uso

- `/ruta`: muestra u oculta la ventana. Clic izquierdo en un paso pone la flecha allí; clic derecho ignora
  esa misión (se guarda por personaje).
- `/ruta recalcular`, `/ruta ignorar [ID]`, `/ruta restaurar` (devuelve las ignoradas), `/ruta config`,
  `/ruta debug`, `/ruta reset confirmar`.
- Botón del compartimento de addons: clic para mostrar u ocultar; clic derecho para las opciones.
- Opciones: flecha automática, pasos visibles, niveles máximos por encima, usar las reglas de Questie y escala.

## Cómo calcula (y sus límites)

Es una heurística, no un óptimo exacto: inserción más barata con orden recoger < objetivos < entregar (y entre
misiones de una cadena), mejora local moviendo pasos y misiones enteras, y estabilidad respecto al plan anterior.

- Distancias en línea recta dentro del mapa: no conoce montañas, caminos ni vuelos.
- El tiempo de cada objetivo es una estimación (unos 14 s por enemigo, 24 s por objeto de botín).
- Solo planifica el mapa en el que estás; las misiones del diario de otras zonas salen como «fuera de este mapa».
- Las misiones nuevas de Forever que QuestieDB aún no tiene se ven si están en tu diario (con el punto de interés
  de Blizzard), pero no se proponen para recoger.

## Desarrollo

Proyecto creado con la plantilla de la skill `wow-addons`. Comprobaciones fuera del juego:

```powershell
C:\Users\Nico\.claude\skills\wow-addons\scripts\verificar-addon.ps1 -Carpeta .
```

Simulación con la QuestieDB real instalada (orco de nivel 1 en el Valle de los Retos, por defecto):

```powershell
python -I -B tools\simular_ruta.py --pasos 200 --hasta-nivel 10
python -I -B tools\simular_ruta.py --mapa 1412 --x 44.2 --y 76 --raza 6 --clase 1
```
