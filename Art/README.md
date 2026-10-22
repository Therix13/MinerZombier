# Sector 07 · Dirección artística pintada

Ilustración 2D industrial: roca húmeda, acero gastado, cobre cálido, iluminación ámbar e infección cian. Estas cinco láminas son imágenes originales generadas para este proyecto mediante la herramienta de generación de imágenes de OpenAI. Se conservan los PNG originales sin retoque ni remuestreo de sus píxeles; Godot usa regiones de atlas, transparencias, mipmaps y filtrado lineal.

| Archivo | Distribución y uso |
|---|---|
| `Cinematics/origin_panels.png` | 2 × 2: descubrimiento, ruptura del laboratorio, evacuación, refugio. |
| `Environments/mine_world.png` | 2 × 2: portal de mina, roca, galería excavada, exterior boscoso. |
| `Sprites/industry.png` | 4 × 3: cuatro minerales; taladro, horno, compactador, sierra; torreta oxidada, torreta de cobre, AK-47, minigun. |
| `Sprites/components.png` | 4 × 3: cuatro lingotes; nitrato, azufre, pólvora, balas; alto calibre, granada, cohete, batería. |
| `Sprites/infected.png` | Tres columnas y dos filas desiguales: minero, blindado, escupidor; ejecutor, rey de la plaga, madre de la colmena. La segunda fila ocupa el 57,8 % de la altura. |

`Scripts/painted_assets.gd` centraliza las regiones y comparte texturas. Hay **seis siluetas pintadas**, adaptadas a los dieciocho arquetipos mediante movimiento y señales de combate; no dieciocho sprites exclusivos. Las cintas y señales conservan gráficos suaves para facilitar su lectura. Wolframio y algunas variantes de armas reutilizan siluetas con tratamiento de color.

La apertura sustituye íntegramente la anterior: cuatro planos, 32 segundos, música ambiental sintetizada, partículas, movimiento de cámara, iluminación y subtítulos en español. Se puede avanzar, omitir y reproducir desde Historia. Explica la contaminación del campamento por esporas y la elección de la mina por su aire independiente, agua y generador. No tiene doblaje ni animación facial. Las derrotas de los cuatro jefes usan el escenario pintado y animaciones de caída, desintegración o rotura del escudo.

Las animaciones de juego incluyen marcha e impactos mediante shader, caída y disolución de cadáveres, retroceso y fogonazos, sierra giratoria, prensa y luz de hornos. Los halos aditivos evitan pases de iluminación por cada objeto de la fábrica. Las texturas de terreno se dibujan mediante mallas retenidas y los iconos de cintas se cachean.

## Capturas reales en Godot

- [Introducción](../docs/painted-presentation/opening.png)
- [Mina](../docs/painted-presentation/mine.png)
- [Derrota de jefe](../docs/painted-presentation/boss.png)
- [Bestiario](../docs/painted-presentation/bestiary.png)

## Verificación

`tests/painted_presentation.gd` comprueba carga y compartición de láminas, animaciones, cuatro planos narrativos, pausa y restauración exactas, repetición desde Historia, transición a la primera noche, escenas de jefes y compatibilidad del guardado. `tests/render_performance.gd` comprueba terreno retenido, mipmaps, fábrica representativa y exclusión del mundo cubierto por una cinemática. Las pruebas gráficas usan OpenGL con renderizado por software; no certifican 120 FPS en hardware de usuario.

Resultado de esta revisión: presentación 54/54 (también en ventana real), renderizado 63/63 (183 llamadas de dibujo en la fábrica y 17 en la introducción), progresión 81/81, contenido industrial 99/99 y pantalla inicial/guardados 60/60. En total, 357 comprobaciones. Algunos tests de regresión antiguos emiten avisos de instancias ObjectDB al cerrar el árbol de prueba; no hubo errores de parseo, shader o comprobaciones fallidas.
