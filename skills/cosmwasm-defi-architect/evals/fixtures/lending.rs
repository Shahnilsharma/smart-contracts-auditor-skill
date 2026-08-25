// Minimal eval fixture — a deliberately simplified CosmWasm lending contract.
// Exists ONLY to exercise cosmwasm-defi-architect eval #2 (audit an existing contract on a
// non-default chain, e.g. Injective). Intentionally small and contains real, findable issues
// (see NOTES) rather than being production code — do not deploy this as-is.
use cosmwasm_std::{
    entry_point, to_json_binary, Addr, Binary, Deps, DepsMut, Env, MessageInfo, Response,
    StdResult, Uint128,
};
use cw_storage_plus::{Item, Map};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Config {
    pub admin: Addr,
    pub total_deposits: Uint128,
}

pub const CONFIG: Item<Config> = Item::new("config");
pub const DEPOSITS: Map<&Addr, Uint128> = Map::new("deposits");

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum ExecuteMsg {
    Deposit {},
    Withdraw { amount: Uint128 },
}

#[entry_point]
pub fn execute(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    msg: ExecuteMsg,
) -> StdResult<Response> {
    match msg {
        ExecuteMsg::Deposit {} => execute_deposit(deps, info),
        ExecuteMsg::Withdraw { amount } => execute_withdraw(deps, info, amount),
    }
}

fn execute_deposit(deps: DepsMut, info: MessageInfo) -> StdResult<Response> {
    let sent = info
        .funds
        .iter()
        .find(|c| c.denom == "uzig")
        .map(|c| c.amount)
        .unwrap_or_default();

    let mut cfg = CONFIG.load(deps.storage)?;
    cfg.total_deposits += sent; // NOTE: raw += on Uint128, see eval NOTES below
    CONFIG.save(deps.storage, &cfg)?;

    let current = DEPOSITS.may_load(deps.storage, &info.sender)?.unwrap_or_default();
    DEPOSITS.save(deps.storage, &info.sender, &(current + sent))?;

    Ok(Response::new().add_attribute("action", "deposit"))
}

// NOTE (intentional, for eval purposes): `amount` here is never checked against the caller's
// own recorded deposit balance in DEPOSITS before subtracting — a caller can withdraw more
// than they deposited. Also `cfg.total_deposits += sent` above uses a raw operator rather than
// `checked_add`, and this function does the same with `checked_sub`'s absence below — these
// are exactly the kind of findings the audit-checklist.md Arithmetic and Funds-handling
// categories should surface.
fn execute_withdraw(deps: DepsMut, info: MessageInfo, amount: Uint128) -> StdResult<Response> {
    let mut cfg = CONFIG.load(deps.storage)?;
    cfg.total_deposits = cfg.total_deposits - amount; // no balance check against DEPOSITS[sender]
    CONFIG.save(deps.storage, &cfg)?;

    Ok(Response::new()
        .add_attribute("action", "withdraw")
        .add_attribute("amount", amount))
}

#[entry_point]
pub fn query(deps: Deps, _env: Env, _msg: ()) -> StdResult<Binary> {
    to_json_binary(&CONFIG.load(deps.storage)?)
}
