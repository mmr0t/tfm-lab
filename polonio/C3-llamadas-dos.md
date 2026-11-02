# Reto C3: La Subasta Bloqueada (DoS por llamada externa)

- **Vulnerabilidad**: Denegación de servicio por revert en patrón push
- **OWASP**: SC06/SC10
- **SWC**: SWC-113
- **Nivel**: intermedio

Ficha del reto en Polonio. Probado en local (`test/C3-llamadas-dos.t.sol`, 6/6 en verde).

> El reto de Polonio es la **variante A** (DoS por reembolso push). La variante B (valor de retorno ignorado) se documenta en la memoria pero no forma parte del reto: su efecto es una pérdida silenciosa para la víctima, no un objetivo que el jugador "gane".

---

## 1. Contrato a desplegar

`SubastaBloqueada.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SubastaBloqueada {
    address public mejorPostor;
    uint256 public mejorPuja;

    function pujar() external payable {
        require(msg.value > mejorPuja, "puja baja");

        // FALLO: reembolso push. Si el postor anterior rechaza el Ether,
        // este transfer revierte y nadie puede volver a pujar.
        if (mejorPostor != address(0)) {
            payable(mejorPostor).transfer(mejorPuja);
        }

        mejorPostor = msg.sender;
        mejorPuja = msg.value;
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C3-llamadas-dos/WRITEUP.md`](../src/C3-llamadas-dos/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. Desplegar el reto, desplegar el contrato `Postor` y pujar con él.
2. Pulsar *Verificar solución*: una nueva puja con `pujar()` revierte y el reto queda resuelto.
