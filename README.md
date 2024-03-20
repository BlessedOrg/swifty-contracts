# NFT Lottery Ticket System

This system allows a seller to create and manage an NFT-based lottery system using two main contracts: `Deposit` and `NFTLotteryTicket`. Participants can deposit funds to be eligible for the lottery, and winners are selected randomly via Gelato's VRF service to receive unique NFT tickets.

## Contracts

- `Deposit.sol`: Handles participants' deposits and eligibility.
- `NFTLotteryTicket.sol`: Manages the lottery state, selects winners, and mints NFT tickets.

## How to Deploy (Applicable to sellers)

1. **Deploy the Deposit Contract:**

   - Compile `Deposit.sol` using Forge, Remix, or Hardhat.
   - Deploy the contract to your chosen network. During deployment, specify the seller's address as a constructor parameter.

2. **Deploy the NFTLotteryTicket Contract:**

   - Compile `NFTLotteryTicket.sol` similarly.
   - Deploy the contract, providing the URI for the NFT metadata as a constructor parameter.

3. **Set Operator Address for Gelato VRF:**

   - Call `setOperatorAddress` on `NFTLotteryTicket` with the operator address provided by Gelato.

4. **Link the Two Contracts:**
   - Call `setDepositContract` on `NFTLotteryTicket` with the address of the deployed `Deposit` contract.
   - Call `setLotteryAddress` on `Deposit` with the address of the deployed `NFTLotteryTicket` contract.

## How to Use

### As the Seller

1. **Initialize the Lottery:**

   - Set the minimum deposit amount required for participants to be eligible using `setMinimumDepositAmount`.
   - Set the number of tickets/winners using `setNumberOfTickets`.

2. **Start the Lottery:**

   - Call `startLottery` to change the state to ACTIVE and automatically check for eligible participants.

3. **Selecting Winners:**

   - Manually initiate the winner selection process by calling `initiateSelectWinner`.
   - The contract will request randomness from Gelato's VRF, and winners will be selected one by one.
   - Monitor the `WinnerSelected` and `LotteryEnded` events.

4. **End the Lottery:**

   - Once all winners are selected, or when you decide to end the lottery, call `endLottery`.

5. **Withdraw Funds:**
   - After the lottery ends, call `sellerWithdraw` to collect the funds from losing participants.

### As a Participant

1. **Deposit Funds:**

   - Send funds to the `Deposit` contract while the lottery is NOT_STARTED. The amount must meet or exceed the minimum deposit amount.

2. **Check Eligibility:**

   - You can check if you're marked eligible after the lottery starts.

3. **After Lottery Ends:**
   - If you're a winner, mint your NFT ticket using `mintMyNFT`.
   - If not a winner, withdraw your deposited funds using `buyerWithdraw`.

## Testing and Security

- Thoroughly test all functionalities, especially around deposits, winner selection, and NFT minting.
- Consider security best practices and potentially get a smart contract audit.

## Conclusion

This NFT Lottery Ticket System offers a transparent and fair way to distribute unique NFTs to participants. The integration with Gelato VRF ensures randomness in winner selection, and the two-contract architecture separates concerns between handling funds and managing the lottery logic.
