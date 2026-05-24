pub mod IPCollection;
pub mod types;

pub mod interfaces {
    pub mod IIPCollection;
}

pub mod mock_contracts {
    pub mod MockAccount;
    pub mod Receiver;
}

#[cfg(test)]
mod tests {
    mod IPCollectionTest;
}
