# Reto C9: El Staking Generoso (Lógica de negocio)

- **Vulnerabilidad**: recompensa reclamable en bucle
- **OWASP**: SC02
- **Nivel**: intermedio

Ficha del reto en Polonio. Probado en local (`test/C9-logica-negocio.t.sol`, 3/3 en verde).

---

## 1. Contrato a desplegar

`StakingGeneroso.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract StakingGeneroso {
    mapping(address => uint256) public depositado;
    uint256 public constant TASA = 100; // %

    constructor() payable {} // fondo de recompensas

    function depositar() external payable {
        depositado[msg.sender] += msg.value;
    }

    // FALLO: paga la recompensa completa en cada llamada, sin descontar lo pagado.
    function reclamar() external {
        uint256 recompensa = (depositado[msg.sender] * TASA) / 100;
        payable(msg.sender).transfer(recompensa);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C9-logica-negocio/WRITEUP.md`](../src/C9-logica-negocio/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. Desplegar el reto (con 5 ETH).
2. Desplegar el contrato atacante y llamar a `atacar()` con 1 ETH y 6 iteraciones.
3. Pulsar *Verificar solución*: `isSolved()` devuelve `true` y el reto queda resuelto.
