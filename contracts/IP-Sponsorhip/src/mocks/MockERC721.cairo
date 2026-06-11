// Test mock: minimal ERC-721 with a public mint, standing in for any IP
// asset contract (MIP collection, external collection, …).
#[starknet::interface]
pub trait IERC721Mint<TContractState> {
    fn mint(ref self: TContractState, recipient: starknet::ContractAddress, token_id: u256);
}

#[starknet::contract]
pub mod MockERC721 {
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc721::ERC721Component;
    use starknet::ContractAddress;
    use crate::mocks::MockERC721::IERC721Mint;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}
        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc721.initializer("Mock IP", "MIP", "");
    }

    #[abi(embed_v0)]
    impl MintImpl of IERC721Mint<ContractState> {
        fn mint(ref self: ContractState, recipient: ContractAddress, token_id: u256) {
            self.erc721.mint(recipient, token_id);
        }
    }
}
