# Reto C4: El Monedero Delegado (delegatecall)

- **Vulnerabilidad**: delegatecall a dirección arbitraria
- **OWASP**: SC10
- **SWC**: SWC-112
- **Nivel**: intermedio

Ficha del reto en Polonio. Probado en local (`test/C4-delegatecall-proxies.t.sol`, 6/6 en verde).

> El reto de Polonio es la **variante A** (delegatecall arbitrario). La variante B (colisión de almacenamiento) se documenta en la memoria pero no forma parte del reto: su efecto es la corrupción de un puntero interno, difícil de plantear como objetivo "ganable".

---

## 1. Contrato a desplegar

`MonederoDelegado.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MonederoDelegado {
    address public owner; // slot 0

    constructor() payable {
        owner = msg.sender;
    }

    // FALLO: delega a una dirección arbitraria controlada por quien llama.
    function ejecutar(address logica, bytes calldata data) external {
        (bool ok, ) = logica.delegatecall(data);
        require(ok, "delegatecall fallido");
    }

    function retirar() external {
        require(msg.sender == owner, "solo owner");
        payable(msg.sender).transfer(address(this).balance);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C4-delegatecall-proxies/WRITEUP.md`](../src/C4-delegatecall-proxies/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. Desplegar el reto (con 5 ETH).
2. Desplegar el contrato `Malicioso` desde la consola y ejecutar los dos pasos.
3. Pulsar *Verificar solución*: `isSolved()` devuelve `true` y el reto queda resuelto.
