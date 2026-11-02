// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Caso C7 - Manipulación de oráculos de precio amplificada con préstamo flash.
// OWASP SC03 (oráculos) y SC04 (flash loans). SWC: ninguno directo (fallo de
// arquitectura). Para tener un escenario autocontenido y sin fees (se omiten para
// que las cuentas cuadren de forma exacta) se incluyen un ERC20 mínimo, un AMM de
// producto constante, un prestamista flash y el protocolo de préstamos vulnerable.

/// @notice ERC20 mínimo para el escenario (sin fees, sin eventos).
contract MiniToken {
    string public name;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n) {
        name = n;
    }

    function mint(address to, uint256 a) external {
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

/// @notice AMM de producto constante (x*y=k), sin comisiones.
/// Igual que Uniswap V2, acumula el precio ponderado en el tiempo
/// (`precioAcumulado`) para que un oráculo TWAP pueda leerlo. El protocolo
/// vulnerable no lo usa: lee directamente las reservas (precio spot).
contract SimpleAMM {
    MiniToken public token;
    MiniToken public usdc;
    uint256 public reserveToken;
    uint256 public reserveUsdc;

    // Suma de (precio spot x segundos) desde el despliegue, en USDC/token con 18
    // decimales. Se actualiza ANTES de cambiar las reservas, de modo que el precio
    // resultante de un swap solo empieza a pesar cuando pasa el tiempo.
    uint256 public precioAcumulado;
    uint256 public ultimaActualizacion;

    function _acumular() internal {
        uint256 transcurrido = block.timestamp - ultimaActualizacion;
        if (transcurrido > 0 && reserveToken > 0) {
            precioAcumulado += (reserveUsdc * 1e18 * transcurrido) / reserveToken;
        }
        ultimaActualizacion = block.timestamp;
    }

    /// @notice Valor del acumulador en este instante (incluye el tramo pendiente).
    function precioAcumuladoActual() external view returns (uint256) {
        uint256 transcurrido = block.timestamp - ultimaActualizacion;
        if (reserveToken == 0) return precioAcumulado;
        return precioAcumulado + (reserveUsdc * 1e18 * transcurrido) / reserveToken;
    }

    constructor(address t, address u) {
        token = MiniToken(t);
        usdc = MiniToken(u);
    }

    function init(uint256 t, uint256 u) external {
        token.transferFrom(msg.sender, address(this), t);
        usdc.transferFrom(msg.sender, address(this), u);
        _acumular();
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
        _acumular();
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
        _acumular();
        reserveToken = newToken;
        reserveUsdc = newUsdc;
        usdc.transfer(msg.sender, usdcOut);
    }
}

interface IFlashBorrower {
    function onFlashLoan(uint256 amount) external;
}

/// @notice Prestamista flash de USDC sin comisión. Revierte si no se devuelve.
contract FlashLender {
    MiniToken public usdc;

    constructor(address u) {
        usdc = MiniToken(u);
    }

    function flashLoan(uint256 amount) external {
        uint256 saldoAntes = usdc.balanceOf(address(this));
        usdc.transfer(msg.sender, amount);
        IFlashBorrower(msg.sender).onFlashLoan(amount);
        require(usdc.balanceOf(address(this)) >= saldoAntes, "flash no devuelto");
    }
}

/// @notice Protocolo de préstamos vulnerable.
/// Valora el colateral con el precio SPOT del AMM, que un flash loan puede mover
/// en la misma transacción. El atacante infla el precio, deposita un colateral
/// minúsculo que "vale" muchísimo y drena el USDC del protocolo.
contract PrestamosVulnerable {
    MiniToken public token;
    MiniToken public usdc;
    SimpleAMM public amm;
    mapping(address => uint256) public colateral;
    mapping(address => uint256) public deuda;

    constructor(address t, address u, address a) {
        token = MiniToken(t);
        usdc = MiniToken(u);
        amm = SimpleAMM(a);
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
