/// Minimal mock account for testing safe_mint.
///
/// On Starknet, all real user wallets are deployed account contracts implementing SRC6.
/// safe_mint calls supports_interface(ISRC6_ID) on the recipient; this mock returns true,
/// allowing safe_mint to succeed exactly as it would with a real user wallet.
#[starknet::contract]
pub mod MockAccount {
    use openzeppelin::account::interface::ISRC6_ID;
    use openzeppelin::introspection::src5::SRC5Component;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.src5.register_interface(ISRC6_ID);
    }
}
