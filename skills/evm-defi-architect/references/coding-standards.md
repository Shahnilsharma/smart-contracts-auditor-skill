# Solidity coding standards (enforce in every generated contract)

- **Errors**: custom `error` types, not `require(cond, "string")` — cheaper deploy/revert gas, clearer ABI-level errors.
- **Reentrancy**: checks-effects-interactions ordering always; `nonReentrant` (OZ `ReentrancyGuard`) on any function combining external calls with state writes. Treat any external call (including plain ETH `.call{value:}`, ERC-777 hooks, ERC-721/1155 receiver callbacks) as a potential reentry point.
- **Token transfers**: `SafeERC20.safeTransfer`/`safeTransferFrom` — never assume a token reverts on failure or returns `true`; account for fee-on-transfer and rebasing tokens explicitly if the protocol might list arbitrary tokens (compare balance-before/after rather than trusting the transferred amount).
- **Access control**: explicit modifier or `AccessControl` role check as the first statement of every privileged function. No security-by-obscurity (unguarded but "hidden" admin functions).
- **Arithmetic**: Solidity ≥0.8 has built-in overflow/underflow checks — don't wrap in `unchecked{}` unless the bound is proven safe and documented inline with why.
- **Randomness**: never use `block.timestamp`/`blockhash`/`block.prevrandao` alone as an unpredictable source for anything of value — use Chainlink VRF or equivalent commit-reveal if randomness is load-bearing.
- **Proxies/upgrades**: if upgradeable, use OZ upgradeable contracts, storage gaps (`__gap`), `_disableInitializers()` in the implementation constructor, and a timelock/multisig for upgrade authority. Never let `initialize()` be callable twice or by an unauthorized caller.
- **Signatures**: EIP-712 typed data with domain separator including `chainId` and contract address; always include and check a nonce to prevent replay, and invalidate used signatures.
- **Events**: emit on every state-changing action with indexed key params, for indexers and audit trails.
- **Input validation**: reject zero-address where it would brick funds, reject zero-amount where it's a meaningless/no-op-but-costly call, validate array lengths match before parallel-array loops.
- **Loops**: no unbounded iteration over user-growable arrays/mappings in a single external call — paginate or cap.
- **Self-destruct**: don't design fund-recovery or cleanup logic around `SELFDESTRUCT` — post-Cancun (EIP-6780) it only deletes code/self-destructs within the same transaction it was created, it's not a reliable "drain funds and delete" primitive anymore.
- **Testing hook parity**: every function here should have a matching Foundry unit+fuzz test and, for state-machine-relevant functions, a Hardhat scenario step (see `testing-foundry.md` / `testing-hardhat.md`).
