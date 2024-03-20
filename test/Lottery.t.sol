// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import "forge-std/console.sol";
import { NFTLotteryTicket } from "../src/NFTLotteryTicket.sol";
import { Lottery } from "../src/Lottery.sol";
import { USDC } from "../src/USDC.sol";

contract LotteryTest is Test {
    Lottery public lottery;
    USDC public usdcToken;

    uint256 private sellerPrivateKey = 0xa11ce;
    uint256 private multisigWalletPrivateKey = 0xb334d;

    address seller;
    address multisigWallet;

    function setUp() public {
        // Generate addresses from private keys
        seller = vm.addr(sellerPrivateKey);
        multisigWallet = vm.addr(multisigWalletPrivateKey);

        vm.startPrank(seller);
        // Deploy the Deposit contract with the seller address
        lottery = new Lottery(seller);

        // Deploy the USDC token contract
        usdcToken = new USDC("USDC", "USDC", 6, 1000000000000000000000000, 1000000000000000000000000);
        lottery.setUsdcContractAddr(address(usdcToken));

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

    function test_ChangeLotteryState() public {
        vm.prank(seller);
        lottery.changeLotteryState(Lottery.LotteryState.ACTIVE);
        assertEq(
            uint256(lottery.lotteryState()), uint256(Lottery.LotteryState.ACTIVE), "Lottery state should be ACTIVE"
        );

        vm.prank(seller);
        lottery.changeLotteryState(Lottery.LotteryState.ENDED);
        assertEq(uint256(lottery.lotteryState()), uint256(Lottery.LotteryState.ENDED), "Lottery state should be ENDED");
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
        lottery.changeLotteryState(Lottery.LotteryState.ENDED);

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
        lottery.changeLotteryState(Lottery.LotteryState.ENDED);
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
        lottery.changeLotteryState(Lottery.LotteryState.ENDED);
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
        lottery.changeLotteryState(Lottery.LotteryState.ENDED);

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
        lottery.changeLotteryState(Lottery.LotteryState.ACTIVE);

        // End the lottery to allow withdrawal
        vm.prank(seller);
        lottery.changeLotteryState(Lottery.LotteryState.ENDED);

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
        lottery.selectWinners();
        lottery.endLottery();
        vm.stopPrank();
        assertEq(lottery.isWinner(user), true, "user should be winner");
        
        vm.startPrank(user);
        lottery.mintMyNFT();
        assertEq(nftLotteryTicket.balanceOf(user, 1), 1, "Joe must own NFT#1");
        vm.stopPrank();
    }

    function test_enoughSupply() public {
        address user = address(3);
        address joe = address(4);

        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);
        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        provideUsdc(joe, depositAmount);
        vm.startPrank(joe); 
        lottery.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(lottery));
        lottery.setNftContractAddr(address(nftLotteryTicket));
        lottery.setNumberOfTickets(2);
        lottery.setMinimumDepositAmount(depositAmount);
        lottery.startLottery();
        assertEq(lottery.isParticipantEligible(user), true, "user should be eligable to win");
        assertEq(lottery.isParticipantEligible(joe), true, "joe should be eligable to win");

        lottery.selectWinners();
        lottery.endLottery();
        vm.stopPrank();
        assertEq(lottery.isWinner(user), true, "user should be winner");
        assertEq(lottery.isWinner(joe), true, "user should be winner");
        vm.startPrank(user);
        lottery.mintMyNFT();
        assertEq(nftLotteryTicket.balanceOf(user, 1), 1, "Joe must own NFT#1");
        vm.stopPrank();
    }    

    function test_moreDemand() public {
        address user = address(3);
        address joe = address(4);
        address anna = address(5);

        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);
        vm.startPrank(user);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        provideUsdc(joe, depositAmount);
        vm.startPrank(joe);
        lottery.deposit(depositAmount);
        vm.stopPrank();


        provideUsdc(anna, depositAmount);
        vm.startPrank(anna);
        lottery.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(lottery));
        lottery.setNftContractAddr(address(nftLotteryTicket));
        lottery.setNumberOfTickets(1);
        lottery.setMinimumDepositAmount(depositAmount);
        lottery.startLottery();
        assertEq(lottery.isParticipantEligible(user), true, "user should be eligable to win");
        assertEq(lottery.isParticipantEligible(joe), true, "joe should be eligable to win");

        lottery.selectWinners();
        lottery.endLottery();
        vm.stopPrank();
        assertEq(lottery.getWinners().length, 1, "just one winner should be selected");
        assertEq(lottery.isWinner(lottery.getWinners()[0]), true, "user should be winner");
    }    
}
