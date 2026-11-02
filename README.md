# tfm-lab: Laboratorio reproducible de vulnerabilidades en smart contracts

Entorno de la parte práctica del TFM *Análisis de las principales vulnerabilidades actuales en smart contracts de Ethereum*. Cada caso del catálogo (de C1 a C10) incluye un contrato **vulnerable**, su versión **corregida** y un test que demuestra que el ataque tiene éxito contra el primero y fracasa contra el segundo.

> **Aviso de uso.** Los contratos vulnerables de este repositorio se han escrito exclusivamente con fines formativos y de investigación, para ejecutarse en una red local aislada. No deben desplegarse en redes públicas. Explotar contratos ajenos sin autorización puede constituir un delito y causa daños a terceras personas.

## Requisitos

Solo **Docker**. No hace falta instalar la toolchain de Foundry: el script `./forge` ejecuta la imagen oficial `ghcr.io/foundry-rs/foundry` (la misma que usa [Polonio](https://github.com/Offensive-Skills/Polonio)).

```bash
./forge build                                         # compila todo
./forge test                                          # ejecuta TODA la batería (51 pruebas)
./forge test --match-contract C1_ControlAcceso        # un caso concreto
./forge test -vvv                                     # con trazas detalladas
```

Quien tenga Foundry instalado localmente puede usar `forge` en vez de `./forge`.

> Este documento es la **guía única**: la sección [Probar cada reto en el laboratorio](#probar-cada-reto-en-el-laboratorio) cubre la reproducción con Foundry, y la sección [Desplegar y probar los retos en Polonio](#desplegar-y-probar-los-retos-en-polonio) cubre el despliegue en la herramienta. El TFM tiene **dos entornos**: el laboratorio Foundry (reproducible por cualquiera, es el que valida los resultados) y Polonio (herramienta de apoyo propia para desplegar y resolver los retos de forma manual).

## Versiones fijadas (reproducibilidad)

| Componente | Versión | Dónde |
|---|---|---|
| Solidity (solc) | 0.8.28 | `foundry.toml` |
| EVM | `cancun` por defecto, y perfil `paris` para paridad con Polonio | `foundry.toml` |
| Optimizador | activado, 200 runs | `foundry.toml` |
| OpenZeppelin Contracts | 5.6.1 | `lib/openzeppelin/` |
| forge-std | v1.9.6 | `lib/forge-std/` |
| Imagen Foundry | `ghcr.io/foundry-rs/foundry` fijada por digest `sha256:6fec6dc8249fb0231144b159e4ee1d86e486e3dc8eccb09a25e5e16ce494236b` (forge 1.8.7) | `./forge` |
| Slither | 0.11.6 | `analisis/run-slither.sh` |

El compilador (0.8.x) y el optimizador (200 runs) coinciden con Polonio. El laboratorio usa EVM `cancun` (mainnet desde Dencun, 2024), que requieren algunas utilidades de OpenZeppelin 5.6. Los contratos de los retos de Polonio son autocontenidos y sin OpenZeppelin, así que también compilan bajo el `evmVersion: paris` de la herramienta. Para comprobar esa paridad:

```bash
FOUNDRY_PROFILE=paris ./forge build --skip 'test/**' --skip '**/Fixed.sol'
```

## Estructura

```
tfm-lab/
  foundry.toml              # versiones fijadas
  remappings.txt            # forge-std/ y @openzeppelin/contracts/
  forge                     # wrapper: forge via Docker
  lib/                      # dependencias vendorizadas (OZ, forge-std)
  src/
    _smoke/                 # caso de humo (prueba del arnés; no es del catálogo)
    CXX-<nombre>/
      Vulnerable.sol        # contrato vulnerable
      Fixed.sol             # versión corregida
      WRITEUP.md            # resolución paso a paso del reto y de sus variantes
  test/
    base/BaseChallenge.t.sol  # base común de todos los tests
    CXX-<nombre>.t.sol        # exploit contra vulnerable + resistencia del corregido
  polonio/
    CXX-<nombre>.md         # ficha del reto en Polonio
    simulacion/             # contratos de las fichas de C7 y C8 y simulación de su despliegue
  analisis/
    run-slither.sh          # reproduce el análisis estático
    slither/                # salida de Slither por contrato y RESUMEN.md
```

## Convención de un caso

1. **`Vulnerable.sol` y `Fixed.sol`** exponen la misma interfaz, incluida una función `isSolved()` que define la condición de éxito del reto (la misma condición que comprueba Polonio).

2. **El test** hereda de `BaseChallenge` y define al menos:
   - `test_Exploit_Vulnerable()`: tras el ataque, `isSolved()` devuelve `true`.
   - `test_Fixed_Resiste()`: el mismo ataque **no** consigue `isSolved() == true`.

   Esto materializa el indicador del objetivo OE4: el exploit cumple la condición de éxito sobre la versión vulnerable y no la cumple sobre la corregida.

3. **El writeup** (`src/CXX-nombre/WRITEUP.md`) explica cómo resolver el reto paso a paso: el escenario, la vulnerabilidad, la resolución, las otras variantes del caso, la mitigación y las pruebas que lo comprueban. Es también el writeup del reto en Polonio.

4. **La ficha de Polonio** (`polonio/CXX-*.md`) recoge el `.sol` del reto y el writeup del caso.

## Estado de los casos

| Caso | Vulnerabilidad | Vulnerable/Fixed | Test | Ficha Polonio |
|---|---|---|---|---|
| (humo) | - | OK | OK | - |
| C1 | Control de acceso (desprotegida + tx.origin + inicialización) | OK | OK (6/6) | OK |
| C2 | Reentrada (clásica + entre funciones + solo lectura) | OK | OK (6/6) | OK |
| C3 | Llamadas externas y DoS (push + retorno ignorado + bucle no acotado) | OK | OK (6/6) | OK |
| C4 | delegatecall y proxies (hijack + colisión storage + implementación sin inicializar) | OK | OK (6/6) | OK |
| C5 | Aleatoriedad débil (lotería predecible) | OK | OK (3/3) | OK |
| C6 | Firmas (replay + replay entre contratos/cadenas + maleabilidad) | OK | OK (6/6) | OK |
| C7 | Oráculos y préstamos flash | OK | OK (3/3) | OK (acciones `setup`) |
| C8 | Errores aritméticos y de precisión (inflación de vault + redondeo + división antes de multiplicación) | OK | OK (6/6) | OK (con víctima) |
| C9 | Lógica de negocio (recompensa en bucle) | OK | OK (3/3, una de fuzzing) | OK |
| C10 | Validación de entradas (escritura arbitraria + hash collision) | OK | OK (4/4) | OK |

## Análisis estático con Slither

`analisis/run-slither.sh` ejecuta Slither sobre cada contrato vulnerable y corregido, y `slither-check-upgradeability` sobre los proxies de C4. La salida se guarda en `analisis/slither/` y la interpretación (qué detecta, qué no y qué falsos positivos aparecen) está en [`analisis/slither/RESUMEN.md`](analisis/slither/RESUMEN.md).

## Probar cada reto en el laboratorio

Desde la carpeta `tfm-lab/`. La primera ejecución descarga `solc` 0.8.28 (unos segundos).

```bash
./forge test            # toda la batería: 51 pruebas, todas deben pasar
```

Para ejecutar un caso concreto, usa el nombre de su contrato de test:

| Caso | Comando | Pruebas |
|---|---|---|
| C1  | `./forge test --match-contract C1_ControlAcceso` | 6 |
| C2  | `./forge test --match-contract C2_Reentrada` | 6 |
| C3  | `./forge test --match-contract C3_LlamadasDoS` | 6 |
| C4  | `./forge test --match-contract C4_DelegatecallProxies` | 6 |
| C5  | `./forge test --match-contract C5_Aleatoriedad` | 3 |
| C6  | `./forge test --match-contract C6_Firmas` | 6 |
| C7  | `./forge test --match-contract C7_OraculoFlashloan` | 3 |
| C8  | `./forge test --match-contract C8_AritmeticaPrecision` | 6 |
| C9  | `./forge test --match-contract C9_LogicaNegocio` | 3 |
| C10 | `./forge test --match-contract C10_ValidacionEntradas` | 4 |
| humo | `./forge test --match-contract SmokeTest` | 2 |

Añade `-vvv` para ver las trazas de cada llamada, o `-vvvv` para el detalle completo de la EVM. En cada caso, una prueba `test_Exploit_*` comprueba que el ataque **resuelve** la versión vulnerable y una `test_Fixed_*` comprueba que la corregida **resiste**.

## Desplegar y probar los retos en Polonio

Esta sección explica cómo probar cada reto en la herramienta Polonio. El código exacto de cada reto (contrato y *writeup*) está en la ficha correspondiente de `polonio/CXX-*.md`.

### Requisitos previos

- La aplicación **Polonio** instalada.
- **Docker** en ejecución, **Node.js 18+**, y el puerto **8545** (Anvil) disponible.

### Arranque de Polonio

```bash
npm start                   # abre la app de escritorio
```

En la app: inicia sesión con tu usuario y token de Offensive Skills y pulsa **Iniciar Nodo** para levantar la red local Anvil.

## Licencia

Código bajo licencia MIT (ver [`LICENSE`](LICENSE)). Las dependencias vendorizadas en `lib/` conservan sus licencias originales (OpenZeppelin Contracts con MIT, y forge-std con MIT o Apache-2.0).
