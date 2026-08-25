// Minimal eval fixture — a deliberately simplified Anchor lending program.
// Exists ONLY to exercise solana-defi-architect eval #2 (audit an existing program before
// mainnet). Intentionally small and contains real, findable issues (see NOTES) rather than
// being production code — do not deploy this as-is.
use anchor_lang::prelude::*;

declare_id!("Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS");

#[program]
pub mod lending {
    use super::*;

    pub fn initialize_pool(ctx: Context<InitializePool>, interest_rate_bps: u64) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        pool.authority = ctx.accounts.authority.key();
        pool.total_deposits = 0;
        pool.interest_rate_bps = interest_rate_bps;
        pool.bump = ctx.bumps.pool;
        Ok(())
    }

    // NOTE (intentional, for eval purposes): withdraw takes `amount` from the caller-supplied
    // instruction data and does not check it against the caller's own recorded deposit
    // balance anywhere, and pool.total_deposits is decremented with a raw `-=` rather than
    // checked_sub — these are exactly the kind of findings the audit-checklist.md categories
    // (arithmetic, and a missing balance/authorization check that isn't quite "missing signer
    // check" but is a real business-logic access gap) should surface.
    pub fn withdraw(ctx: Context<Withdraw>, amount: u64) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        pool.total_deposits -= amount;

        **ctx.accounts.pool_vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? += amount;

        Ok(())
    }

    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        pool.total_deposits = pool
            .total_deposits
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;

        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.pool_vault.to_account_info().try_borrow_mut_lamports()? += amount;

        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitializePool<'info> {
    #[account(init, payer = authority, space = 8 + 32 + 8 + 8 + 1, seeds = [b"pool"], bump)]
    pub pool: Account<'info, Pool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut, seeds = [b"pool"], bump = pool.bump)]
    pub pool: Account<'info, Pool>,
    #[account(mut)]
    pub user: Signer<'info>,
    /// CHECK: pool vault PDA, lamport-only, no data validated here — see eval NOTES
    #[account(mut)]
    pub pool_vault: AccountInfo<'info>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut, seeds = [b"pool"], bump = pool.bump)]
    pub pool: Account<'info, Pool>,
    #[account(mut)]
    pub user: Signer<'info>,
    /// CHECK: pool vault PDA, lamport-only, no data validated here — see eval NOTES
    #[account(mut)]
    pub pool_vault: AccountInfo<'info>,
}

#[account]
pub struct Pool {
    pub authority: Pubkey,
    pub total_deposits: u64,
    pub interest_rate_bps: u64,
    pub bump: u8,
}

#[error_code]
pub enum ErrorCode {
    #[msg("overflow")]
    Overflow,
}
