pub mod IPCollection;
pub mod IPCollectionFactory;
pub mod types;

pub mod interfaces {
    pub mod IIPCollection;
    pub mod IIPCollectionFactory;
}

pub mod mock_contracts {
    pub mod ERC1155Receiver;
    pub mod MockAccount;
}

#[cfg(test)]
mod tests {
    mod IPCollectionFactoryTest;
    mod IPCollectionTest;
}
