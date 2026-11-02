# Reto C5: La Lotería Predecible (Aleatoriedad débil)

- **Vulnerabilidad**: aleatoriedad débil a partir de variables del bloque
- **OWASP**: SC09 (2025)
- **SWC**: SWC-120
- **Nivel**: básico/intermedio

Ficha del reto en Polonio. Probado en local (`test/C5-aleatoriedad.t.sol`, 3/3 en verde).

---

## 1. Contrato a desplegar

`LoteriaPredecible.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LoteriaPredecible {
    constructor() payable {}

    function jugar() external payable {
        require(msg.value == 1 ether, "1 ETH");

        // FALLO: azar predecible a partir de variables del bloque.
        uint256 aleatorio = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))
        );

        if (aleatorio % 2 == 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C5-aleatoriedad/WRITEUP.md`](../src/C5-aleatoriedad/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. Desplegar el reto (con 5 ETH).
2. Desplegar el contrato atacante (1 ETH) y llamar a `atacar()` hasta ganar.
3. Pulsar *Verificar solución*: `isSolved()` devuelve `true` y el reto queda resuelto.

> Anvil mina cada transacción en un bloque nuevo, así que reintentar `atacar()` cambia las variables del bloque y el atacante acaba entrando en una ronda ganadora.
