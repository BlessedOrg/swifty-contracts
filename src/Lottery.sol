// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { GelatoVRFConsumerBase } from "../lib/vrf-contracts/contracts/GelatoVRFConsumerBase.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ILotteryV2.sol";

contract Lottery is GelatoVRFConsumerBase, Ownable {
    constructor(address _seller, address _operatorAddr)
    Ownable(msg.sender) {
        seller = _seller;
        randomNumber = getRandomNumber();
        operatorAddr = _operatorAddr;
    }

    enum LotteryState {
        NOT_STARTED,
        ACTIVE,
        ENDED,
        VRF_REQUESTED,
        VRF_COMPLETED
    }

    LotteryState public lotteryState;

    address public multisigWalletAddress;
    address public seller;
    address public immutable operatorAddr;

    uint256 public minimumDepositAmount;
    uint256 public numberOfTickets;
    uint256 public randomNumber;
    address[] private eligibleParticipants;
    mapping(address => bool) public hasMinted;

    mapping(address => uint256) public deposits;
    mapping(address => bool) public winners;
    address[] public winnerAddresses;
    address[] private participants;

    address public nftContractAddr;
    address public usdcContractAddr;

    uint256 public finishAt;

    event LotteryStarted();
    event WinnerSelected(address indexed winner);
    event LotteryEnded();
    event RandomRequested(address indexed requester);
    event RandomFullfiled(uint256 number);

    modifier onlySeller() {
        require(msg.sender == seller, "Only seller can call this function");
        _;
    }

    modifier lotteryNotStarted() {
        require(lotteryState == LotteryState.NOT_STARTED, "Lottery is in active state");
        _;
    }

    modifier lotteryStarted() {
        require(lotteryState == LotteryState.ACTIVE, "Lottery is not active");
        _;
    }

    modifier lotteryEnded() {
        require(lotteryState == LotteryState.ENDED, "Lottery is not ended yet");
        _;
    }

    modifier hasNotMinted() {
        require(!hasMinted[msg.sender], "NFT already minted");
        _;
    }

    modifier whenLotteryNotActive() {
        require(lotteryState != LotteryState.ACTIVE, "Lottery is currently active");
        _;
    }

    function _operator() internal view override returns (address) {
        return operatorAddr;
    }

    function deposit(uint256 amount) public payable whenLotteryNotActive {
        require(finishAt > block.timestamp, "Deposits are not possible anymore");
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount > 0, "No funds sent");
        require(
            IERC20(usdcContractAddr).allowance(msg.sender, address(this)) >= amount, 
            "Insufficient allowance"
        );

        IERC20(usdcContractAddr).transferFrom(msg.sender, address(this), amount);
        
        if(deposits[msg.sender] == 0) {
            participants.push(msg.sender);
        }
        deposits[msg.sender] += amount;
    }

    function getParticipants() public view returns (address[] memory) {
        return participants;
    }

    function setMultisigWalletAddress(address _multisigWalletAddress) public onlyOwner {
        multisigWalletAddress = _multisigWalletAddress;
    }

    function setNftContractAddr(address _nftContractAddr) public onlyOwner {
        nftContractAddr = _nftContractAddr;
    }    

    function changeLotteryState(LotteryState _newState) public onlySeller {
        lotteryState = _newState;
    }

    function isWinner(address _participant) public view returns (bool) {
        return winners[_participant];
    }

    function getWinners() public view returns (address[] memory) {
        return winnerAddresses;
    }

    function setWinner(address _winner) public onlySeller {
        winners[_winner] = true;
        winnerAddresses.push(_winner);
    }

    function buyerWithdraw() public whenLotteryNotActive {
        require(!winners[msg.sender], "Winners cannot withdraw");

        uint256 amount = deposits[msg.sender];
        require(amount > 0, "No funds to withdraw");

        deposits[msg.sender] = 0;
        IERC20(usdcContractAddr).transfer(msg.sender, amount);
    }

    function sellerWithdraw() public onlySeller() {
        require(lotteryState == LotteryState.ENDED, "Lottery not ended");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < winnerAddresses.length; i++) {
            address winner = winnerAddresses[i];
            totalAmount += deposits[winner];
            deposits[winner] = 0; // Prevent double withdrawal
        }

        uint256 protocolTax = (totalAmount * 5) / 100; // 5% tax
        uint256 amountToSeller = totalAmount - protocolTax;

        IERC20(usdcContractAddr).transfer(multisigWalletAddress, protocolTax);
        IERC20(usdcContractAddr).transfer(seller, amountToSeller);
    }

    function requestRandomness() external onlySeller {
        _requestRandomness(abi.encode(msg.sender));
        emit RandomRequested(msg.sender);
    } 

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory) internal override {
        randomNumber = randomness;
        emit RandomFullfiled(randomness);
    }    

    function getRandomNumber () public view onlySeller returns (uint256) {
        // Replace with actual VRF result
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))); 
    }

    function selectWinners() external onlySeller {
        require(numberOfTickets > 0, "No tickets left to allocate");

        if(numberOfTickets >= eligibleParticipants.length) {
            // less demand than supply, no need for lottery. Everybody wins!
            for (uint256 i = 0; i < eligibleParticipants.length; i++) {
                address selectedWinner = eligibleParticipants[i];

                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }
            for (uint256 i = 0; i < eligibleParticipants.length; i++) {
                removeParticipant(i);
                numberOfTickets--;
            }
        } else {
            // shuffle array of winners
            for (uint j = 0; j < eligibleParticipants.length; j++) {
                uint n = j + randomNumber % (eligibleParticipants.length - j);
                address temp = eligibleParticipants[n];
                eligibleParticipants[n] = eligibleParticipants[j];
                eligibleParticipants[j] = temp;
            }

            // take the first n winners
            for (uint256 i = 0; i < numberOfTickets; i++) {
                address selectedWinner = eligibleParticipants[i];

                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    removeParticipant(i);
                    numberOfTickets--;

                    emit WinnerSelected(selectedWinner);
                }
            }
        }

        if (numberOfTickets == 0) {
            emit LotteryEnded();
        }
    }

    function setMinimumDepositAmount(uint256 _amount) public onlySeller {
        minimumDepositAmount = _amount;
    }

    function setNumberOfTickets(uint256 _numberOfTickets) public onlySeller {
        require(_numberOfTickets > 0, "Number of tickets must be greater than zero");
        numberOfTickets = _numberOfTickets;
    }

    function startLottery() public onlySeller lotteryNotStarted {
        changeLotteryState(LotteryState.ACTIVE);
        checkEligibleParticipants();
    }

    function endLottery() public onlySeller {
        changeLotteryState(LotteryState.ENDED);
        // Additional logic for ending the lottery
        // Process winners, mint NFT tickets, etc.
    }

    function getDepositedAmount(address participant) external view returns (uint256) {
        return deposits[participant];
    }

    // Function to check and mark eligible participants
    function checkEligibleParticipants() internal {
        for (uint256 i = 0; i < participants.length; i++) {
            uint256 depositedAmount = deposits[participants[i]];
            if (depositedAmount >= minimumDepositAmount) {
                // Mark this participant as eligible for the lottery
                eligibleParticipants.push(participants[i]);
            }
        }
    }

    function removeParticipant(uint256 index) internal {
        require(index < eligibleParticipants.length, "Index out of bounds");

        // If the winner is not the last element, swap it with the last element
        if (index < eligibleParticipants.length - 1) {
            eligibleParticipants[index] = eligibleParticipants[eligibleParticipants.length - 1];
        }

        // Remove the last element (now the winner)
        eligibleParticipants.pop();
    }

    function isParticipantEligible(address participant) public view returns (bool) {
        for (uint256 i = 0; i < eligibleParticipants.length; i++) {
            if (eligibleParticipants[i] == participant) {
                return true;
            }
        }
        return false;
    }

    function mintMyNFT() public hasNotMinted lotteryEnded {
        require(isWinner(msg.sender), "Caller is not a winner");
        hasMinted[msg.sender] = true;
        INFTLotteryTicket(nftContractAddr).lotteryMint(msg.sender);
    }

    function setUsdcContractAddr(address _usdcContractAddr) public onlyOwner {
        usdcContractAddr = _usdcContractAddr;
    }

    function setFinishAt(uint _finishAt) public onlySeller {
        finishAt = _finishAt;
    }

    function transferNonWinnerDeposits(address lotteryV2addr) public onlySeller {
        for(uint256 i = 0; i < participants.length; i++) {
            uint256 currentDeposit = deposits[participants[i]];
            deposits[participants[i]] = 0;
            IERC20(usdcContractAddr).transfer(lotteryV2addr, currentDeposit);
            ILotteryV2(lotteryV2addr).transferDeposit(participants[i], currentDeposit);

            if (i < participants.length - 1) {
                participants[i] = participants[participants.length - 1];
            }
            participants.pop();
        }
    }
}
