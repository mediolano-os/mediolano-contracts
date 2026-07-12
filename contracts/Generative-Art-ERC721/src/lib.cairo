pub mod GenerativeArt;
pub mod GenerativeArtFactory;

pub mod interfaces {
    pub mod IGenerativeArt;
    pub mod IGenerativeArtFactory;
}

pub mod mock_contracts {
    pub mod MockAccount;
    pub mod Receiver;
}

#[cfg(test)]
mod tests {
    mod GenerativeArtTest;
    mod GenerativeArtFactoryTest;
}
