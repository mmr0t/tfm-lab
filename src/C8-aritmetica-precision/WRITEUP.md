# C8. Errores aritméticos y de precisión: writeup

Este documento explica cómo resolver el reto del caso C8 y las otras dos variantes que se estudian en el laboratorio. El análisis completo está en la sección 4.8 de la memoria.

## El reto: El Vault Inflable

En Polonio el reto se llama `VaultInflable` y despliega tres contratos: `AssetReto` (el token), `VaultInflable` y `DepositanteHonesto` (la víctima). En el laboratorio, el vault equivalente es `VaultVulnerable` (`src/C8-aritmetica-precision/Vulnerable.sol`).

**Escenario.**

- Un vault recién creado y vacío acepta depósitos de ASSET y entrega a cambio participaciones (*shares*), en proporción a lo que ya contiene.
- Tú tienes 2.000 ASSET.
- Una persona, representada por el contrato `DepositanteHonesto`, tiene 500 ASSET y un depósito pendiente. Su función `depositar()` hace ese depósito cuando alguien la llama, una sola vez.

**Objetivo.** Quedarte con el depósito de la víctima. El reto se da por resuelto cuando tu saldo de ASSET supera los 2.000 iniciales.

En una red pública, el depósito de la víctima sería una transacción esperando en la cola, y el atacante se adelantaría a ella. En la red local no hay cola, así que eres tú quien decide cuándo llamar a `depositar()`.

## La vulnerabilidad

```solidity
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
```

Hay dos problemas que, juntos, permiten el ataque:

1. **La división trunca.** En la EVM no hay decimales. Si el resultado de `assets * totalShares / totalAssets()` es menor que 1, el depositante recibe 0 participaciones, aunque haya entregado sus tokens.
2. **`totalAssets()` es el saldo real del contrato.** Cualquiera puede aumentarlo transfiriendo tokens directamente al vault, sin pasar por `deposit` y, por tanto, sin recibir participaciones. Esa "donación" cambia el valor de cada participación a voluntad del atacante.

## Resolución paso a paso

Todo se hace desde tu cuenta, con llamadas normales:

1. **Autorizar al vault** a mover tus tokens: `AssetReto.approve(<VaultInflable>, <cantidad grande>)`.
2. **Ser el primer depositante con 1 wei:** `VaultInflable.deposit(1)`. Como el vault estaba vacío, recibes 1 participación. Es la única que existe.
3. **Donar 1.000 ASSET** directamente al vault: `AssetReto.transfer(<VaultInflable>, 1000 * 10^18)`. El vault no emite participaciones por ello, así que tu única participación pasa a valer 1.000 ASSET.
4. **Dejar que la víctima deposite:** `DepositanteHonesto.depositar()`. Sus participaciones se calculan como `500 * 1 / 1000`, que se trunca a **0**. Sus 500 ASSET entran en el vault, pero no recibe nada a cambio.
5. **Canjear tu participación:** `VaultInflable.redeem(1)`. Como eres el dueño de la única participación, recibes todo el saldo: 1.500 ASSET.
6. **Verificar.** Acabas con 2.500 ASSET: tus 2.000 más los 500 de la víctima.

Estado del vault durante el ataque:

| Paso | Activos del vault | Participaciones totales | Resultado |
|---|---|---|---|
| 2 | 1 wei | 1 | Recibes 1 participación |
| 3 | 1.000 ASSET + 1 wei | 1 | No se emiten participaciones |
| 4 | 1.500 ASSET + 1 wei | 1 | La víctima recibe 0 participaciones |
| 5 | 0 | 0 | Recibes 1.500 ASSET y 1 wei |

## Otras variantes del caso

**Redondeo a favor del usuario** (`CambioVulnerable`). Un contrato de intercambio cobra una comisión del 0,3 % calculada como `amount * 30 / 10000`, que trunca hacia abajo. Para cualquier importe menor que 334 unidades la comisión es 0, así que el atacante hace muchos intercambios pequeños y no paga nunca comisión. La prueba hace 1.000 intercambios de 333 unidades y recibe exactamente lo mismo que entrega.

**División antes de multiplicación** (`RepartoVulnerable`). Un contrato reparte recompensas entre los depositantes con un acumulador de recompensa por token:

```solidity
recompensaPorToken += (recompensa / totalDepositado) * 1e18;
```

Al dividir antes de escalar, el cociente pierde todos los decimales. Con 1.000.000 de tokens depositados y 1.500.000 de recompensa, el cociente 1,5 se trunca a 1: solo se reparte 1.000.000 y los 500.000 restantes quedan bloqueados para siempre. Una recompensa menor que el total depositado no se reparte en absoluto. Aquí no hay atacante: el propio cálculo hace perder fondos.

## Mitigación

La versión corregida (`src/C8-aritmetica-precision/Fixed.sol`) suma participaciones y activos virtuales en los cálculos, como hace OpenZeppelin en su implementación de ERC-4626:

```solidity
sharesMinted = (assets * (totalShares + OFFSET)) / (totalAssets() + 1);
// ...
assets = (s * (totalAssets() + 1)) / (totalShares + OFFSET);
```

Con un desplazamiento de 1.000 participaciones virtuales, la donación del atacante se reparte también entre ellas, y nadie puede canjearlas. El ataque no se vuelve imposible, pero deja de ser rentable: con los mismos importes, la víctima recibe 999 participaciones y el atacante recupera unos 500 de los 1.000 ASSET que donó.

Para las otras variantes:

- **Redondeo**: redondear hacia arriba, en contra de quien paga, y exigir un importe mínimo para que la comisión nunca sea 0.
- **División antes de multiplicación**: multiplicar primero, `(recompensa * 1e18) / totalDepositado`, para conservar 18 decimales de precisión.

Como regla general, cada división de un contrato es una decisión sobre quién se queda con el resto, y debe redondear siempre a favor del contrato y no del usuario.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C8_AritmeticaPrecision
./forge test --match-contract C8_AritmeticaPrecision --match-test test_Exploit_Vulnerable -vvvv
FOUNDRY_PROFILE=polonio ./forge test --match-test test_C8
```

La última orden ejecuta la simulación del reto tal como se despliega en Polonio (`polonio/simulacion/`).

| Variante | Ataque | Mitigación |
|---|---|---|
| Inflación del primer depositante | `test_Exploit_Vulnerable` | `test_Fixed_Resiste` |
| Redondeo a favor del usuario | `test_Exploit_Redondeo_Vulnerable` | `test_Fixed_Redondeo_Resiste` |
| División antes de multiplicación | `test_Exploit_DivisionAntesMultiplicacion_Vulnerable` | `test_Fixed_DivisionAntesMultiplicacion_Resiste` |
