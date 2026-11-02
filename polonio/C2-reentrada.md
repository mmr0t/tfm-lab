# Reto C2: El Banco Ingenuo (Reentrada)

- **Vulnerabilidad**: Reentrada clásica
- **OWASP**: SC08
- **SWC**: SWC-107
- **Nivel**: intermedio

Ficha del reto en Polonio. Probado en local (`test/C2-reentrada.t.sol`, 6/6 en verde).

> El reto de Polonio es la **variante A** (reentrada clásica). La variante B (reentrada de solo lectura) se documenta en la memoria pero no forma parte del reto: necesita un contrato consumidor que use el oráculo, y su impacto no se observa sobre un único contrato.

---

## 1. Contrato a desplegar

`BancoIngenuo.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BancoIngenuo {
    mapping(address => uint256) public balances;

    // Se siembra con ETH de "otros usuarios" en el despliegue.
    // El saldo NO se acredita a nadie en el mapping, así que el reto no es trivial.
    constructor() payable {}

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "sin fondos");

        // Envia el Ether ANTES de poner el saldo a cero
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transferencia fallida");

        balances[msg.sender] = 0;
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C2-reentrada/WRITEUP.md`](../src/C2-reentrada/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. Desplegar el reto desde la app.
2. Comprobar con el inspector que el banco tiene 10 ETH y que el saldo del jugador es 0.
3. Desplegar el contrato atacante (desde la consola, con *Desplegar contrato*) y ejecutar `atacar()` con 1 ETH.
4. Pulsar *Verificar solución*: `isSolved()` devuelve `true` y el reto queda resuelto.
