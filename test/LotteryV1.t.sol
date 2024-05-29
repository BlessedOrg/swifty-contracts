// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2, Vm } from "forge-std/Test.sol";
import "forge-std/console.sol";
import { NFTLotteryTicket } from "../src/NFTLotteryTicket.sol";
import { Lottery } from "../src/Lottery.sol";
import { USDC } from "../src/USDC.sol";

import { NFTTicketBase } from "../src/NFTTicketBase.sol";
import { BlessedFactory } from "../src/BlessedFactory.sol";
import { LotteryV1Base } from "../src/LotteryV1Base.sol";
import { LotteryV2Base } from "../src/LotteryV2Base.sol";
import { AuctionV1Base } from "../src/AuctionV1Base.sol";
import { AuctionV2Base } from "../src/AuctionV2Base.sol";

contract LotteryTest is Test {
    LotteryV1Base public lottery;
    BlessedFactory public blessedFactory;
    USDC public usdcToken;

    uint256 private sellerPrivateKey = 0xa11ce;
    uint256 private multisigWalletPrivateKey = 0xb334d;

    address seller;
    address multisigWallet;
    address operator = address(9);

    function setUp() public {
        // Generate addresses from private keys
        seller = vm.addr(sellerPrivateKey);
        multisigWallet = vm.addr(multisigWalletPrivateKey);
        vm.warp(1700819134); // mock time so Gelato round calculate works

        vm.startPrank(seller);
        // Deploy the Deposit contract with the seller address
        NFTTicketBase nftLotteryTicket = new NFTTicketBase();
        LotteryV1Base lotteryBase = new LotteryV1Base();
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

        BlessedFactory.SaleConfig memory config = BlessedFactory.SaleConfig({
            _seller: seller,
            _gelatoVrfOperator: operator,
            _blessedOperator: seller,
            _owner: seller,
            _lotteryV1TicketAmount: 123,
            _lotteryV2TicketAmount: 123,
            _auctionV1TicketAmount: 123,
            _auctionV2TicketAmount: 123,
            _ticketPrice: 100,
            _uri: "https://api.example.com/v1/",
            _usdcContractAddr: seller,
            _multisigWalletAddress: multisigWallet
        });

        blessedFactory.createSale(config);

        address lotteryBaseAddr = blessedFactory.sales(0, 0);

        lottery = LotteryV1Base(lotteryBaseAddr);

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
        lottery.changeLotteryState(LotteryV1Base.LotteryState.ACTIVE);
        assertEq(
            uint256(lottery.lotteryState()), uint256(LotteryV1Base.LotteryState.ACTIVE), "Lottery state should be ACTIVE"
        );

        vm.prank(seller);
        lottery.changeLotteryState(LotteryV1Base.LotteryState.ENDED);
        assertEq(uint256(lottery.lotteryState()), uint256(LotteryV1Base.LotteryState.ENDED), "Lottery state should be ENDED");
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
        lottery.changeLotteryState(LotteryV1Base.LotteryState.ENDED);

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

        // End the lottery and process the withdrawal
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV1Base.LotteryState.ENDED);
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
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV1Base.LotteryState.ENDED);
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
        lottery.changeLotteryState(LotteryV1Base.LotteryState.ENDED);

        // Mark some participants as winners (e.g., first two)
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(seller);
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
        lottery.changeLotteryState(LotteryV1Base.LotteryState.ACTIVE);

        // End the lottery to allow withdrawal
        vm.prank(seller);
        lottery.changeLotteryState(LotteryV1Base.LotteryState.ENDED);

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

    function test_GelatoVRF() public {
        vm.startPrank(seller);
        lottery.requestRandomness();
        vm.stopPrank();

        uint256 randomness = 0x471403f3a8764edd4d39c7748847c07098c05e5a16ed7b083b655dbab9809fae;
        uint256 requestId = 0;
        uint256 roundId = 2671924;
        bytes memory data = abi.encode(address(seller));
        bytes memory dataWithRound = abi.encode(roundId, abi.encode(requestId, data));
        uint256 prevRandom = lottery.randomNumber();
        vm.prank(operator);
        lottery.fulfillRandomness(randomness, dataWithRound);
        assertNotEq(prevRandom, lottery.randomNumber());
    }

    function test_GelatoVRFoperator() public {
        vm.startPrank(seller);
        lottery.requestRandomness();

        uint256 randomness = 0x471403f3a8764edd4d39c7748847c07098c05e5a16ed7b083b655dbab9809fae;
        uint256 requestId = 0;
        uint256 roundId = 2671924;
        bytes memory data = abi.encode(address(seller));
        bytes memory dataWithRound = abi.encode(roundId, abi.encode(requestId, data));
        vm.expectRevert("only operator");
        lottery.fulfillRandomness(randomness, dataWithRound);
        vm.stopPrank();
    }
}
