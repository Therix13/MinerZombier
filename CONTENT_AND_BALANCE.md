# Expansión industrial

Esta versión incorpora una campaña larga y sus sistemas jugables. Las 900 noches son una ruta de progresión, no 900 mapas ni misiones únicas. A velocidad normal, 900 ciclos de cinco minutos de gestión y dos de horda equivalen a 105 horas; acelerar las noches, morir, pausar o prolongar el combate cambia esa duración. No se ha validado una partida humana de 100 horas.

## Producción y armas

Las vetas de nitrato de potasio, azufre y wolframio se integran con minería, fusión hasta nivel 4, taladros, cintas, filtradores y guardado. El nitrato se descubre al crear un lingote de cobre Nv. 3; el azufre, al crear nitrato Nv. 4 o fusionar su veta hasta Nv. 4; el wolframio requiere una veta de oro Nv. 4. El wolframio también se funde con 40 de combustible.

El taller central se abre con **ARSENAL · LOGROS**. Consume recursos sueltos de la mina, conserva el trabajo al guardar, puede repetir una receta y espera sin perder el producto cuando no hay espacio. La ventana pausa la simulación; hay que cerrarla para que avance la fabricación. La munición se transporta y carga mediante cintas o arrastre manual.

| Producto | Materiales por lote | Producción | Tiempo |
|---|---|---:|---:|
| Pólvora | Nitrato Nv. 4 + azufre Nv. 4 + carbón Nv. 4 | 8 | 4 s |
| Balas | Pólvora + lingote de cobre Nv. 1 | 12 | 3 s |
| Granadas | 3 pólvoras + lingote de hierro Nv. 1 | 4 | 5 s |
| Cohetes | 6 pólvoras + lingote de hierro Nv. 2 | 2 | 7 s |
| Celdas | Lingote de cobre Nv. 3 + nitrato Nv. 4 | 8 | 6 s |

| Arma | Precio del plano | Cargador | Intervalo | Daño directo | Radio | Alcance |
|---|---:|---:|---:|---:|---:|---:|
| Pistolas | 1.800 | 24 | 0,65 s | 1,5 | — | 340 |
| Lanzagranadas | 6.000 | 10 | 3 s | 6 | 78 | 360 |
| Lanzacohetes | 20.000 | 6 | 4 s | 18 | 105 | 430 |
| Tesla | 45.000 | 16 | 1,5 s | 4 | 65 | 320 |

Los planos también requieren sus lingotes. Cada arma industrial utiliza exclusivamente su munición. El daño de área a objetivos secundarios es del 65 %. Tesla ralentiza durante dos segundos. Los lanzapepitas conservan su munición mineral y estadísticas anteriores. Todas las armas necesitan una plataforma activa para disparar.

## Progresión y economía

- Siete etapas de campaña, con hitos en los días 1, 6, 21, 81, 181, 361 y 601.
- Galerías ampliables a 11 × 7 y 15 × 9 por 7.500 y 30.000 monedas después de la primera expansión.
- Hasta seis plataformas; las parejas adicionales cuestan 10.000 y 20.000 monedas.
- Reparación de 30 puntos de integridad durante el día, limitada al máximo de 100. Precio: 80 + 15 por día.
- Recompensa por noche: 100 + 40 por día, con límite de 15.000. Se paga antes del checkpoint de amanecer; cargar una victoria no vuelve a pagarla.
- Tres mejoras del arsenal tras las noches 25, 100 y 250, con costes de 25.000/100.000/500.000 y lingotes industriales. Cada rango añade un 20 % de daño y un 25 % de capacidad sobre la base, y resta un 10 % del intervalo base.
- 37 logros con seguimiento real de bajas, fabricación, jefes, noches superadas y noches sin daño. No conceden dinero repetible.

## Combate

Dieciocho tipos: zombi, corredor, blindado, escupidor, demoledor, rey de la plaga, explosivo, rastrero, acechador, esquivo, portaescudo, contagiador, colmena, saboteador, furioso, carcelero, madre de la colmena y ejecutor.

Los nuevos enemigos introducen camuflaje, reducción de cada tercer impacto, restauración de armadura, curación cercana, invocaciones al morir, robo de munición y cargas repetidas. Los jefes anuncian ataques y presentan ventanas vulnerables. La madre invoca rastreros; el ejecutor acelera con poca vida. Sus puntos de vida no se multiplican con el número del día.

Desde el día 21: niebla cada siete noches (−15 % de alcance), blindaje adicional cada seis y furia cada nueve (+20 % de velocidad). Desde la noche 81 aparecen dobles jefes en noches de jefe; desde la 601, triples. Las etapas tardías también cambian la composición de apoyos y furiosos.

Se mantienen 24 zombis en la primera oleada, ocho adicionales por día hasta 160 y un máximo de 64 simultáneos. Los restantes esperan espacio y no desaparecen al amanecer. Los rastreros invocados respetan el límite. El reloj llega a las 06:00, pero el combate sigue hasta eliminar la horda.

## Validación y límites

- `tests/content_expansion.gd`: recursos, recetas, conservación de inventario, armas y munición, efectos de área, habilidades, jefes, mejoras, galerías, plataformas, guardados antiguos y nuevos, y aislamiento de los modelos animados del bestiario.
- `tests/industrial_balance.gd`: combates completos de las noches 1, 3, 6, 10, 15, 20, 21, 30, 50, 100, 200, 500 y 900 con defensas de su etapa, reposición ilimitada de munición y prioridad táctica a ataques a distancia y vulnerabilidades. Mide viabilidad de combate, no el coste de fabricar todos los suministros.
- Se enumeran las 900 noches para comprobar que todas sus selecciones de enemigos son válidas.
- Se conservan las pruebas de hornos, munición mineral, hordas, filtradores, guardado por día, sonidos y presupuesto de renderizado.

El balance es una base inicial reproducible. Aún requiere pruebas humanas de economía, aprendizaje, dificultad y variedad durante sesiones largas. La duración calculada de la ruta no demuestra 100 horas de contenido único. Las comprobaciones gráficas usan renderizado por software; no certifican 120 FPS en el equipo del jugador.
