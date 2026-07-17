use starknet::ContractAddress;

#[starknet::interface]
pub trait IMaliciousERC20Config<TContractState> {
    fn configure_attack(
        ref self: TContractState,
        target: ContractAddress,
        token_id: u256,
        mode: u8,
        reentry_amount: u256,
    );
}

/// ERC-20 that attacks the crowdfunding collection from inside its own
/// transfer hooks — reentering contribute/withdraw/refund/proceeds, or
/// short-transferring on transfer_from (fee-on-transfer behavior).
#[starknet::contract]
pub mod MaliciousERC20 {
    use core::num::traits::Zero;
    use openzeppelin_token::erc20::interface::IERC20;
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::storage::{
        StorageMapReadAccess, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::interface::{
        IIPCrowdfundingCollectionDispatcher, IIPCrowdfundingCollectionDispatcherTrait,
    };
    use crate::mock::mock_erc20::IERC20Mint;
    use super::IMaliciousERC20Config;

    pub const ATTACK_CONTRIBUTE: u8 = 1;
    pub const ATTACK_WITHDRAW: u8 = 2;
    pub const ATTACK_REFUND: u8 = 3;
    pub const ATTACK_PROCEEDS: u8 = 4;
    pub const SHORT_TRANSFER_FROM: u8 = 5;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        target: ContractAddress,
        token_id: u256,
        mode: u8,
        reentry_amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray) {
        self.erc20.initializer(name, symbol);
    }

    #[abi(embed_v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn total_supply(self: @ContractState) -> u256 {
            self.erc20.ERC20_total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.ERC20_balances.read(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.erc20.ERC20_allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.maybe_attack_transfer();
            self.erc20._transfer(get_caller_address(), recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let caller = get_caller_address();
            self.erc20._spend_allowance(sender, caller, amount);
            self.maybe_attack_transfer_from();

            let transferred_amount = if self.mode.read() == SHORT_TRANSFER_FROM {
                amount - 1
            } else {
                amount
            };
            self.erc20._transfer(sender, recipient, transferred_amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20._approve(get_caller_address(), spender, amount);
            true
        }
    }

    #[abi(embed_v0)]
    impl MintImpl of IERC20Mint<ContractState> {
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.erc20.mint(recipient, amount);
        }
    }

    #[abi(embed_v0)]
    impl ConfigImpl of IMaliciousERC20Config<ContractState> {
        fn configure_attack(
            ref self: ContractState,
            target: ContractAddress,
            token_id: u256,
            mode: u8,
            reentry_amount: u256,
        ) {
            self.target.write(target);
            self.token_id.write(token_id);
            self.mode.write(mode);
            self.reentry_amount.write(reentry_amount);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn maybe_attack_transfer_from(ref self: ContractState) {
            if self.mode.read() == ATTACK_CONTRIBUTE {
                let target = self.target.read();
                if !target.is_zero() {
                    // Single-shot: clear the mode before reentering so the
                    // nested contribute's own transfer_from doesn't recurse.
                    self.mode.write(0);
                    IIPCrowdfundingCollectionDispatcher { contract_address: target }
                        .contribute(self.token_id.read(), self.reentry_amount.read());
                }
            }
        }

        fn maybe_attack_transfer(ref self: ContractState) {
            let target = self.target.read();
            if target.is_zero() {
                return;
            }

            let mode = self.mode.read();
            let collection = IIPCrowdfundingCollectionDispatcher { contract_address: target };
            if mode == ATTACK_WITHDRAW {
                collection.withdraw(self.token_id.read(), self.reentry_amount.read());
            }
            if mode == ATTACK_REFUND {
                collection.claim_refund(self.token_id.read());
            }
            if mode == ATTACK_PROCEEDS {
                collection.claim_proceeds(self.token_id.read());
            }
        }
    }
}
