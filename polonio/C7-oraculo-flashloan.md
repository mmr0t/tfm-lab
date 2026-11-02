# Reto C7: El Oráculo Manipulable (oráculo + préstamo flash)

- **Vulnerabilidad**: oráculo de precio *spot* manipulable, amplificado con préstamo flash
- **OWASP**: SC03/SC04
- **Nivel**: avanzado

Ficha del reto en Polonio. El ataque y la mitigación están probados en el laboratorio (`test/C7-oraculo-flashloan.t.sol`, 3/3 en verde). El despliegue, el estado inicial y la condición de éxito de esta ficha se simularon con Foundry en EVM `paris`, la de Polonio (`FOUNDRY_PROFILE=polonio ./forge test`, en `polonio/simulacion/`): sin atacar el reto no se resuelve, los atajos están cerrados y la solución del writeup lo resuelve.

## Reto multi-contrato con preparación

El reto necesita cinco contratos desplegados en orden y un estado inicial que se prepara tras el despliegue: liquidez en el AMM, fondos en el prestamista flash y en el protocolo, y 1 TOKEN para el jugador.

Diferencias con los contratos del laboratorio, necesarias porque en Polonio el jugador puede llamar a cualquier función:
- Cada contrato va en su propio fichero y con nombre propio (`TokenReto` y `UsdcReto` en lugar de dos `MiniToken`), para poder distinguirlos.
- `mint` solo lo puede llamar quien despliega. En el laboratorio estaba abierto (es un arnés), pero aquí el jugador podría acuñarse USDC y resolver el reto sin atacar el oráculo.
- `init` del AMM solo lo puede llamar quien despliega y una sola vez, por el mismo motivo.
- El AMM no incluye el acumulador TWAP, que solo usa la versión corregida.

| Orden | Contrato | Constructor |
|---|---|---|
| 0 | `TokenReto` | sin parámetros |
| 1 | `UsdcReto` | sin parámetros |
| 2 | `AmmReto` | `address TokenReto`, `address UsdcReto` |
| 3 | `PrestamistaFlash` | `address UsdcReto` |
| 4 | `PrestamosVulnerable` | `address TokenReto`, `address UsdcReto`, `address AmmReto` |

---

## 1. Contratos a desplegar

