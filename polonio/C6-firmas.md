# Reto C6: La Firma Reutilizable (Signature Replay)

- **Vulnerabilidad**: reutilización de firma (replay) sin nonce ni dominio
- **OWASP**: mención
- **SWC**: SWC-121
- **Nivel**: avanzado

Ficha del reto en Polonio. Probado en local (`test/C6-firmas.t.sol`, 6/6 en verde).

> El reto de Polonio es la **variante A** (replay). La variante B (maleabilidad) se documenta en la memoria pero no forma parte del reto: requiere construir la firma gemela, más propio de un ejercicio guiado que de un reto autónomo.

---

## 1. Contrato a desplegar

`FirmaReutilizable.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FirmaReutilizable {
    address public firmante;

    constructor(address _f) payable {
        firmante = _f;
    }

    // FALLO: el mensaje solo contiene (to, amount). Sin nonce, sin address(this),
    // sin chainid. La misma firma vale infinitas veces.
    function retirar(address to, uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 hash = keccak256(abi.encodePacked(to, amount));
        require(ecrecover(hash, v, r, s) == firmante, "firma invalida");
        payable(to).transfer(amount);
    }

    function isSolved() external view returns (bool) {
        return address(this).balance == 0;
    }
}
```

## 2. Firma proporcionada al jugador

El reto entrega una firma del `firmante` que autoriza **1 ETH** a la cuenta del jugador (`accounts[1]` de Anvil, `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`). Se incluye en el enunciado/writeup:

```
to     = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
amount = 1000000000000000000           (1 ETH)
v      = 28
r      = 0x348fe8bd903828cd8629fe21b7786d9c8b9fd90f9c7fd8795a2657f59e78f491
s      = 0x1d19ae5923e221ef33a54baf8130f826fc39de0034cc23a70ca843ccfe230eb4
```

> Estos valores están generados con una clave de firmante fija y el encoding exacto del contrato (`keccak256(abi.encodePacked(to, amount))`). El `firmante` del constructor es la dirección derivada de esa clave (`0x56262F17...`). Si se cambia la cuenta del jugador o el importe, hay que regenerar la firma.

## 3. writeup.md

El writeup del reto está en su propio fichero, [`src/C6-firmas/WRITEUP.md`](../src/C6-firmas/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 4. Comprobación en Polonio

1. Desplegar el reto (con el `firmante` en el constructor y 3 ETH).
2. Llamar a `retirar(...)` tres veces con la firma dada, desde `accounts[1]`.
3. Pulsar *Verificar solución*: `isSolved()` devuelve `true` y el reto queda resuelto.
