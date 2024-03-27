# NFT Lottery Ticket System

This system enables sellers to create and manage an NFT-based ticketing system in a decentralized and transparent manner using Solidity smart contracts.

Participants can deposit funds (USDC or other ERC20) to qualify for a lottery, where winners are randomly selected via [Gelato's VRF](https://www.gelato.network/vrf) service. Second option to get your seats is participation in live auctions.

## Contracts

- `NFTLotteryTicket.sol`: Represents tickets as NFTs. Some tickets (depending on auction or lottery type) might be non-transferable (soulbound). Winning the lottery or an auction grants the ability to mint such token.
- `Lottery.sol`: Enables to participate in initial sale of small portion of tickets. Eligible buyers are selected randomly via VRF. 
- `LotteryV2.sol`: Allows potential buyers and sellers to roll a dice and generate a random number. Numbers close to the seller's position become eligible for minting.
- `AuctionV1.sol`: Customers bid the same price and if there's a higher demand for tickets, lucky bidders are selected via VRF.
- `AuctionV2.sol`: First `n` highest bids are eligible to mint tickets (n = number of available tickets)

## How to deploy & setup contracts (applicable to sellers)

1. **Deploy the NFTLotteryTicket Contract:**

   - Compile `NFTLotteryTicket.sol` similarly.
   - Deploy the contract, providing the URI for the NFT metadata as a constructor parameter.

2. **Deploy the Lottery, LotteryV1 and Auction contracts:**

   - Compile `Lottery.sol`, `LotteryV2.sol`, `AuctionV1.sol` and `AuctionV2.sol` using Forge, Remix, or Hardhat.
   - Deploy the contract to your chosen EVM compatible network. During deployment, specify the seller's address as a constructor parameter.


## How to Use

### As the Seller

1. **Initialize the Lottery or Auction:**

   - Set the minimum deposit amount required for participants to be eligible using `setMinimumDepositAmount`.
   - Set the number of tickets/winners using `setNumberOfTickets`.
   - Link NFT contract to the lottery or auction using `setNftContractAddr`.
   - Configure ERC20 payment token for deposits using `setUsdcContractAddr`.
   - Configure timestamp until when deposits are possible using `setFinishAt`.   

2. **Start the Lottery:**

   - Call `startLottery` to change the state to ACTIVE and automatically check for eligible participants.

3. **Selecting Winners:**

   - Manually initiate the winner selection process by calling `selectWinners`.
   - The contract will request randomness from Gelato's VRF, and winners will be selected one by one.
   - Monitor the `WinnerSelected` and `LotteryEnded` events.

4. **End the Lottery:**

   - Once all winners are selected, or when you decide to end the lottery, call `endLottery`.

5. **Withdraw Funds:**
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
- `NFTLotteryTicket.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0x1E1719C267084AfC679115b1C033eD7E2405757D
- `Lottery.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0xB115cDc398C313A65a94E22076c7a5CDcb89c0F8
- `LotteryV2.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0x002184f14b1d3e4C767d6158f55D41A375D39088
- `AuctionV1.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0x5796F72fAD7733F783A802e8AC8ef24E60c5fd2E
- `AuctionV2.sol`: https://opcelestia-raspberry.gelatoscout.com/address/0xBB1126594cB490540b28F6d2fFF220048fd07CA6

## Testnet
Connection details: 
https://raas.gelato.network/rollups/details/public/opcelestia-raspberry

Bridge: 
https://bridge.gelato.network/bridge/opcelestia-raspberry

## How to deploy to testnet? 
```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --constructor-args "https://example.com/" true \
   --private-key "{YOUR_PRIVATE_KEY}" \
   src/NFTLotteryTicket.sol:NFTLotteryTicket 
```

```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --constructor-args 0x727b6D0a1DD1cA8f3132B6Bc8E1Cfa0C04CAb806 \
   --private-key "{YOUR_PRIVATE_KEY}" \
   src/Lottery.sol:Lottery
```

```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
    --constructor-args 0x727b6D0a1DD1cA8f3132B6Bc8E1Cfa0C04CAb806 \
   --private-key "{YOUR_PRIVATE_KEY}" \
    src/LotteryV2.sol:LotteryV2
```

```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --constructor-args 0x727b6D0a1DD1cA8f3132B6Bc8E1Cfa0C04CAb806 \
   --private-key "{YOUR_PRIVATE_KEY}" \
   src/AuctionV1.sol:AuctionV1
```

```
forge create --rpc-url https://rpc.opcelestia-raspberry.gelato.digital \
   --constructor-args 0x727b6D0a1DD1cA8f3132B6Bc8E1Cfa0C04CAb806 \
   --private-key "{YOUR_PRIVATE_KEY}" \
   src/AuctionV2.sol:AuctionV2
```

## How to verify contract code at testnet?
```
forge verify-contract {CONTRACT_ADDR} NFTLotteryTicket --verifier blockscout --verifier-url https://opcelestia-raspberry.gelatoscout.com/api --chain 123420111 --constructor-args $(cast abi-encode "constructor(string,bool)" "https://example.com/" true)
```

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
