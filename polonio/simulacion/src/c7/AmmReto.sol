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
