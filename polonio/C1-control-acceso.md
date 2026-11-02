# Reto C1: La Bóveda sin Dueño (Control de acceso)

- **Vulnerabilidad**: Control de acceso / función desprotegida
- **OWASP**: SC01
- **SWC**: SWC-105, SWC-100
- **Nivel**: básico

Ficha del reto en Polonio. Probado antes en local (`test/C1-control-acceso.t.sol`, 6/6 en verde).

> Nota: el reto de Polonio es la **variante A** (función desprotegida), por ser autocontenida y de una sola transacción encadenada. La variante B (tx.origin) se documenta en la memoria pero no forma parte del reto, porque requiere un contrato de phishing y un escenario de ingeniería social que no aporta como reto independiente.

---

## 1. Contrato a desplegar

`BovedaSinDueno.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BovedaSinDueno {
    address public owner;

    constructor() payable {
        owner = msg.sender;
    }

    function deposit() external payable {}

    // FALLO: sin control de acceso
    function setOwner(address newOwner) external {
        owner = newOwner;
    }

    function withdrawAll() external {
        require(msg.sender == owner, "solo owner");
        payable(msg.sender).transfer(address(this).balance);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C1-control-acceso/WRITEUP.md`](../src/C1-control-acceso/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. En la aplicación, iniciar el nodo, abrir Retos, seleccionar *BovedaSinDueno* y pulsar Desplegar.
2. Resolver con la consola (dos llamadas `setOwner` y `withdrawAll` desde `accounts[1]`).
3. Pulsar *Verificar solución*: debe pasar (`isSolved()` devuelve `true`).
