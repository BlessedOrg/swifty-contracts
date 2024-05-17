# NFT Lottery Ticket System

This system enables sellers to create and manage an NFT-based ticketing system in a decentralized and transparent manner using Solidity smart contracts.

Participants can deposit funds (USDC or other ERC20) to qualify for a lottery, where winners are randomly selected via [Gelato's VRF](https://www.gelato.network/vrf) service. Second option to get your seats is participation in live auctions.

## Contracts

- `NFTLotteryTicket.sol`: Represents tickets as NFTs. Some tickets (depending on auction or lottery type) might be non-transferable (soulbound). Winning the lottery or an auction grants the ability to mint such token.
- `LotteryV1Base.sol`: Enables to participate in initial sale of small portion of tickets. Eligible buyers are selected randomly via VRF. 
- `LotteryV2Base.sol`: Allows potential buyers and sellers to roll a dice and generate a random number. Numbers close to the seller's position become eligible for minting.
- `AuctionV1Base.sol`: Customers bid the same price and if there's a higher demand for tickets, lucky bidders are selected via VRF.
- `AuctionV2Base.sol`: First `n` highest bids are eligible to mint tickets (n = number of available tickets)

## How to deploy & setup contracts (applicable to sellers)

1. **Deploy the NFTLotteryTicket Contract:**

   - Compile `NFTLotteryTicket.sol` similarly.
   - Deploy the contract, providing the URI for the NFT metadata as a constructor parameter.

2. **Deploy the Lottery, LotteryV1 and Auction contracts:**

   - Compile `LotteryV1Base.sol`, `LotteryV2Base.sol`, `AuctionV1Base.sol` and `AuctionV2Base.sol` using Forge, Remix, or Hardhat.
   - Deploy the contract to your chosen EVM compatible network. During deployment, specify the seller's address as a constructor parameter.

3. **Use those Contracts to create BlessedFactory (setBaseContracts function)**

   - To see the whole process of configuring Sale, check the endpoint in Blessed app: https://github.com/BlessedOrg/swifty-app/blob/main/src/app/api/events/%5Bid%5D/deployContracts/route.ts 

## How to Use

### As the Seller

1. **Start the Lottery:**

   - Call `startLottery` to change the state to ACTIVE and automatically check for eligible participants.

2. **Selecting Winners:**

   - Manually initiate the winner selection process by calling `selectWinners`.
   - The contract will request randomness from Gelato's VRF, and winners will be selected one by one.
   - Monitor the `WinnerSelected` and `LotteryEnded` events.

3. **End the Lottery:**

   - Once all winners are selected, or when you decide to end the lottery, call `endLottery`.

4. **Withdraw Funds:**

   - After the lottery ends, call `sellerWithdraw` to collect the funds from losing participants.

### As a Participant

1. **Deposit Funds:**

   - Send funds to the contract while the lottery is NOT_STARTED using `deposit` function. Beforehand adding allowance approval for our contracts would be required. The amount must meet or exceed the minimum deposit amount.

2. **Check Eligibility:**

   - You can check if you're marked eligible after the lottery starts.

3. **After Lottery Ends:**
   - If you're a winner, mint your NFT ticket using `mintMyNFT`.
   - If not a winner, withdraw your deposited funds using `buyerWithdraw`.

## Contracts deployed to OP Celestia Raspberry
- `NFTLotteryTicket.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0xA69bA2a280287405907f70c637D8e6f1B278E613
- `LotteryV1Base.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0xC883d0b60EaF2646483cEafC0c50Ea755C7f794C
- `LotteryV2Base.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0xAF3c36Cb30b88899873E76bFd5E906E0d69d1F53
- `AuctionV1Base.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0xbb5EFc7c05867A010bF6Fa3Ed34230D40CF85941
- `AuctionV2Base.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0xc0C18852552DF4A66FcE60bC444b23Eb5B4FCF59

## Testnet
Connection details: 
https://raas.gelato.network/rollups/details/public/opcelestia-raspberry

Bridge: 
https://bridge.gelato.network/bridge/opcelestia-raspberry

## How to deploy to testnet? 
```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --private-key "{YOUR_PRIVATE_KEY}" \
   src/NFTLotteryTicket.sol:NFTLotteryTicket 
```

```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --private-key "{YOUR_PRIVATE_KEY}" \
   src/LotteryV1Base.sol:LotteryV1Base
```

```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --private-key "{YOUR_PRIVATE_KEY}" \
    src/LotteryV2Base.sol:LotteryV2Base
```

```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --private-key "{YOUR_PRIVATE_KEY}" \
   src/AuctionV1Base.sol:AuctionV1Base
```

```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --private-key "{YOUR_PRIVATE_KEY}" \
   src/AuctionV2Base.sol:AuctionV2Base
```

## How to verify contract code at testnet? (not working for OP Celestia Raspberry)
```
forge verify-contract {CONTRACT_ADDR} NFTLotteryTicket --verifier blockscout --verifier-url https://opcelestia-raspberry.gelatoscout.com/api --chain 123420111 --constructor-args $(cast abi-encode "constructor(string,bool)" "https://example.com/" true)
```
## How to verify if `forge verify-contract` doesn't work?
When script is not working for some reason, the best option is to try use flattened code technique.

All you need to do is: 
- flatten contract code using `forge flatten --output ./src/{ContractName}.flattened.sol ./src/{ContractName}.sol`
- go to the explorer, type address, click Contract => Verify 
- select single file code mode 
- paste flattened contract code 
- specify compiler version to 0.8.25
- specify evm version to `paris`
- if you fail to verify, go to `out` folder, find your `{ContractName}.json` file, and under the `rawMetada` object look for the keys `compiler` and `evmVersion` 


## Run unit tests locally
```
cargo install --git https://github.com/foundry-rs/foundry --profile local --locked forge cast chisel anvil
```

```
forge test -vv
```

## Testing and Security

- Thoroughly test all functionalities, especially around deposits, winner selection, and NFT minting.
- Consider security best practices and potentially get a smart contract audit.

## Conclusion

This NFT Lottery Ticket System offers a transparent and fair way to distribute unique NFTs to participants. The integration with Gelato VRF ensures trusted randomness.