`TokenReto.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice ERC20 mínimo del reto (TOKEN). Solo quien lo despliega puede acuñar.
contract TokenReto {
    string public constant name = "TOKEN";
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

`UsdcReto.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice ERC20 mínimo del reto (USDC). Solo quien lo despliega puede acuñar.
contract UsdcReto {
    string public constant name = "USDC";
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

`AmmReto.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function transfer(address to, uint256 a) external returns (bool);
    function transferFrom(address f, address to, uint256 a) external returns (bool);
}

/// @notice AMM de producto constante (x*y=k), sin comisiones.
/// Las reservas fijan el precio spot que lee el protocolo de préstamos.
contract AmmReto {
    IToken public immutable token;
    IToken public immutable usdc;
    address public immutable admin;
    uint256 public reserveToken;
    uint256 public reserveUsdc;

    constructor(address t, address u) {
        token = IToken(t);
        usdc = IToken(u);
        admin = msg.sender;
    }

    /// @notice Liquidez inicial. Solo el admin y una sola vez.
    function init(uint256 t, uint256 u) external {
        require(msg.sender == admin, "solo admin");
        require(reserveToken == 0 && reserveUsdc == 0, "ya iniciado");
        token.transferFrom(msg.sender, address(this), t);
        usdc.transferFrom(msg.sender, address(this), u);
        reserveToken = t;
        reserveUsdc = u;
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveToken, reserveUsdc);
    }

    function swapUsdcForToken(uint256 usdcIn) external returns (uint256 tokenOut) {
        usdc.transferFrom(msg.sender, address(this), usdcIn);
        uint256 k = reserveToken * reserveUsdc;
        uint256 newUsdc = reserveUsdc + usdcIn;
        uint256 newToken = k / newUsdc;
        tokenOut = reserveToken - newToken;
        reserveToken = newToken;
        reserveUsdc = newUsdc;
        token.transfer(msg.sender, tokenOut);
    }

    function swapTokenForUsdc(uint256 tokenIn) external returns (uint256 usdcOut) {
        token.transferFrom(msg.sender, address(this), tokenIn);
        uint256 k = reserveToken * reserveUsdc;
        uint256 newToken = reserveToken + tokenIn;
        uint256 newUsdc = k / newToken;
        usdcOut = reserveUsdc - newUsdc;
        reserveToken = newToken;
        reserveUsdc = newUsdc;
        usdc.transfer(msg.sender, usdcOut);
    }
}
```

`PrestamistaFlash.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function balanceOf(address a) external view returns (uint256);
    function transfer(address to, uint256 a) external returns (bool);
}

interface IFlashBorrower {
    function onFlashLoan(uint256 amount) external;
}

/// @notice Prestamista flash de USDC sin comisión. Revierte si no se devuelve.
contract PrestamistaFlash {
    IToken public immutable usdc;

    constructor(address u) {
        usdc = IToken(u);
    }

    function flashLoan(uint256 amount) external {
        uint256 saldoAntes = usdc.balanceOf(address(this));
        usdc.transfer(msg.sender, amount);
        IFlashBorrower(msg.sender).onFlashLoan(amount);
        require(usdc.balanceOf(address(this)) >= saldoAntes, "flash no devuelto");
    }
}
```

`PrestamosVulnerable.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    function balanceOf(address a) external view returns (uint256);
    function transfer(address to, uint256 a) external returns (bool);
    function transferFrom(address f, address to, uint256 a) external returns (bool);
}

interface IAmm {
    function getReserves() external view returns (uint256, uint256);
}

/// @notice Protocolo de préstamos que valora el colateral con el precio SPOT
/// del AMM. Un préstamo flash puede mover ese precio en la misma transacción.
contract PrestamosVulnerable {
    IToken public immutable token;
    IToken public immutable usdc;
    IAmm public immutable amm;
    mapping(address => uint256) public colateral;
    mapping(address => uint256) public deuda;

    constructor(address t, address u, address a) {
        token = IToken(t);
        usdc = IToken(u);
        amm = IAmm(a);
    }

    // FALLO: precio spot leído directo de las reservas.
    function precioToken() public view returns (uint256) {
        (uint256 rt, uint256 ru) = amm.getReserves();
        return (ru * 1e18) / rt;
    }

    function depositar(uint256 amt) external {
        token.transferFrom(msg.sender, address(this), amt);
        colateral[msg.sender] += amt;
    }

    function pedir(uint256 amt) external {
        uint256 maxDeuda = (colateral[msg.sender] * precioToken()) / 1e18;
        require(deuda[msg.sender] + amt <= maxDeuda, "sobre-colateralizado");
        deuda[msg.sender] += amt;
        usdc.transfer(msg.sender, amt);
    }

    /// @notice Condición de éxito: el protocolo se queda sin USDC.
    function isSolved() external view returns (bool) {
        return usdc.balanceOf(address(this)) == 0;
    }
}
```

## 2. writeup.md

El writeup del reto está en su propio fichero, [`src/C7-oraculo-flashloan/WRITEUP.md`](../src/C7-oraculo-flashloan/WRITEUP.md), junto a los contratos del caso. Explica el escenario, la vulnerabilidad, la resolución paso a paso, las otras variantes del laboratorio, la mitigación y las pruebas que lo comprueban.

## 3. Comprobación en Polonio

1. Desplegar el reto. Comprobar que el despliegue termina sin errores y que `PrestamosVulnerable.precioToken()` devuelve `1000000000000000000000` (1.000 USDC).
2. *Verificar solución* antes de atacar: debe indicar que el reto no está resuelto.
3. Desplegar `AtacanteOraculo`, transferirle el TOKEN y llamar a `atacar()`.
4. *Verificar solución*: reto resuelto.
