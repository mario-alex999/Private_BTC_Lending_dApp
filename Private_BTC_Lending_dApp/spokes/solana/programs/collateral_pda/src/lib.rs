use anchor_lang::prelude::*;
use anchor_lang::system_program::{transfer, Transfer};

declare_id!("ColLtR1pda111111111111111111111111111111111");

#[program]
pub mod collateral_pda {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, starknet_address_hash: [u8; 32]) -> Result<()> {
        let collateral = &mut ctx.accounts.collateral;
        collateral.depositor = ctx.accounts.depositor.key();
        collateral.starknet_address_hash = starknet_address_hash;
        collateral.total_lamports = 0;
        collateral.bump = ctx.bumps.collateral;
        Ok(())
    }

    pub fn deposit_sol(
        ctx: Context<DepositSol>,
        starknet_address_hash: [u8; 32],
        amount_lamports: u64,
    ) -> Result<()> {
        require!(amount_lamports > 0, CollateralError::InvalidAmount);

        let collateral = &mut ctx.accounts.collateral;
        require!(
            collateral.starknet_address_hash == starknet_address_hash,
            CollateralError::StarknetHashMismatch
        );

        transfer(
            CpiContext::new(
                ctx.accounts.system_program.to_account_info(),
                Transfer {
                    from: ctx.accounts.depositor.to_account_info(),
                    to: collateral.to_account_info(),
                },
            ),
            amount_lamports,
        )?;

        collateral.total_lamports = collateral
            .total_lamports
            .checked_add(amount_lamports)
            .ok_or(CollateralError::Overflow)?;

        emit!(CollateralDeposited {
            depositor: collateral.depositor,
            starknet_address_hash,
            amount_lamports,
            slot: Clock::get()?.slot,
        });

        Ok(())
    }
}

#[derive(Accounts)]
#[instruction(starknet_address_hash: [u8; 32])]
pub struct Initialize<'info> {
    #[account(mut)]
    pub depositor: Signer<'info>,
    #[account(
        init,
        payer = depositor,
        space = 8 + CollateralAccount::INIT_SPACE,
        seeds = [b"collateral", depositor.key().as_ref(), starknet_address_hash.as_ref()],
        bump
    )]
    pub collateral: Account<'info, CollateralAccount>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(starknet_address_hash: [u8; 32])]
pub struct DepositSol<'info> {
    #[account(mut)]
    pub depositor: Signer<'info>,
    #[account(
        mut,
        seeds = [b"collateral", depositor.key().as_ref(), starknet_address_hash.as_ref()],
        bump = collateral.bump,
        has_one = depositor
    )]
    pub collateral: Account<'info, CollateralAccount>,
    pub system_program: Program<'info, System>,
}

#[account]
#[derive(InitSpace)]
pub struct CollateralAccount {
    pub depositor: Pubkey,
    pub starknet_address_hash: [u8; 32],
    pub total_lamports: u64,
    pub bump: u8,
}

#[event]
pub struct CollateralDeposited {
    pub depositor: Pubkey,
    pub starknet_address_hash: [u8; 32],
    pub amount_lamports: u64,
    pub slot: u64,
}

#[error_code]
pub enum CollateralError {
    #[msg("Deposit amount must be > 0")]
    InvalidAmount,
    #[msg("Starknet address hash mismatch")]
    StarknetHashMismatch,
    #[msg("Arithmetic overflow")]
    Overflow,
}
