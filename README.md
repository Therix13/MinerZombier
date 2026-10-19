# MineDefense — progresión y tecnologías

Proyecto para **Godot 4.7**, edición estándar con GDScript. No requiere complementos ni dependencias externas.

## Abrir y jugar

1. Descomprime el ZIP conservando las carpetas.
2. En Godot 4.7, pulsa **Importar** y selecciona `project.godot`.
3. Espera a que termine la importación y pulsa **F6** sobre `main.tscn` o **F5** para ejecutar el proyecto.

La escena de inicio es `main.tscn`. `ZombieMiner.tscn` también funciona y utiliza el mismo controlador `Scripts/main.gd`; ya no hay una copia de la lógica incrustada en la escena.

## Niveles e investigación

Ganas **EXP** por derrotar zombis y vender minerales, tanto manualmente como por cinta:

| Acción | EXP |
| --- | --- |
| Derrotar un zombi | 10 |
| Vender una pepita de carbón | 2 |
| Vender una pepita de cobre | 3 |

El primer nivel requiere 25 EXP. Cada nivel posterior necesita 15 EXP más que el anterior: 25, 40, 55, 70… La EXP sobrante se conserva y una recompensa grande puede otorgar varios niveles. Cada subida da **1 punto de investigación (PI)**.

El indicador de la izquierda muestra nivel, EXP y puntos disponibles. Pulsa **TECNOLOGÍAS** allí o entra en **Tienda → TECNOLOGÍAS** para investigar durante el día. Cada tarjeta explica su efecto, coste, nivel y tecnología previa. Las mejoras afectan de inmediato a las máquinas y torretas existentes y a las nuevas; cada tecnología solo se compra una vez.

| Rama | Tecnología | Requisitos | Efecto |
| --- | --- | --- | --- |
| Minería | Extracción eficiente | Nivel 2, 1 PI | 5 acciones por pepita en vez de 7 |
| Minería | Perforación avanzada | Nivel 4, 2 PI y Extracción eficiente | Taladro cada 0,3 s en vez de 0,6 s |
| Logística | Cintas mejoradas | Nivel 2, 1 PI | Transporte cada 3 s en vez de 4 s |
| Logística | Transporte industrial | Nivel 4, 2 PI y Cintas mejoradas | Transporte cada 2 s |
| Defensa | Potencia de fuego | Nivel 2, 1 PI | Un 50 % más de daño |
| Defensa | Cargadores ampliados | Nivel 4, 2 PI y Potencia de fuego | Capacidad de 8 municiones y disparo cada 3 s |

La progresión dura **toda la partida y se mantiene al cambiar de día**. Reiniciar comienza una partida nueva con nivel 1, cero EXP y ninguna tecnología. No hay guardado entre sesiones. Las recompensas, costes y requisitos se pueden ajustar en `Scripts/progression_manager.gd`.

Extraer, mover o cargar minerales no duplica la EXP de su venta. Los impactos sin matar, la limpieza de enemigos al cerrar y las recompensas de monedas del tutorial o de una noche tampoco conceden EXP.

## Correcciones incluidas

- Se restaura la carpeta `Scripts/` con archivos reales, sin enlaces ni rutas externas.
- La escena principal usa `main.gd`, incluido el panel «Noche superada» y el botón Continuar.
- Las ventas por cinta actualizan el tutorial igual que las ventas manuales; la bonificación inicial se entrega una sola vez.
- Las vetas, cintas, taladros y minerales respetan el terreno comprado al colocarlos o arrastrarlos. Se mantienen las conexiones de munición, la venta de minerales y la rotación en la misma casilla.
- Al cerrar o reiniciar se desconectan las señales del ciclo y se rompen las referencias circulares entre gestores. Los gestores de la partida anterior se liberan.

## Controles

- Clic izquierdo: colocar, extraer mineral o seleccionar y arrastrar objetos.
- Clic derecho y arrastrar: mover la cámara.
- Rueda del ratón: zoom.
- **R**: rotar durante la colocación o al mover una veta, cinta o taladro.
- **Esc**: cancelar la colocación; también cierra el panel de victoria.
- **P**: alternar las vistas de mina y defensa durante la preparación.
- **Enter**: continuar desde el panel de victoria.
- **F10**: activar o desactivar el modo de desarrollo existente.

## Validación

Se comprobaron ambos puntos de entrada con Godot `4.7.stable.official.5b4e0cb0f`, en modo headless:

| Prueba | `main.tscn` | `ZombieMiner.tscn` |
| --- | --- | --- |
| Juego, tutorial, economía, minería, transporte, disparos, victoria y límites de terreno | 32 comprobaciones | 32 comprobaciones |
| Primera venta automática, tres reinicios, reinicio de mejoras y liberación de los nueve gestores | 55 comprobaciones | 55 comprobaciones |
| EXP, niveles, requisitos, compra desde la interfaz, efectos de las seis tecnologías y límites de fase | 58 comprobaciones | 58 comprobaciones |

Las pruebas de liberación utilizan referencias débiles para comprobar que los objetos desaparecen realmente. Las pruebas de interfaz verifican el indicador en ventanas de 1152×648 y 800×600, el acceso por botón y el desplazamiento hasta la última tecnología. Además de los códigos de salida, se revisa que Godot no informe de errores, advertencias ni recursos retenidos. No se ha realizado una prueba visual interactiva ni una exportación ejecutable.

Para repetir las comprobaciones desde la carpeta del proyecto, con Godot 4.7 disponible como `godot`:

```bash
godot --headless --path . --editor --import --quit
godot --headless --path . --quit-after 120
godot --headless --path . --script res://tests/smoke.gd -- main.tscn
godot --headless --path . --script res://tests/smoke.gd -- ZombieMiner.tscn
godot --headless --path . --script res://tests/lifecycle.gd -- main.tscn
godot --headless --path . --script res://tests/lifecycle.gd -- ZombieMiner.tscn
godot --headless --path . --script res://tests/progression.gd -- main.tscn
godot --headless --path . --script res://tests/progression.gd -- ZombieMiner.tscn
```

Los scripts de pruebas terminan con código distinto de cero si falla una comprobación. La carpeta `.godot/` se genera al importar y se excluye del ZIP y del control de versiones.
