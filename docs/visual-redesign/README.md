# Sector 07 · renovación 2D

Dirección artística: ilustración geométrica vectorial, pizarra azul y acentos turquesa/cobre; sin pixel art. El atlas antiguo y su generador fueron retirados.

- [Mina](mine.png)
- [Taller y requisitos de fusión](workshop.png)
- [Bestiario](bestiary.png)
- [Escena de jefe](boss-scene.png)

Los precios, recetas, velocidades y requisitos están en [CONTENT_AND_BALANCE.md](../../CONTENT_AND_BALANCE.md).

## Validación

| Prueba | Comprobaciones correctas |
|---|---:|
| renewed_progression | 81 |
| content_expansion | 99 |
| filter_belt | 237 |
| session_save | 60 |
| day_archives | 24 |
| timed_hordes | 33 |
| industrial_balance | 26 |
| night_purchases | 77 |
| render_performance | 63 |
| mine_scenery | 5 |

Las dos primeras, compras nocturnas y renderizado se ejecutaron también con ventana y renderizador OpenGL. La fábrica de referencia usa 236 llamadas de dibujo y la cinemática 200. Esto no certifica 120 FPS en cualquier equipo ni una campaña humana de 100 horas.

Dos pruebas históricas adicionales siguen incompatibles con sistemas retirados antes de esta revisión: `building_controls.gd` invoca EXP e investigaciones, y `night_resupply.gd` espera la antigua guía persistente de tutorial. Se identificaron durante la comprobación y no se cuentan como pruebas aprobadas. La progresión actual, movimiento/fusiones, compras nocturnas y guardado se validan con las pruebas actuales de la tabla.
