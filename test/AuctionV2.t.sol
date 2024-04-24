// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import "forge-std/console.sol";
import { NFTLotteryTicket } from "../src/NFTLotteryTicket.sol";
import { AuctionV2 } from "../src/AuctionV2.sol";
import { USDC } from "../src/USDC.sol";

import { NFTTicketBase } from "../src/NFTTicketBase.sol";
import { BlessedFactory } from "../src/BlessedFactory.sol";
import { LotteryBase } from "../src/LotteryBase.sol";
import { LotteryV2Base } from "../src/LotteryV2Base.sol";
import { AuctionV1Base } from "../src/AuctionV1Base.sol";
import { AuctionV2Base } from "../src/AuctionV2Base.sol";

contract AuctionV2Test is Test {
    AuctionV2Base public auction;
    BlessedFactory public blessedFactory;
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
        NFTTicketBase nftLotteryTicket = new NFTTicketBase();
        LotteryBase lotteryBase = new LotteryBase();
        LotteryV2Base lotteryV2Base = new LotteryV2Base();
        AuctionV1Base auctionV1Base = new AuctionV1Base();
        AuctionV2Base auctionV2Base = new AuctionV2Base();
        blessedFactory = new BlessedFactory();
        blessedFactory.setBaseContracts(
            address(nftLotteryTicket), 
            address(lotteryBase),
            address(lotteryV2Base),
            address(auctionV1Base),
            address(auctionV2Base)
        );

        blessedFactory.createSale(seller, seller, seller, "http://tokenuri.com/");
        address auctionV2baseAddr = blessedFactory.sales(0, 3);

        auction = AuctionV2Base(auctionV2baseAddr);

        // Deploy the USDC token contract
        usdcToken = new USDC("USDC", "USDC", 6, 1000000000000000000000000, 1000000000000000000000000);
        auction.setUsdcContractAddr(address(usdcToken));
        auction.setFinishAt(vm.unixTime() + 100000);

        // Set the multisig wallet address in the Deposit contract
        auction.setMultisigWalletAddress(multisigWallet);
        vm.stopPrank();
    }

    function provideUsdc(address recipient, uint256 amount) public {
        vm.startPrank(seller);
        usdcToken.transfer(recipient, amount);
        vm.stopPrank();

        vm.startPrank(recipient);
        // approve lottery to actually spend usdc
        usdcToken.approve(address(auction), amount);
        vm.stopPrank();
    }

    function test_DepositFunds() public {
        uint256 depositAmount = 10000;
        address user = address(3); // Example user address


        provideUsdc(user, depositAmount); // Provide 10000 usdc to the user

        vm.startPrank(user);
        auction.deposit(depositAmount);
        assertEq(auction.getDepositedAmount(user), depositAmount, "Deposit amount should be recorded correctly");
        vm.stopPrank();
    }

    function test_DepositTimeConstraint() public {
        uint256 depositAmount = 10000;
        address user = address(3); // Example user address


        provideUsdc(user, depositAmount); // Provide 10000 usdc to the user

        vm.startPrank(user);
        auction.deposit(100);
        assertEq(auction.getDepositedAmount(user), 100, "Deposit amount should be recorded correctly");
        vm.stopPrank();

        vm.startPrank(seller);
        auction.setFinishAt(0);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("Deposits are not possible anymore");
        auction.deposit(100);
        vm.stopPrank();

    }    

    function test_ChangeLotteryState() public {
        vm.prank(seller);
        auction.changeLotteryState(AuctionV2Base.LotteryState.ACTIVE);
        assertEq(
            uint256(auction.lotteryState()), uint256(AuctionV2Base.LotteryState.ACTIVE), "Lottery state should be ACTIVE"
        );

        vm.prank(seller);
        auction.changeLotteryState(AuctionV2Base.LotteryState.ENDED);
        assertEq(uint256(auction.lotteryState()), uint256(AuctionV2Base.LotteryState.ENDED), "Lottery state should be ENDED");
    }

    function test_NonWinnerWithdrawal() public {
        address nonWinner = address(4); // Example non-winner address
        uint256 depositAmount = 10000;

        provideUsdc(nonWinner, depositAmount); 
        // Non-winner deposits funds
        vm.startPrank(nonWinner);
        auction.deposit(depositAmount);
        vm.stopPrank();

        // End the lottery
        vm.prank(seller);
        auction.changeLotteryState(AuctionV2Base.LotteryState.ENDED);

        // Non-winner attempts to withdraw
        vm.startPrank(nonWinner);
        auction.buyerWithdraw();
        assertEq(auction.getDepositedAmount(nonWinner), 0, "Non-winner should be able to withdraw their deposit");
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
        auction.deposit(user1Deposit);
        vm.stopPrank();

        vm.startPrank(user2);
        auction.deposit(user2Deposit);
        vm.stopPrank();

        assertEq(auction.getDepositedAmount(user1), user1Deposit, "User1 deposit should be recorded correctly");
        assertEq(auction.getDepositedAmount(user2), user2Deposit, "User2 deposit should be recorded correctly");
    }

    function test_SellerWithdrawalWithProtocolTax() public {
        address winner = address(3);
        uint256 winnerDeposit = 10000;
        uint256 protocolTax = (winnerDeposit * 5) / 100; // 5% tax
        uint256 amountToSeller = usdcToken.balanceOf(seller) - protocolTax;

        // Setup: Winner deposits and is set as a winner
        provideUsdc(winner, winnerDeposit);
        
        vm.startPrank(winner);
        auction.deposit(winnerDeposit);
        vm.stopPrank();
        vm.prank(seller);
        auction.setWinner(winner);

        // End the lottery and process the withdrawal
        vm.prank(seller);
        auction.changeLotteryState(AuctionV2Base.LotteryState.ENDED);
        vm.prank(seller);
        auction.sellerWithdraw();

        // Check balances
        assertEq(usdcToken.balanceOf(multisigWallet), protocolTax, "Multisig should receive the correct tax amount");
        assertEq(usdcToken.balanceOf(seller), amountToSeller, "Seller should receive the correct amount after tax");
    }

    function test_WinnerCannotWithdraw() public {
        address winner = address(3);
        uint256 depositAmount = 10000;

        provideUsdc(winner, depositAmount);

        vm.startPrank(winner);
        auction.deposit(depositAmount);
        vm.stopPrank();

        // Set as winner and try to withdraw
        vm.prank(seller);
        auction.setWinner(winner);
        vm.prank(seller);
        auction.changeLotteryState(AuctionV2Base.LotteryState.ENDED);
        vm.startPrank(winner);
        vm.expectRevert("Winners cannot withdraw");
        auction.buyerWithdraw();
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
            auction.deposit(depositAmount);
            vm.stopPrank();
        }

        // End the lottery
        vm.prank(seller);
        auction.changeLotteryState(AuctionV2Base.LotteryState.ENDED);

        // Mark some participants as winners (e.g., first two)
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(seller);
            auction.setWinner(participants[i]);
        }

        // Ensure winners cannot withdraw
        for (uint256 i = 0; i < 2; i++) {
            vm.startPrank(participants[i]);
            vm.expectRevert("Winners cannot withdraw");
            auction.buyerWithdraw();
            vm.stopPrank();
        }

        // Ensure losers can withdraw
        for (uint256 i = 2; i < participants.length; i++) {
            uint256 initialBalance = usdcToken.balanceOf(participants[i]);
            vm.startPrank(participants[i]);
            auction.buyerWithdraw();
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
        auction.sellerWithdraw();

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
        auction.deposit(depositAmount);
        vm.stopPrank();
        assertEq(auction.getDepositedAmount(user), depositAmount, "Deposit before start should be recorded");

        // Start the lottery
        vm.prank(seller);
        auction.changeLotteryState(AuctionV2Base.LotteryState.ACTIVE);

        // End the lottery to allow withdrawal
        vm.prank(seller);
        auction.changeLotteryState(AuctionV2Base.LotteryState.ENDED);

        // Case 2: Attempt to withdraw multiple times
        vm.startPrank(user);
        auction.buyerWithdraw();
        assertEq(auction.getDepositedAmount(user), 0, "User should have withdrawn their deposit");
        vm.expectRevert("No funds to withdraw");
        auction.buyerWithdraw(); // Attempt to withdraw again
        vm.stopPrank();

        // Case 3: Deposit right after the lottery ends
        provideUsdc(user, depositAmount);

        vm.startPrank(user);
        auction.deposit(depositAmount);
        vm.stopPrank();
        assertEq(auction.getDepositedAmount(user), depositAmount, "Deposit after end should be recorded");
    }

    function test_nftMintHappyPath() public {
        address user = address(3);
        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);
        vm.startPrank(user);
        auction.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(auction));
        auction.setNftContractAddr(address(nftLotteryTicket));
        auction.setNumberOfTickets(10);
        auction.setInitPrice(depositAmount);
        auction.startLottery();
        auction.selectWinners();
        auction.endLottery();
        vm.stopPrank();
        assertEq(auction.isWinner(user), true, "user should be winner");
        
        vm.startPrank(user);
        auction.mintMyNFT();
        assertEq(nftLotteryTicket.balanceOf(user, 1), 1, "Joe must own NFT#1");
        vm.stopPrank();
    }

    function test_enoughSupply() public {
        address user = address(3);
        address joe = address(4);

        uint256 depositAmount = 10000;

        provideUsdc(user, depositAmount);
        vm.startPrank(user);
        auction.deposit(depositAmount);
        vm.stopPrank();

        provideUsdc(joe, depositAmount);
        vm.startPrank(joe); 
        auction.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(auction));
        auction.setNftContractAddr(address(nftLotteryTicket));
        auction.setNumberOfTickets(2);
        auction.setInitPrice(depositAmount);
        auction.startLottery();
        auction.selectWinners();
        auction.endLottery();
        vm.stopPrank();
        assertEq(auction.isWinner(user), true, "user should be winner");
        assertEq(auction.isWinner(joe), true, "user should be winner");
        vm.startPrank(user);
        auction.mintMyNFT();
        assertEq(nftLotteryTicket.balanceOf(user, 1), 1, "Joe must own NFT#1");
        vm.stopPrank();
    }    

    function test_moreDemand() public {
        address user = address(3);
        address joe = address(4);
        address anna = address(5);

        uint256 initialPrice = 10000;

        provideUsdc(anna, initialPrice + 10000);
        vm.startPrank(anna);
        auction.deposit(initialPrice- 100);
        vm.stopPrank();

        provideUsdc(user, initialPrice + 10000);
        vm.startPrank(user);
        auction.deposit(initialPrice);
        vm.stopPrank();

        provideUsdc(joe, initialPrice + 10000);
        vm.startPrank(joe);
        auction.deposit(initialPrice + 200);
        vm.stopPrank();


        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(auction));
        
        assertEq(auction.participants(0), anna, "anna should be first");
        assertEq(auction.participants(1), user, "user should be second");
        assertEq(auction.participants(2), joe, "joe should be last");

        auction.sortDepositsDesc();
        assertEq(auction.participants(0), joe, "joe should be first");
        assertEq(auction.participants(1), user, "user should be second");
        assertEq(auction.participants(2), anna, "anna should be last");
        
        auction.setNftContractAddr(address(nftLotteryTicket));
        auction.setNumberOfTickets(2);
        auction.setInitPrice(initialPrice);
        auction.startLottery();
        auction.selectWinners();
        assertEq(auction.getWinners().length, 2, "just one winner should be selected");
        assertEq(auction.getWinners()[0], joe, "joe should be winner");
        assertEq(auction.getWinners()[1], user, "user should be winner");
        auction.endLottery();
    }    

    function test_moreDemandAndWinners() public {
        address user = address(3);
        address joe = address(4);
        address anna = address(5);

        uint256 initialPrice = 10000;

        provideUsdc(anna, initialPrice + 10000);
        vm.startPrank(anna);
        auction.deposit(initialPrice);
        vm.stopPrank();

        provideUsdc(user, initialPrice + 10000);
        vm.startPrank(user);
        auction.deposit(initialPrice);
        vm.stopPrank();

        provideUsdc(joe, initialPrice + 10000);
        vm.startPrank(joe);
        auction.deposit(initialPrice);
        vm.stopPrank();


        vm.startPrank(seller);
        NFTLotteryTicket nftLotteryTicket = new NFTLotteryTicket("ipfs://example_uri/", false);
        nftLotteryTicket.setDepositContractAddr(address(auction));
        auction.setNftContractAddr(address(nftLotteryTicket));
        auction.setNumberOfTickets(2);
        auction.setInitPrice(initialPrice);
        auction.startLottery();
        auction.selectWinners();
        assertEq(auction.getWinners().length, 3, "More winners than tickets");
        auction.endLottery();

        vm.startPrank(anna);
        auction.mintMyNFT();
        vm.stopPrank();

        vm.startPrank(user);
        auction.mintMyNFT();
        vm.stopPrank();

        vm.startPrank(joe);
        vm.expectRevert("No tickets left to allocate");
        auction.mintMyNFT();
        vm.stopPrank();
    }   
}
