# Reto C10: La Sobreescritura (Escritura arbitraria de storage)

- **Vulnerabilidad**: escritura en posición de almacenamiento arbitraria
- **OWASP**: SC05
- **SWC**: SWC-124
- **Nivel**: avanzado

Ficha del reto en Polonio. Probado en local (`test/C10-validacion-entradas.t.sol`, 4/4 en verde).

> El reto de Polonio es la **variante A** (escritura arbitraria). La variante B (colisión de hash con `abi.encodePacked`) se documenta en la memoria pero no forma parte del reto: requiere entregar una firma y recomponer arrays, más propio de un ejercicio guiado.

---

## 1. Contrato a desplegar

`LaSobreescritura.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LaSobreescritura {
    address public owner;        // slot 0 (objetivo)
    uint256[] public registros;  // slot 1

    constructor() {
        owner = msg.sender;
    }

    function anotar(uint256 valor) external {
        registros.push(valor);
    }

    // FALLO: escribe en registros[indice] sin comprobar límites.
    function editar(uint256 indice, uint256 valor) external {
        assembly {
            mstore(0x00, registros.slot)
            let base := keccak256(0x00, 0x20)
            sstore(add(base, indice), valor)
        }
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C10-validacion-entradas/WRITEUP.md`](../src/C10-validacion-entradas/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. Desplegar el reto.
2. Desde la consola, calcular `base = keccak256(abi.encode(uint256(1)))`, el `indice` y llamar a `editar(indice, tuDireccion)`.
3. Pulsar *Verificar solución*: `owner()` ya no es el desplegador y el reto queda resuelto.
