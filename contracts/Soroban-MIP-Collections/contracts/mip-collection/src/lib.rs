#![no_std]
use soroban_sdk::{contract, contractimpl};

#[contract]
pub struct Placeholder;

#[contractimpl]
impl Placeholder {
    pub fn version() -> u32 {
        1
    }
}
