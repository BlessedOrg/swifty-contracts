# NFT Lottery Ticket System
This system enables sellers to create and manage an NFT-based ticketing system in a decentralized and transparent manner using Solidity Smart Contracts.

Participants can deposit funds (USDC or other ERC20) to qualify for a lottery, where winners are randomly selected via [Gelato's VRF](https://www.gelato.network/vrf) service. Second option to get your seats is participation in live auctions.

# Demo Links
We had a limitation by loom therefore we had to split to multiple videos:

**Part I**  

https://www.loom.com/share/1bbe0842fdd44baeba9c8354d2d5e2b2

**Part 2**  

https://www.loom.com/share/a0f5f33b34b04d639a921ad31aa01d1a

**Part 3**  

https://www.loom.com/share/2a15180337ea4aad91f7693936ed173c

# Contracts
- `NFTLotteryTicket.sol`: Represents tickets as NFTs. Some tickets (depending on auction or lottery type) might be non-transferable (soulbound). Winning the lottery or an auction grants the ability to mint such token.
- `LotteryV1Base.sol`: Enables to participate in initial sale of small portion of tickets. Eligible buyers are selected randomly via VRF. 
- `LotteryV2Base.sol`: Allows potential buyers and sellers to roll a dice and generate a random number. Numbers close to the seller's position become eligible for minting.
- `AuctionV1Base.sol`: Customers bid the same price and if there's a higher demand for tickets, lucky bidders are selected via VRF.
- `AuctionV2Base.sol`: First `n` highest bids are eligible to mint tickets (n = number of available tickets)

# How to deploy & setup Smart Contracts
1. **Deploy the NFTLotteryTicket, LotteryV1Base, LotteryV2Base, AuctionV1Base and AuctionV2Base Contracts:**

   - Compile the contracts and deploy them using Foundry (desribed below), Remix, or Hardhat to your chosen EVM compatible network (we use Base).

2. **Use those Contracts as a base Contracts to create a Sale in BlessedFactory (setBaseContracts function)**
 
   - To see the whole process of configuring Sale, check the endpoint in Blessed app: https://github.com/BlessedOrg/swifty-app/blob/main/src/app/api/events/%5Bid%5D/deployContracts/route.ts

# How to Use

## LotteryV1

### As a Seller

💡 fill this after audit

### As a Participant

💡 fill this after audit

## LotteryV2

### As a Seller

💡 fill this after audit

### As a Participant

💡 fill this after audit

## AuctionV1

### As a Seller

💡 fill this after audit

### As a Participant

💡 fill this after audit

## AuctionV2

### As a Seller

💡 fill this after audit

### As a Participant

💡 fill this after audit

# How to deploy and verify Smart Contracts? 
You can use foundry for that, simply run the command (remember to replace variables - prefixed with $):
```
forge create src/LotteryV1Base.sol:LotteryV1Base \
    --rpc-url  $RPC_URL \
    --private-key "$WALLET_PIRVATE_KEY" \
    
    --verify \
    --chain-id $CHAIN_ID \
    --etherscan-api-key $ETHERSCAN_API_KEY \
```

# I can't deploy and verify Contract at the same time
```
For some networks, it may be the case that verifing directly from the Foundry will not work. If this is your case, see the next point for manual verification.
```

# How to verify Contract manually?
When script is not working for some reason, the best option is to try use flattened code technique and go to explorer and verify Contract manually.

All you need to do is: 
- flatten Contract code using `forge flatten --output ./src/flatten/{ContractName}.flattened.sol ./src/{ContractName}.sol`. For example: `forge flatten --output ./src/flatten/BlessedFactory.flattened.sol ./src/BlessedFactory.sol`
- go to the explorer, type address, click Contract => Verify 
- select single file code mode 
- paste flattened Contract code 
- specify compiler version to 0.8.25
- specify evm version to `paris`
- if you fail to verify, go to `out` folder, find your `{ContractName}.json` file, and under the `rawMetada` object look for the keys `compiler` and `evmVersion`

# Run unit tests locally
**Currently our tests are outdated (due to changes requested by the CDC audit company)!**
```
cargo install --git https://github.com/foundry-rs/foundry --profile local --locked forge cast chisel anvil
```

```
forge test -vv
```

# Current testnet
Currently for testing we are using Base Sepolia.

Connection details:
https://docs.base.org/docs/network-information/

Bridge:
https://bridge.base.org/deposit

Here are the deployed versions of Base Contracts:
- `NFTLotteryTicket.sol`: https://sepolia.basescan.org/address/0x5f0AB9E7Ce90C552871f80c60eD5FdF353A5FF18
- `LotteryV1Base.sol`: https://sepolia.basescan.org/address/0x14E85848Eec0c5a2Fd4fE207be0E9835227D0F57
- `LotteryV2Base.sol`: https://sepolia.basescan.org/address/0x8Efd26340E13458557B7c6a9B4cD875e22e46C55
- `AuctionV1Base.sol`: https://sepolia.basescan.org/address/0x82058b148F6264b1c455990B2C823127a9B19456
- `AuctionV2Base.sol`: https://sepolia.basescan.org/address/0xFeC7681621A1bBFf09219B7B24c2356087d28E06

# Conclusion
This NFT Lottery Ticket System offers a transparent and fair way to distribute unique NFTs to participants. The integration with Gelato VRF ensures trusted randomness.

# Related further Links
Here we list all relevant other repos.

# App
We create a dedicated repo for the App to you understand the database structure and how to set it up.
https://github.com/BlessedOrg/swifty-app  

# UX
We create a dedicated UX repo as we also partipated in the UX challenge and we explained there in detail with screenshoots what challenges we had and what how we solved that UX wise.  
https://github.com/BlessedOrg/UX--UI  

# Gelato Bounty
For the Gelato Bounty we create also our own repo where we share our findings.
We needed to link it at the UX Challenge too, please consider that this was a constraint of handing in a submission to pick one and to be complete we listed it here as well as in the other signed in built where we soley focused on UX challenges.  
https://github.com/BlessedOrg/Gelato
