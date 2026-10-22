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
- Siete ampliaciones sucesivas hasta cubrir las 1.200 casillas; precios y tamaños detallados abajo.
- Hasta seis plataformas; las parejas adicionales cuestan 10.000 y 20.000 monedas.
- Reparación de 30 puntos de integridad durante el día, limitada al máximo de 100. Precio: 80 + 15 por día.
- Recompensa por noche: 100 + 40 por día, con límite de 15.000. Se paga antes del checkpoint de amanecer; cargar una victoria no vuelve a pagarla.
- Tres mejoras del arsenal tras las noches 25, 100 y 250, con costes de 25.000/100.000/500.000 y lingotes industriales. Cada rango añade un 20 % de daño y un 25 % de capacidad sobre la base, y resta un 10 % del intervalo base.
- 55 logros con seguimiento real de bajas, fabricación, jefes, noches superadas y noches sin daño. No conceden dinero repetible.

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

## Renovación visual y progresión por fusiones

La presentación actual usa ilustración pintada: roca húmeda, acero gastado, cobre cálido e infección cian. Cinco láminas originales aportan escenarios, máquinas, minerales, componentes y seis siluetas de infectados reutilizadas por los dieciocho arquetipos. Los PNG conservan su resolución y transparencia, con mipmaps y filtrado lineal. Las señales de dirección, niveles e interfaz siguen siendo gráficos nítidos. El terreno mantiene su caché de dibujo. Véase `Art/README.md`.

### Excavación completa

| Galería resultante | Precio de esta ampliación |
|---|---:|
| 7 × 5 | 500 |
| 11 × 7 | 7.500 |
| 15 × 9 | 30.000 |
| 19 × 14 | 90.000 |
| 23 × 21 | 240.000 |
| 27 × 30 | 600.000 |
| 30 × 40 | 1.500.000 |

Se desbloquean al colocar cobre. Cada compra conserva las celdas y objetos anteriores. La última abarca las 1.200 casillas del mapa y no admite más cobros. La tienda y el arsenal comparten el mismo precio y operación; las ampliaciones se pueden comprar durante la noche. La curva usa el valor creciente de metales y lingotes, requiere reinvertir y no limita el tamaño por día. Es un balance inicial que necesita pruebas humanas prolongadas.

### Recetas y armas desbloqueables

Los requisitos se acumulan: no hay que mantener los ingredientes en el suelo. Hace falta **haber creado todos** los objetos indicados; descubrir nitrato ya no concede todo el arsenal. Los logros muestran cada fusión y resultado antes de conseguirlo. Las recetas permanecen visibles, bloqueadas y con su requisito en Taller.

| Desbloqueo | Objetos que hay que crear |
|---|---|
| Pólvora | Nitrato Nv. 4 y azufre Nv. 4 |
| Balas | Lingote de cobre Nv. 2 |
| Alto calibre | Lingote de hierro Nv. 2 |
| Granadas | Lingote de hierro Nv. 3 |
| Cohetes | Lingote de oro Nv. 3 |
| Celdas eléctricas | Lingote de wolframio Nv. 2 |
| Pistolas | Balas y lingote de hierro Nv. 2 |
| AK-47 | Alto calibre y lingote de hierro Nv. 3 |
| Minigun | Alto calibre y lingote de hierro Nv. 4 |
| Lanzagranadas | Granadas y lingote de cobre Nv. 3 |
| Lanzacohetes | Cohetes y lingote de hierro Nv. 4 |
| Tesla | Celdas y lingote de wolframio Nv. 3 |

Un lote de alto calibre consume dos pólvoras y un lingote de hierro Nv. 2 y produce 16 balas en 4 segundos. AK-47: plano 4.200, dos lingotes de hierro Nv. 3 y uno de cobre Nv. 3, cargador 30, intervalo 0,4 s, daño 2, alcance 350. Minigun: plano 12.000, dos lingotes de hierro Nv. 4 y uno de cobre Nv. 4, cargador 80, intervalo 0,16 s, daño 1,4, alcance 330. Ambas consumen sólo alto calibre: la minigun aporta más daño por segundo a cambio de gastar más munición y perder alcance. Las mejoras globales del arsenal también las afectan.

### Herramientas hasta nivel 4

Arrastra dos taladros, hornos, compactadores, sierras o cintas del mismo tipo y nivel para fusionarlos. Las cintas deben tener la misma forma; se conserva la configuración de destino. Las máquinas deben estar vacías, sin combustible ni producción pendiente; las fusiones no destruyen ni duplican materiales. El movimiento conserva el nivel. Cada Nv. 4 representa ocho herramientas de Nv. 1.

Hornos, sierras, compactadores y cintas multiplican su velocidad por 1 / 1,5 / 2,25 / 3,375 según nivel. El taladro aplica 1 / 2 / 3 / 4 golpes por ciclo. Los consumos y cantidades producidas se mantienen. Las cintas Nv. 1 conservan sus dos segundos. Los niveles se muestran con marcas turquesas y se guardan; los archivos anteriores cargan sus herramientas como Nv. 1.

Dos nuevas piezas de logística: **Distribuidor**, plano 150 y dos lingotes de cobre Nv. 3, alterna salidas laterales después de cada entrega exitosa; **Expulsor**, plano 250 y un lingote de hierro Nv. 2, descarga al frente sobre suelo libre. También se fusionan hasta Nv. 4.

### Historia

La apertura anterior se sustituye por una secuencia de 32 segundos en cuatro planos pintados: descubrimiento de una colonia subterránea, fallo de contención del Protocolo Lázaro y contaminación de la ventilación, evacuación de Mara e Ivo y refugio en una mina con aire independiente, agua y generador. Se puede avanzar cada plano o saltar la introducción. Historia permite reproducirla completa. Industria, cuatro primeras derrotas de jefes y epílogo desde la noche 600 continúan esta historia con el mismo escenario cinematográfico. Las escenas de Carcelero, Rey de la Plaga, Madre de la Colmena y Ejecutor tienen siluetas y animaciones de derrota propias. Pausan el combate, aparecen y desaparecen en un segundo y se cierran con Continuar, Enter, Espacio o Escape. No otorgan recompensas repetibles. Los archivos descubiertos persisten y pueden reproducirse desde Historia. Son escenas 2D con texto, cámara en movimiento, partículas, etalonaje y animaciones de derrota; no son vídeos prerenderizados ni tienen doblaje. La apertura incorpora música ambiental original sintetizada. Los infectados tienen movimiento de marcha, impactos y disolución al morir; las torretas retroceso y fogonazos; sierras y compactadores piezas animadas. Los hornos usan halos aditivos para evitar multiplicar los pases de iluminación de toda la fábrica.

Hay **55 logros**, incluidos los doce hitos de munición/armas y tres hitos de fusión de herramientas. Las compras y tecnologías ya obtenidas en partidas antiguas se conservan.
