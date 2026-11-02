# Reto C8: El Vault Inflable (precisión, inflación del primer depositante)

- **Vulnerabilidad**: ataque de inflación del primer depositante en un vault estilo ERC-4626
- **OWASP**: SC07
- **Nivel**: avanzado

Ficha del reto en Polonio. El ataque y la mitigación están probados en el laboratorio (`test/C8-aritmetica-precision.t.sol`, 6/6 en verde). El despliegue, el estado inicial y la condición de éxito de esta ficha se simularon con Foundry en EVM `paris`, la de Polonio (`FOUNDRY_PROFILE=polonio ./forge test`, en `polonio/simulacion/`): sin atacar el reto no se resuelve, el atajo de acuñar está cerrado y la solución del writeup lo resuelve.

> El reto de Polonio es la **variante A** (inflación del primer depositante). Las variantes B (redondeo a favor del usuario) y C (división antes de multiplicación) se documentan en la memoria y se prueban en el laboratorio, pero no forman parte del reto: su efecto es una pérdida o un bloqueo de fondos, no un objetivo que el jugador "gane".

## Un reto con víctima

El ataque necesita una víctima que deposite *después* de que el atacante prepare el vault. En una red pública, el atacante vería la transacción de depósito de la víctima en la cola y se adelantaría a ella. En la red local de Polonio no hay cola de transacciones, así que la víctima es un contrato, `DepositanteHonesto`, con 500 ASSET y una función `depositar()` que cualquiera puede llamar una sola vez: llamarla equivale a que la transacción pendiente de la víctima entre en un bloque. El jugador decide cuándo ocurre, igual que un atacante que se adelanta.

La condición de éxito no puede ser "la víctima tiene 0 participaciones", porque se cumpliría también si la víctima nunca deposita. Se usa una condición sobre el resultado: **el jugador acaba con más ASSET de los 2.000 que tenía**. La única fuente posible de ese beneficio es el depósito de la víctima.

Diferencias con los contratos del laboratorio: `AssetReto` solo deja acuñar a quien lo despliega (en el laboratorio el token es un arnés abierto) y se añade el contrato de la víctima.

| Orden | Contrato | Constructor |
|---|---|---|
| 0 | `AssetReto` | sin parámetros |
| 1 | `VaultInflable` | `address AssetReto` |
| 2 | `DepositanteHonesto` | `address AssetReto`, `address VaultInflable` |

---

## 1. Contratos a desplegar

`AssetReto.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice ERC20 mínimo del reto (ASSET). Solo quien lo despliega puede acuñar.
contract AssetReto {
    string public constant name = "ASSET";
    uint8 public constant decimals = 18;
    address public immutable admin;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        admin = msg.sender;
    }

    function mint(address to, uint256 a) external {
        require(msg.sender == admin, "solo admin");
        balanceOf[to] += a;
        totalSupply += a;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        _t(msg.sender, to, a);
        return true;
    }

    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        require(al >= a, "allowance");
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        _t(f, to, a);
        return true;
    }

    function _t(address f, address to, uint256 a) internal {
        require(balanceOf[f] >= a, "balance");
        balanceOf[f] -= a;
        balanceOf[to] += a;
    }
}
```

`VaultInflable.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function balanceOf(address a) external view returns (uint256);
    function transfer(address to, uint256 a) external returns (bool);
    function transferFrom(address f, address to, uint256 a) external returns (bool);
}

/// @notice Vault estilo ERC-4626 sin participaciones virtuales ni depósito
/// mínimo. Las participaciones se calculan con una división que trunca.
contract VaultInflable {
    IToken public immutable asset;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    constructor(address a) {
        asset = IToken(a);
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function deposit(uint256 assets) external returns (uint256 sharesMinted) {
        sharesMinted = totalShares == 0
            ? assets
            : (assets * totalShares) / totalAssets(); // trunca: puede dar 0
        asset.transferFrom(msg.sender, address(this), assets);
        shares[msg.sender] += sharesMinted;
        totalShares += sharesMinted;
    }

    function redeem(uint256 s) external returns (uint256 assets) {
        assets = (s * totalAssets()) / totalShares;
        shares[msg.sender] -= s;
        totalShares -= s;
        asset.transfer(msg.sender, assets);
    }
}
```

`DepositanteHonesto.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function balanceOf(address a) external view returns (uint256);
    function approve(address s, uint256 a) external returns (bool);
}

interface IVault {
    function deposit(uint256 assets) external returns (uint256);
}

/// @notice La víctima: tiene 500 ASSET y una transacción de depósito pendiente.
/// En una red pública su transacción esperaría en la cola y el atacante podría
/// adelantarse a ella. En la red local del reto no hay cola de transacciones, así
/// que cualquiera puede "liberar" el depósito llamando a depositar() una vez.
contract DepositanteHonesto {
    IToken public immutable asset;
    IVault public immutable vault;
    bool public depositado;

    constructor(address a, address v) {
        asset = IToken(a);
        vault = IVault(v);
    }

    function depositar() external {
        require(!depositado, "ya depositado");
        depositado = true;
        uint256 saldo = asset.balanceOf(address(this));
        asset.approve(address(vault), saldo);
        vault.deposit(saldo);
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C8-aritmetica-precision/WRITEUP.md`](../src/C8-aritmetica-precision/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. Desplegar el reto y comprobar que `AssetReto.balanceOf(jugador)` es 2.000 ASSET y `AssetReto.balanceOf(DepositanteHonesto)` es 500 ASSET.
2. *Verificar solución* antes de atacar: debe indicar que el reto no está resuelto.
3. Seguir los pasos del writeup.
4. *Verificar solución*: reto resuelto (saldo del jugador, 2.500 ASSET).
