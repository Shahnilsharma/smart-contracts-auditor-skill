# Foundry testing pattern (unit + fuzz + invariant + symbolic)

## Setup
`forge init`, then `.cargo`-equivalent is `foundry.toml` — set `evm_version` to match target chain (see `references/ethereum-chain-defaults.md`), `via_ir = true` if gas optimization needs it (5–15% typical reduction, slower compile).

## Unit tests — `test/<Contract>.t.sol`
One test per branch, happy + revert:
```solidity
function test_deposit_happyPath() public { ... }
function test_RevertWhen_UnauthorizedCaller() public {
    vm.expectRevert(Unauthorized.selector);
    vm.prank(attacker);
    target.adminOnlyFn();
}
```

## Fuzz tests — parametric, `testFuzz_` prefix
Any test function taking parameters is auto-fuzzed by `forge test`. Use `vm.assume()` sparingly (rejects too many inputs slows fuzzing) and prefer `bound()` to constrain ranges:
```solidity
function testFuzz_withdraw_returnsExactDeposit(uint256 amount) public {
    amount = bound(amount, 1, MAX_DEPOSIT);
    vault.deposit(amount);
    assertEq(vault.withdraw(amount), amount);
}
```
Default `fuzz.runs = 256`; raise for release-grade passes (`--fuzz-runs 10000` or set in `foundry.toml`).

## Invariant tests — stateful, system-wide properties
```solidity
contract VaultInvariantTest is Test {
    VaultHandler handler;
    function setUp() public {
        handler = new VaultHandler(vault);
        targetContract(address(handler)); // fuzz calls through the handler, not the raw contract
    }
    function invariant_solvency() public view {
        assertGe(address(vault).balance, vault.totalDeposits());
    }
}
```
- Use a **handler** contract wrapping realistic call sequences (with `vm.prank`/`deal` for actor setup) rather than exposing the raw contract to the fuzzer directly — otherwise most random sequences just revert and don't exercise real state.
- Track **ghost variables** in the handler (e.g. running sum of deposits) to compare against contract state in the invariant.
- Config in `foundry.toml`: `runs` (sequences run), `depth` (calls per sequence), `fail_on_revert` (default false — reverts just end that run, don't fail the campaign).
- Use `max_time_delay`/`max_block_delay` when the property depends on elapsed time/blocks (vesting, auctions, TWAPs, cooldowns).
- Add `show_metrics = true` and a `callSummary()` helper to see which handler functions actually got exercised — an invariant with an unhit handler function isn't meaningfully tested.

## Symbolic testing (MVP feature — bounded proof, not a guarantee)
`check*`/`prove*` functions run under `forge test --symbolic`. PASS means "no counterexample found within the modeled EVM surface and configured bounds" — known gaps include gas accounting, some Cancun+ opcodes, and unknown external code. Use for arithmetic-heavy pure logic where a bounded proof adds real value, not as a replacement for fuzz/invariant/manual review.

## Commands
```bash
forge test -vvv                 # verbose trace on failure
forge coverage                  # line/branch coverage
forge snapshot                  # gas regression baseline, forge snapshot --diff after changes
forge test --match-test invariant_solvency -vvvv
```
