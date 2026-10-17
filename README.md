# MineDefense — versión corregida

Proyecto para **Godot 4.7**, edición estándar con GDScript. No requiere complementos ni dependencias externas.

## Abrir y jugar

1. Descomprime el ZIP conservando las carpetas.
2. En Godot 4.7, pulsa **Importar** y selecciona `project.godot`.
3. Espera a que termine la importación y pulsa **F6** sobre `main.tscn` o **F5** para ejecutar el proyecto.

La escena de inicio es `main.tscn`. `ZombieMiner.tscn` también funciona y utiliza el mismo controlador `Scripts/main.gd`; ya no hay una copia de la lógica incrustada en la escena.

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
| Primera venta automática, tres reinicios y liberación de los ocho gestores al cerrar una noche activa | 45 comprobaciones | 45 comprobaciones |

Las pruebas de liberación utilizan referencias débiles para comprobar que los objetos desaparecen realmente. Además de los códigos de salida, se revisa que Godot no informe de errores, advertencias ni recursos retenidos. No se ha realizado una prueba visual interactiva ni una exportación ejecutable.

Para repetir las comprobaciones desde la carpeta del proyecto, con Godot 4.7 disponible como `godot`:

```bash
godot --headless --path . --editor --import --quit
godot --headless --path . --quit-after 120
godot --headless --path . --script res://tests/smoke.gd -- main.tscn
godot --headless --path . --script res://tests/smoke.gd -- ZombieMiner.tscn
godot --headless --path . --script res://tests/lifecycle.gd -- main.tscn
godot --headless --path . --script res://tests/lifecycle.gd -- ZombieMiner.tscn
```

Los scripts de pruebas terminan con código distinto de cero si falla una comprobación. La carpeta `.godot/` se genera al importar y se excluye del ZIP y del control de versiones.
