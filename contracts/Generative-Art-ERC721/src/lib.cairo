pub mod GenerativeArt;

pub mod interfaces {
    pub mod IGenerativeArt;
}

pub mod mock_contracts {
    pub mod MockAccount;
    pub mod Receiver;
}

#[cfg(test)]
mod tests {
    mod GenerativeArtTest;
}
