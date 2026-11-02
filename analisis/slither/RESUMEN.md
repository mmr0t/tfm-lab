# Resultados de Slither sobre el laboratorio

Herramientas: Slither 0.11.6 y `slither-check-upgradeability`, con solc 0.8.28, `--evm-version cancun` y optimizador a 200 pasadas. Se reproduce con `analisis/run-slither.sh`. Fecha de ejecución: 01/11/2026 (reejecutado tras añadir la variante de división antes de multiplicación en C8).

Criterio de lectura. Para cada variante se indica si Slither **detecta la vulnerabilidad estudiada** en la versión vulnerable (verdadero positivo) y si **el aviso desaparece** en la versión corregida. Se omiten los avisos que no guardan relación con la vulnerabilidad del caso:

- `incorrect-equality`: lo provoca `isSolved()` (`address(this).balance == 0`), que es parte del arnés del reto, no de la lógica del contrato.
- `unchecked-transfer` en C7 y C8: el `MiniToken` del escenario devuelve `bool` y los contratos lo ignoran. Es un artefacto del token mínimo del laboratorio (en producción se usaría `SafeERC20`).
- `erc20-interface` en C1: la wallet tiene una función llamada `transfer` sin ser un token.
- `missing-zero-check`, `locked-ether`, `reentrancy-benign`, `timestamp`: avisos de baja relevancia.

## Tabla resumen

| Caso | Variante | Detector esperado | Vulnerable | Corregido |
|---|---|---|---|---|
| C1 | Función desprotegida (`setOwner`) | ninguno específico | No detectada | - |
| C1 | Autorización por `tx.origin` | `tx-origin` | **Detectada** | Desaparece |
| C1 | Inicialización desprotegida (`initialize`) | ninguno específico | No detectada | - |
| C2 | Reentrada clásica | `reentrancy-eth` | **Detectada** | Desaparece |
| C2 | Reentrada entre funciones (*cross-function*) | `reentrancy-eth` | **Detectada** | Desaparece |
| C2 | Reentrada de solo lectura | `reentrancy-eth` (indirecto) | Detectada como escritura tras llamada, sin identificar el consumidor `view` | Desaparece |
| C3 | DoS por reembolso *push* | ninguno específico | No detectada | - |
| C3 | Retorno de `send` ignorado | `unchecked-send` | **Detectada** | Desaparece |
| C3 | Bucle no acotado (DoS por gas) | `calls-loop` | **Detectada** | Desaparece |
| C4 | `delegatecall` a destino arbitrario | `controlled-delegatecall` | **Detectada** | **Falso positivo**: persiste aunque el destino es inmutable y la función exige `owner` |
| C4 | Colisión de almacenamiento | `order-vars-proxy` (check-upgradeability) | **Detectada** | Desaparece |
| C4 | Implementación sin inicializar | ninguno específico | No detectada | - |
| C5 | Aleatoriedad con variables del bloque | `weak-prng` | **Detectada** | **Falso positivo**: persiste, el detector reconoce el patrón `hash % n` sin distinguir la fuente |
| C6 | Replay de firma | ninguno específico | No detectada | - |
| C6 | Maleabilidad de firma | ninguno específico | No detectada | `arbitrary-send-eth` aparece como falso positivo (destino pasado como parámetro, pero autorizado por firma) |
| C7 | Oráculo de precio *spot* | ninguno específico | No detectada | - |
| C8 | Inflación del primer depositante | ninguno específico | No detectada | - |
| C8 | Redondeo a favor del usuario | ninguno específico | No detectada | - |
| C8 | División antes de multiplicación | `divide-before-multiply` | **Detectada** | Desaparece |
| C9 | Error de lógica de negocio | ninguno específico | No detectada | - |
| C10 | Escritura arbitraria en *storage* (ensamblador) | ninguno específico | No detectada | - |
| C10 | Colisión de hash con `abi.encodePacked` | `encode-packed-collision` | **Detectada** | Desaparece |

## Lectura de los resultados

- De las 22 variantes estudiadas, Slither identifica de forma directa **10** (`tx-origin`, reentrada clásica, reentrada entre funciones, `unchecked-send`, bucle no acotado con `calls-loop`, `delegatecall` controlado, colisión de *storage*, `weak-prng`, `divide-before-multiply` y `encode-packed-collision`) y señala de forma indirecta **1** más (reentrada de solo lectura).
- No detecta ninguna de las vulnerabilidades de **lógica económica o de diseño** (C7, C8, C9), ni el replay o la maleabilidad de firmas, ni la función desprotegida ni la inicialización desprotegida de C1, ni el DoS *push* de C3, ni la implementación sin inicializar de C4, ni el redondeo a favor del usuario de C8, ni la escritura arbitraria en ensamblador de C10.
- En **3** versiones corregidas mantiene avisos de alta severidad que son falsos positivos (C4, C5 y C6).

Estos datos, obtenidos sobre el propio laboratorio, son coherentes con los estudios empíricos citados en la memoria (Durieux et al., 2020; Ghaleb y Pattabiraman, 2020; Chaliasos et al., 2024): el análisis estático es útil para patrones sintácticos, pero no sustituye la comprensión del mecanismo de ataque ni la verificación mediante pruebas.

Observación sobre las variantes de C1, C4 y C8 añadidas. La inicialización desprotegida (C1), la implementación sin inicializar detrás de un proxy (C4) y el redondeo a favor del usuario (C8) no tienen un detector específico en Slither y pasan desapercibidas en el análisis estático, pese a estar entre las causas de incidentes reales. Refuerzan la conclusión del capítulo: el análisis estático cubre patrones sintácticos, no la intención del contrato. El bucle no acotado de C3 sí lo marca `calls-loop`, y la reentrada entre funciones de C2 la marca `reentrancy-eth` igual que la clásica.

Nota de reproducción: estos resultados se obtienen con `analisis/run-slither.sh`. Las variantes que se añadan al laboratorio deben incorporarse a esta tabla ejecutando de nuevo el script.

Observación sobre la variante de división antes de multiplicación (C8), añadida en la Fase 6. Es el único fallo de precisión que Slither identifica, porque tiene una forma sintáctica fija (una multiplicación aplicada al resultado de una división). El redondeo a favor del usuario y el ataque de inflación, que dependen de la dirección del redondeo y del estado del contrato, no los detecta.
