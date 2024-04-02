// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import "forge-std/console.sol";
import { NFTLotteryTicket } from "../src/NFTLotteryTicket.sol";
import { LotteryV2 } from "../src/LotteryV2.sol";
import { Lottery } from "../src/Lottery.sol";
import { USDC } from "../src/USDC.sol";

contract MockedLotteryV2 is LotteryV2 {
    constructor(address _seller, address _operatorAddr) LotteryV2(_seller, _operatorAddr)  {
         // Child construction code goes here
    }

    // fake functions to control randomness
    function setSellerRandomNumber(uint256 _randomNumber) public {
        randomNumber = _randomNumber;
    }

    function setBuyerRandomNumber(address _buyerAddr, uint256 random) public {
        rolledNumbers[_buyerAddr] = random;
    }
}

contract LotteryV2Test is Test {
    MockedLotteryV2 public lottery;
    USDC public usdcToken;

    uint256 private sellerPrivateKey = 0xa11ce;
    uint256 private multisigWalletPrivateKey = 0xb334d;

    address seller;
    address operator;
    address multisigWallet;

    function setUp() public {
        // Generate addresses from private keys
        seller = vm.addr(sellerPrivateKey);
        operator = vm.addr(0x1234);
        multisigWallet = vm.addr(multisigWalletPrivateKey);
        vm.warp(1700819134); // mock time so Gelato round calculate works
        vm.startPrank(seller);
        // Deploy the Deposit contract with the seller address
        lottery = new MockedLotteryV2(seller, operator);

        // Deploy the USDC token contract
        usdcToken = new USDC("USDC", "USDC", 6, 1000000000000000000000000, 1000000000000000000000000);
        lottery.setUsdcContractAddr(address(usdcToken));
        lottery.setFinishAt(block.timestamp + 100000);

        // Set the multisig wallet address in the Deposit contract
        lottery.setMultisigWalletAddress(multisigWallet);
        vm.stopPrank();
    }

    function provideUsdc(address recipient, uint256 amount) public {
        vm.startPrank(seller);
        usdcToken.transfer(recipient, amount);
        vm.stopPrank();

        vm.startPrank(recipient);
        // approve lottery to actually spend usdc
        usdcToken.approve(address(lottery), amount);
        vm.stopPrank();
    }

    function test_DepositFunds() public {
        uint256 depositAmount = 10000;
        address user = address(3); // Example user address


        provideUsdc(user, depositAmount); // Provide 10000 usdc to the user

        vm.startPrank(user);
        lottery.deposit(depositAmount);
        assertEq(lottery.deposits(user), depositAmount, "Deposit amount should be recorded correctly");
        vm.stopPrank();
    }

    function test_DepositNotPossible() public {
        uint256 depositAmount = 10000;
        address user = address(3); // Example user address


        provideUsdc(user, depositAmount); // Provide 10000 usdc to the user

        vm.startPrank(seller);
        lottery.setFinishAt(0);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("Only seller can call this function");
        lottery.setFinishAt(1000);
        vm.expectRevert("Deposits are not possible anymore");
        lottery.deposit(depositAmount);
        vm.stopPrank();
    }

    function test_ChangeLotteryState() public {
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV2.LotteryState.ACTIVE);
        assertEq(
            uint256(lottery.lotteryState()), uint256(LotteryV2.LotteryState.ACTIVE), "Lottery state should be ACTIVE"
        );

        vm.prank(seller);
        lottery.changeLotteryState(LotteryV2.LotteryState.ENDED);
        assertEq(uint256(lottery.lotteryState()), uint256(LotteryV2.LotteryState.ENDED), "Lottery state should be ENDED");
    }

    function test_NonWinnerWithdrawal() public {
        address nonWinner = address(4); // Example non-winner address
        uint256 depositAmount = 10000;

        provideUsdc(nonWinner, depositAmount); 
        // Non-winner deposits funds
        vm.startPrank(nonWinner);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        // End the lottery
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV2.LotteryState.ENDED);

        // Non-winner attempts to withdraw
        vm.startPrank(nonWinner);
        lottery.buyerWithdraw();
        assertEq(lottery.deposits(nonWinner), 0, "Non-winner should be able to withdraw their deposit");
        vm.stopPrank();
    }

    function test_MultipleUsersDeposit() public {
        address user1 = address(3);
        address user2 = address(4);
        uint256 user1Deposit = 5000;
        uint256 user2Deposit = 10000;

        provideUsdc(user1, user1Deposit);
        provideUsdc(user2, user2Deposit);

        vm.startPrank(user1);
        lottery.deposit(user1Deposit);
        vm.stopPrank();

        vm.startPrank(user2);
        lottery.deposit(user2Deposit);
        vm.stopPrank();

        assertEq(lottery.deposits(user1), user1Deposit, "User1 deposit should be recorded correctly");
        assertEq(lottery.deposits(user2), user2Deposit, "User2 deposit should be recorded correctly");
    }

    function test_SellerWithdrawalWithProtocolTax() public {
        address winner = address(3);
        uint256 winnerDeposit = 10000;
        uint256 protocolTax = (winnerDeposit * 5) / 100; // 5% tax
        uint256 amountToSeller = usdcToken.balanceOf(seller) - protocolTax;

        // Setup: Winner deposits and is set as a winner
        provideUsdc(winner, winnerDeposit);
        
        vm.startPrank(winner);
        lottery.deposit(winnerDeposit);
        vm.stopPrank();
        vm.prank(seller);
        lottery.setWinner(winner);

        // End the lottery and process the withdrawal
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV2.LotteryState.ENDED);
        vm.prank(seller);
        lottery.sellerWithdraw();

        // Check balances
        assertEq(usdcToken.balanceOf(multisigWallet), protocolTax, "Multisig should receive the correct tax amount");
        assertEq(usdcToken.balanceOf(seller), amountToSeller, "Seller should receive the correct amount after tax");
    }

    function test_WinnerCannotWithdraw() public {
        address winner = address(3);
        uint256 depositAmount = 10000;

        provideUsdc(winner, depositAmount);

        vm.startPrank(winner);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        // Set as winner and try to withdraw
        vm.prank(seller);
        lottery.setWinner(winner);
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV2.LotteryState.ENDED);
        vm.startPrank(winner);
        vm.expectRevert("Winners cannot withdraw");
        lottery.buyerWithdraw();
        vm.stopPrank();
    }

    function test_CompleteLotteryCycle() public {
        // Setup: Multiple participants deposit funds
        address[] memory participants = new address[](4);
        participants[0] = address(3);
        participants[1] = address(4);
        participants[2] = address(5);
        participants[3] = address(6);
        uint256 depositAmount = 10000;

        for (uint256 i = 0; i < participants.length; i++) {
            provideUsdc(participants[i], depositAmount);

            vm.startPrank(participants[i]);
            lottery.deposit(depositAmount);
            vm.stopPrank();
        }

        // End the lottery
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV2.LotteryState.ENDED);

        // Mark some participants as winners (e.g., first two)
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(seller);
            lottery.setWinner(participants[i]);
        }

        // Ensure winners cannot withdraw
        for (uint256 i = 0; i < 2; i++) {
            vm.startPrank(participants[i]);
            vm.expectRevert("Winners cannot withdraw");
            lottery.buyerWithdraw();
            vm.stopPrank();
        }

        // Ensure losers can withdraw
        for (uint256 i = 2; i < participants.length; i++) {
            uint256 initialBalance = usdcToken.balanceOf(participants[i]);
            vm.startPrank(participants[i]);
            lottery.buyerWithdraw();
            assertEq(usdcToken.balanceOf(participants[i]), initialBalance + depositAmount, "Loser should withdraw their deposit");
            vm.stopPrank();
        }

        // Test seller withdrawal and tax distribution
        uint256 totalPrizePool = depositAmount * 2; // Assuming 2 winners
        uint256 protocolTax = (totalPrizePool * 5) / 100;
        uint256 amountToSeller = totalPrizePool - protocolTax;
        uint256 initialSellerBalance = usdcToken.balanceOf(seller);
        uint256 initialMultisigBalance = usdcToken.balanceOf(multisigWallet);

        vm.prank(seller);
        lottery.sellerWithdraw();

        assertEq(
            usdcToken.balanceOf(seller), initialSellerBalance + amountToSeller, "Seller should receive correct amount after tax"
        );
        assertEq(usdcToken.balanceOf(multisigWallet), initialMultisigBalance + protocolTax, "Multisig should receive the tax amount");
    }

    function test_EdgeCaseDeposits() public {
        address user = address(3);
        uint256 depositAmount = 10000;

        // Setup: Provide Ether to the user
        provideUsdc(user, depositAmount);

        // Case 1: Deposit right before the lottery starts
        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.stopPrank();
        assertEq(lottery.deposits(user), depositAmount, "Deposit before start should be recorded");

        // Start the lottery
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV2.LotteryState.ACTIVE);

        // End the lottery to allow withdrawal
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV2.LotteryState.ENDED);

        // Case 2: Attempt to withdraw multiple times
        vm.startPrank(user);
        lottery.buyerWithdraw();
        assertEq(lottery.deposits(user), 0, "User should have withdrawn their deposit");
        vm.expectRevert("No funds to withdraw");
        lottery.buyerWithdraw(); // Attempt to withdraw again
        vm.stopPrank();

        // Case 3: Deposit right after the lottery ends
        provideUsdc(user, depositAmount);

        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.stopPrank();
        assertEq(lottery.deposits(user), depositAmount, "Deposit after end should be recorded");
    }

    function test_nftMintHappyPath() public {
        address user = address(3);
        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);
        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(lottery));
        lottery.setNftContractAddr(address(nftLotteryTicket));
        lottery.setNumberOfTickets(10);
        lottery.setMinimumDepositAmount(depositAmount);
        lottery.startLottery();
        lottery.setRandomNumber();

        // steer the random number to 5
        lottery.setBuyerRandomNumber(user, 5);
        lottery.setSellerRandomNumber(5);

        assertEq(lottery.randomNumber(), 5, "mocked random number should be 5");
        assertEq(lottery.rolledNumbers(user), 5, "mocked random number should be 5");
        lottery.endLottery();
        vm.stopPrank();
        
        vm.startPrank(user);
        assertEq(lottery.isClaimable(user), true, "user number should be claimable");
        lottery.claimNumber(user);
        assertEq(lottery.isWinner(user), true, "user should be winner");
        lottery.mintMyNFT();
        assertEq(nftLotteryTicket.balanceOf(user, 1), 1, "Joe must own NFT#1");
        vm.stopPrank();
    } 

    function test_noRandomMatch() public {
        address user = address(3);
        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);
        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(lottery));
        lottery.setNftContractAddr(address(nftLotteryTicket));
        lottery.setNumberOfTickets(10);
        lottery.setMinimumDepositAmount(depositAmount);
        lottery.startLottery();
        lottery.setRandomNumber();

        // steer the random number to 5
        lottery.setBuyerRandomNumber(user, 51);
        lottery.setSellerRandomNumber(5);

        assertEq(lottery.randomNumber(), 5, "mocked random number should be 5");
        assertEq(lottery.rolledNumbers(user), 51, "mocked random number should be 51");
        lottery.endLottery();
        vm.stopPrank();
        
        vm.startPrank(user);
        assertEq(lottery.isClaimable(user), false, "user number should not be claimable");
        vm.expectRevert("Participant is not claimable");
        lottery.claimNumber(user);
        assertEq(lottery.isWinner(user), false, "user should not be winner");
        vm.expectRevert("Caller is not a winner");
        lottery.mintMyNFT();
        vm.stopPrank();
    }    

    function test_rollDice() public {
        address user = address(3);
        uint256 depositAmount = 10000;
        uint256 rollPrice = 1000;

        provideUsdc(user, depositAmount);

        vm.startPrank(seller);
        lottery.setRollPrice(rollPrice);
        vm.stopPrank();

        vm.startPrank(user);
        lottery.deposit(depositAmount);
        lottery.roll();
        uint256 firstRoll = lottery.rolledNumbers(user);
        assertEq(lottery.deposits(user), depositAmount - rollPrice, "user should have less deposit");
        
        // fake different entropy
        vm.prevrandao(bytes32(uint256(42)));
        lottery.roll();
        uint256 secondRoll = lottery.rolledNumbers(user);
        assertEq(lottery.deposits(user), depositAmount - rollPrice * 2, "user should have less deposit");
        assertEq(firstRoll == secondRoll, false, "user should have different random");
        vm.stopPrank();
    }

    function test_rollDicePriceFail() public {
        address user = address(3);
        uint256 depositAmount = 10000;
        uint256 rollPrice = 1000;

        provideUsdc(user, depositAmount);

        vm.startPrank(seller);
        lottery.setRollPrice(rollPrice);
        lottery.setMinimumDepositAmount(depositAmount);
        vm.stopPrank();

        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.expectRevert("Insufficient funds");
        lottery.roll();
        vm.stopPrank();
    }

    function test_rollDiceNoPrice() public {
        address user = address(3);
        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);

        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.expectRevert("No roll price set");
        lottery.roll();
        vm.stopPrank();
    }

    function test_rollNotPossible() public {
        address user = address(3);
        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);

        vm.startPrank(seller);
        lottery.setRollPrice(100);
        lottery.setMinimumDepositAmount(depositAmount);
        vm.stopPrank();

        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        lottery.setFinishAt(0);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("Rolling is not possible anymore");
        lottery.roll();
        vm.stopPrank();
    }

    function test_randomNumberTolerance() public {
        address user = address(3);
        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);
        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(lottery));
        lottery.setNftContractAddr(address(nftLotteryTicket));
        lottery.setNumberOfTickets(10);
        lottery.setMinimumDepositAmount(depositAmount);
        lottery.setRollTolerance(5);
        lottery.startLottery();
        lottery.setRandomNumber();

        lottery.setBuyerRandomNumber(user, 55);
        lottery.setSellerRandomNumber(50);

        lottery.endLottery();
        vm.stopPrank();
        
        vm.startPrank(user);
        assertEq(lottery.isClaimable(user), true, "user number should be claimable");
        lottery.claimNumber(user);
        assertEq(lottery.isWinner(user), true, "user should be winner");
        lottery.mintMyNFT();
        assertEq(nftLotteryTicket.balanceOf(user, 1), 1, "Joe must own NFT#1");
        vm.stopPrank();
    }     

    function test_randomNumberFailedTolerance() public {
      address user = address(3);
      uint256 depositAmount = 10000;

      provideUsdc(user, depositAmount);
      vm.startPrank(user);
      lottery.deposit(depositAmount);
      vm.stopPrank();

      vm.startPrank(seller);
      NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
      nftLotteryTicket.setDepositContractAddr(address(lottery));
      lottery.setNftContractAddr(address(nftLotteryTicket));
      lottery.setNumberOfTickets(10);
      lottery.setMinimumDepositAmount(depositAmount);
      lottery.setRollTolerance(6);
      lottery.startLottery();
      lottery.setRandomNumber();

      lottery.setBuyerRandomNumber(user, 57);
      lottery.setSellerRandomNumber(50);

      lottery.endLottery();
      vm.stopPrank();
      
      vm.startPrank(user);
      assertEq(lottery.isClaimable(user), false, "user number should not be claimable");
      vm.stopPrank();
    }     

    function test_transferDeposit() public {
      address john = address(3);
      address max = address(3);
      uint256 depositAmount = 10000;

      vm.startPrank(seller);
      usdcToken.transfer(john, depositAmount);
      usdcToken.transfer(max, depositAmount);
      Lottery lotteryV1 = new Lottery(seller, address(66));
      lotteryV1.setUsdcContractAddr(address(usdcToken));
      lotteryV1.setFinishAt(vm.unixTime() + 100000);
      vm.stopPrank();

      vm.startPrank(max);
      usdcToken.approve(address(lotteryV1), depositAmount);
      lotteryV1.deposit(depositAmount);
      vm.stopPrank();

      vm.startPrank(john);
      usdcToken.approve(address(lotteryV1), depositAmount);
      lotteryV1.deposit(depositAmount);
      vm.stopPrank();

      vm.startPrank(seller);
      NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
      nftLotteryTicket.setDepositContractAddr(address(lotteryV1));
      lotteryV1.setNftContractAddr(address(nftLotteryTicket));
      lotteryV1.setNumberOfTickets(1);
      lotteryV1.setMinimumDepositAmount(depositAmount);
      lotteryV1.startLottery();
      lotteryV1.selectWinners();
      lotteryV1.endLottery();
      lottery.setLotteryV1Addr(address(lotteryV1));
      

      assertEq(lottery.getParticipants().length == 0, true, "no deposits at second lottery");
      lotteryV1.transferNonWinnerDeposits(address(lottery));
      assertEq(lottery.getParticipants().length == 1, true, "transffered deposit at second lottery");
      vm.stopPrank();
    }
}
