pub mod errors;
pub mod interface;
pub mod types;

pub mod contract {
    pub mod ip_syndication;
}

pub mod mock {
    pub mod erc20;
    pub mod malicious_erc20;
    pub mod mock_erc1155_receiver;
    pub mod reentrant_erc1155_receiver;
}
